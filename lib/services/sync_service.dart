import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/local_event_store.dart';
import '../data/remote/remote_calendar_data_source.dart';
import '../models/calendar_event.dart';
import '../services/google_calendar_service.dart';

enum SyncState { idle, syncing, error }

class SyncStatus {
  final SyncState state;
  final DateTime? lastSyncTime;
  final String? error;

  const SyncStatus({required this.state, this.lastSyncTime, this.error});
}

class SyncService {
  SyncService(this._localStore, this._remoteSource);

  final LocalEventStore _localStore;
  final RemoteCalendarDataSource _remoteSource;

  Timer? _timer;
  DateTimeRange? _currentRange;
  String? _defaultCalendarId;
  SharedPreferences? _prefs;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus(state: SyncState.idle);

  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get status => _status;

  Future<void> start({
    required DateTimeRange range,
    required String calendarId,
  }) async {
    _currentRange = range;
    _defaultCalendarId = calendarId;
    _prefs ??= await SharedPreferences.getInstance();

    await fullSync(range: range, calendarId: calendarId);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) async {
      await incrementalSync(showProgress: false);
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> updateRange(DateTimeRange range) async {
    if (_defaultCalendarId == null) return;
    _currentRange = range;
    await fullSync(range: range, calendarId: _defaultCalendarId!);
  }

  Future<void> fullSync({
    required DateTimeRange range,
    required String calendarId,
  }) async {
    if (!await _ensureSignedIn()) return;

    _setStatus(const SyncStatus(state: SyncState.syncing));

    try {
      final calendarIds = await _getTargetCalendarIds(fallback: calendarId);
      for (final calendarId in calendarIds) {
        final result = await _remoteSource.listEvents(
          timeMin: range.start,
          timeMax: range.end,
          calendarId: calendarId,
          syncToken: null,
        );

        for (final remoteEvent in result.events) {
          await _applyRemoteEvent(remoteEvent);
        }
        await _reconcileMissingRemoteEvents(
          calendarId: calendarId,
          range: range,
          remoteEvents: result.events,
        );

        if (result.nextSyncToken != null) {
          await _saveSyncToken(calendarId, result.nextSyncToken!);
        }
      }

      _setStatus(
        SyncStatus(state: SyncState.idle, lastSyncTime: DateTime.now()),
      );
    } catch (e) {
      _setStatus(SyncStatus(state: SyncState.error, error: e.toString()));
    }
  }

  Future<bool> incrementalSync({bool showProgress = true}) async {
    if (_defaultCalendarId == null || _currentRange == null) return false;
    if (!await _ensureSignedIn()) return false;

    if (showProgress) {
      _setStatus(const SyncStatus(state: SyncState.syncing));
    }

    final range = _currentRange!;
    var hasChanges = false;

    try {
      final calendarIds = await _getTargetCalendarIds(
        fallback: _defaultCalendarId!,
      );
      for (final calendarId in calendarIds) {
        final token = await _getSyncToken(calendarId);
        try {
          final isIncremental = token != null && token.isNotEmpty;
          final result = await _remoteSource.listEvents(
            timeMin: range.start,
            timeMax: range.end,
            calendarId: calendarId,
            syncToken: token,
          );

          for (final remoteEvent in result.events) {
            final changed = await _applyRemoteEvent(remoteEvent);
            hasChanges = hasChanges || changed;
          }
          if (!isIncremental) {
            final reconciled = await _reconcileMissingRemoteEvents(
              calendarId: calendarId,
              range: range,
              remoteEvents: result.events,
            );
            hasChanges = hasChanges || reconciled;
          }

          if (result.nextSyncToken != null) {
            await _saveSyncToken(calendarId, result.nextSyncToken!);
          }
        } catch (e) {
          final errorText = e.toString();
          if (errorText.contains('410') || errorText.contains('GONE')) {
            await _clearSyncToken(calendarId);
            final fallbackResult = await _remoteSource.listEvents(
              timeMin: range.start,
              timeMax: range.end,
              calendarId: calendarId,
              syncToken: null,
            );
            for (final remoteEvent in fallbackResult.events) {
              final changed = await _applyRemoteEvent(remoteEvent);
              hasChanges = hasChanges || changed;
            }
            final reconciled = await _reconcileMissingRemoteEvents(
              calendarId: calendarId,
              range: range,
              remoteEvents: fallbackResult.events,
            );
            hasChanges = hasChanges || reconciled;
            if (fallbackResult.nextSyncToken != null) {
              await _saveSyncToken(calendarId, fallbackResult.nextSyncToken!);
            }
            continue;
          }
          rethrow;
        }
      }

      if (showProgress || hasChanges) {
        _setStatus(
          SyncStatus(state: SyncState.idle, lastSyncTime: DateTime.now()),
        );
      }
      return hasChanges;
    } catch (e) {
      _setStatus(SyncStatus(state: SyncState.error, error: e.toString()));
      return false;
    }
  }

  Future<void> pushLocalChanges() async {
    if (!await _ensureSignedIn()) return;

    final pending = await _localStore.getPendingEvents();
    if (pending.isEmpty) return;

    for (final event in pending) {
      final normalizedEvent = _normalizeRemoteIdentity(event);
      try {
        if (normalizedEvent.pendingAction == PendingAction.create) {
          final created = await _remoteSource.insertEvent(
            event: normalizedEvent,
          );
          final updated = normalizedEvent.copyWith(
            gEventId: created.gEventId,
            dirty: false,
            deleted: false,
            pendingAction: PendingAction.none,
            updatedAtRemote: created.updatedAtRemote,
          );
          await _localStore.upsertEvent(updated);
          if (updated.gEventId != null) {
            await _localStore.removeDuplicateGoogleEventCopies(
              gEventId: updated.gEventId!,
              keepEventId: updated.id,
            );
          }
        } else if (normalizedEvent.pendingAction == PendingAction.update) {
          if (normalizedEvent.gEventId == null) {
            final created = await _remoteSource.insertEvent(
              event: normalizedEvent,
            );
            final updated = normalizedEvent.copyWith(
              gEventId: created.gEventId,
              dirty: false,
              deleted: false,
              pendingAction: PendingAction.none,
              updatedAtRemote: created.updatedAtRemote,
            );
            await _localStore.upsertEvent(updated);
            if (updated.gEventId != null) {
              await _localStore.removeDuplicateGoogleEventCopies(
                gEventId: updated.gEventId!,
                keepEventId: updated.id,
              );
            }
          } else {
            var eventForRemote = normalizedEvent;
            final sourceCalendarId = _extractCalendarIdFromLocalId(
              normalizedEvent.id,
            );

            if (sourceCalendarId != null &&
                sourceCalendarId.isNotEmpty &&
                sourceCalendarId != normalizedEvent.calendarId) {
              await _remoteSource.moveEvent(
                event: normalizedEvent,
                sourceCalendarId: sourceCalendarId,
              );

              final movedLocalId = _buildRemoteLocalId(
                calendarId: normalizedEvent.calendarId,
                gEventId: normalizedEvent.gEventId!,
              );
              if (movedLocalId != normalizedEvent.id) {
                eventForRemote = normalizedEvent.copyWith(id: movedLocalId);
                await _localStore.replaceEventId(
                  oldId: normalizedEvent.id,
                  eventWithNewId: eventForRemote,
                );
              }
            }

            final updatedRemote = await _remoteSource.updateEvent(
              event: eventForRemote,
            );
            final updated = eventForRemote.copyWith(
              dirty: false,
              pendingAction: PendingAction.none,
              updatedAtRemote: updatedRemote.updatedAtRemote,
            );
            await _localStore.upsertEvent(updated);
            if (updated.gEventId != null) {
              await _localStore.removeDuplicateGoogleEventCopies(
                gEventId: updated.gEventId!,
                keepEventId: updated.id,
              );
            }
          }
        } else if (normalizedEvent.pendingAction == PendingAction.delete) {
          if (normalizedEvent.gEventId != null) {
            await _remoteSource.deleteEvent(event: normalizedEvent);
          }
          await _localStore.deleteEventById(normalizedEvent.id);
        }
      } catch (_) {
        // Keep dirty state; will retry later.
      }
    }
  }

  CalendarEvent _normalizeRemoteIdentity(CalendarEvent event) {
    final parts = event.id.split(':');
    final looksLikeRemoteId = parts.length >= 3 && parts.first == 'g';
    final inferredGEventId = looksLikeRemoteId
        ? parts.sublist(2).join(':')
        : null;

    final gEventId = (event.gEventId != null && event.gEventId!.isNotEmpty)
        ? event.gEventId
        : inferredGEventId;

    return event.copyWith(
      // Preserve edited calendar choice from local record.
      calendarId: event.calendarId,
      gEventId: gEventId,
    );
  }

  String? _extractCalendarIdFromLocalId(String localId) {
    final parts = localId.split(':');
    if (parts.length < 3 || parts.first != 'g') {
      return null;
    }
    return parts[1];
  }

  String _buildRemoteLocalId({
    required String calendarId,
    required String gEventId,
  }) {
    return 'g:$calendarId:$gEventId';
  }

  Future<bool> _applyRemoteEvent(CalendarEvent remoteEvent) async {
    if (remoteEvent.gEventId == null) return false;

    final existing = await _localStore.getByGoogleId(
      remoteEvent.gEventId!,
      remoteEvent.calendarId,
    );

    if (existing != null && existing.dirty) {
      return false;
    }

    if (remoteEvent.deleted) {
      if (existing != null) {
        await _localStore.markDeleted(existing.id);
        return true;
      }
      return false;
    }

    if (existing != null && _sameEventContent(existing, remoteEvent)) {
      return false;
    }

    final merged = (existing ?? remoteEvent).copyWith(
      title: remoteEvent.title,
      description: remoteEvent.description,
      location: remoteEvent.location,
      startDateTime: remoteEvent.startDateTime,
      endDateTime: remoteEvent.endDateTime,
      allDay: remoteEvent.allDay,
      timezone: remoteEvent.timezone,
      color: remoteEvent.color,
      reminders: remoteEvent.reminders,
      gEventId: remoteEvent.gEventId,
      calendarId: remoteEvent.calendarId,
      updatedAtRemote: remoteEvent.updatedAtRemote,
      deleted: false,
      dirty: false,
      pendingAction: PendingAction.none,
    );

    await _localStore.upsertEvent(merged);
    if (merged.gEventId != null) {
      await _localStore.removeDuplicateGoogleEventCopies(
        gEventId: merged.gEventId!,
        keepEventId: merged.id,
      );
    }
    return true;
  }

  Future<bool> _reconcileMissingRemoteEvents({
    required String calendarId,
    required DateTimeRange range,
    required List<CalendarEvent> remoteEvents,
  }) async {
    final remoteGoogleIds = remoteEvents
        .map((e) => e.gEventId)
        .whereType<String>()
        .toSet();

    final localSyncedEvents = await _localStore
        .getSyncedEventsForCalendarInRange(
          calendarId: calendarId,
          range: range,
        );

    var changed = false;
    for (final localEvent in localSyncedEvents) {
      final localGoogleId = localEvent.gEventId;
      if (localGoogleId == null || remoteGoogleIds.contains(localGoogleId)) {
        continue;
      }

      await _localStore.markDeleted(localEvent.id);
      changed = true;
    }
    return changed;
  }

  bool _sameEventContent(CalendarEvent a, CalendarEvent b) {
    if (a.title != b.title) return false;
    if (a.description != b.description) return false;
    if (a.location != b.location) return false;
    if (a.startDateTime != b.startDateTime) return false;
    if (a.endDateTime != b.endDateTime) return false;
    if (a.allDay != b.allDay) return false;
    if (a.timezone != b.timezone) return false;
    if (a.color.toARGB32() != b.color.toARGB32()) return false;
    if (a.calendarId != b.calendarId) return false;
    if (a.gEventId != b.gEventId) return false;
    if (a.reminders.length != b.reminders.length) return false;
    for (var i = 0; i < a.reminders.length; i++) {
      if (a.reminders[i] != b.reminders[i]) return false;
    }
    return true;
  }

  Future<bool> _ensureSignedIn() async {
    return await GoogleCalendarService.instance.isSignedIn();
  }

  Future<List<String>> _getTargetCalendarIds({required String fallback}) async {
    try {
      final calendars = await GoogleCalendarService.instance.getUserCalendars();
      final ids = calendars
          .map((e) => (e['id'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isNotEmpty) {
        return ids;
      }
    } catch (_) {}
    return [fallback];
  }

  void _setStatus(SyncStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  Future<String?> _getSyncToken(String calendarId) async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!.getString(_syncTokenKey(calendarId));
  }

  Future<void> _saveSyncToken(String calendarId, String token) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_syncTokenKey(calendarId), token);
  }

  Future<void> _clearSyncToken(String calendarId) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_syncTokenKey(calendarId));
  }

  String _syncTokenKey(String calendarId) => 'sync_token_$calendarId';
}
