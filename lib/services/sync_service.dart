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

  const SyncStatus({
    required this.state,
    this.lastSyncTime,
    this.error,
  });
}

class SyncService {
  SyncService(
    this._localStore,
    this._remoteSource,
  );

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
      await incrementalSync();
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

        if (result.nextSyncToken != null) {
          await _saveSyncToken(calendarId, result.nextSyncToken!);
        }
      }

      _setStatus(
        SyncStatus(state: SyncState.idle, lastSyncTime: DateTime.now()),
      );
    } catch (e) {
      _setStatus(
        SyncStatus(state: SyncState.error, error: e.toString()),
      );
    }
  }

  Future<void> incrementalSync() async {
    if (_defaultCalendarId == null || _currentRange == null) return;
    if (!await _ensureSignedIn()) return;

    _setStatus(const SyncStatus(state: SyncState.syncing));

    final range = _currentRange!;

    try {
      final calendarIds = await _getTargetCalendarIds(
        fallback: _defaultCalendarId!,
      );
      for (final calendarId in calendarIds) {
        final token = await _getSyncToken(calendarId);
        try {
          final result = await _remoteSource.listEvents(
            timeMin: range.start,
            timeMax: range.end,
            calendarId: calendarId,
            syncToken: token,
          );

          for (final remoteEvent in result.events) {
            await _applyRemoteEvent(remoteEvent);
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
              await _applyRemoteEvent(remoteEvent);
            }
            if (fallbackResult.nextSyncToken != null) {
              await _saveSyncToken(calendarId, fallbackResult.nextSyncToken!);
            }
            continue;
          }
          rethrow;
        }
      }

      _setStatus(
        SyncStatus(state: SyncState.idle, lastSyncTime: DateTime.now()),
      );
    } catch (e) {
      _setStatus(
        SyncStatus(state: SyncState.error, error: e.toString()),
      );
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
          final created = await _remoteSource.insertEvent(event: normalizedEvent);
          final updated = normalizedEvent.copyWith(
            gEventId: created.gEventId,
            dirty: false,
            deleted: false,
            pendingAction: PendingAction.none,
            updatedAtRemote: created.updatedAtRemote,
          );
          await _localStore.upsertEvent(updated);
        } else if (normalizedEvent.pendingAction == PendingAction.update) {
          if (normalizedEvent.gEventId == null) {
            final created = await _remoteSource.insertEvent(event: normalizedEvent);
            final updated = normalizedEvent.copyWith(
              gEventId: created.gEventId,
              dirty: false,
              deleted: false,
              pendingAction: PendingAction.none,
              updatedAtRemote: created.updatedAtRemote,
            );
            await _localStore.upsertEvent(updated);
          } else {
            final updatedRemote = await _remoteSource.updateEvent(
              event: normalizedEvent,
            );
            final updated = normalizedEvent.copyWith(
              dirty: false,
              pendingAction: PendingAction.none,
              updatedAtRemote: updatedRemote.updatedAtRemote,
            );
            await _localStore.upsertEvent(updated);
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
    final inferredCalendarId = looksLikeRemoteId ? parts[1] : null;
    final inferredGEventId = looksLikeRemoteId ? parts.sublist(2).join(':') : null;

    final calendarId = (inferredCalendarId != null && inferredCalendarId.isNotEmpty)
        ? inferredCalendarId
        : event.calendarId;

    final gEventId = (event.gEventId != null && event.gEventId!.isNotEmpty)
        ? event.gEventId
        : inferredGEventId;

    return event.copyWith(
      calendarId: calendarId,
      gEventId: gEventId,
    );
  }

  Future<void> _applyRemoteEvent(CalendarEvent remoteEvent) async {
    if (remoteEvent.gEventId == null) return;

    final existing = await _localStore.getByGoogleId(
      remoteEvent.gEventId!,
      remoteEvent.calendarId,
    );

    if (existing != null && existing.dirty) {
      return;
    }

    if (remoteEvent.deleted) {
      if (existing != null) {
        await _localStore.markDeleted(existing.id);
      }
      return;
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
  }

  Future<bool> _ensureSignedIn() async {
    return await GoogleCalendarService.instance.isSignedIn();
  }

  Future<List<String>> _getTargetCalendarIds({
    required String fallback,
  }) async {
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
