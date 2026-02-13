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
  Timer? _rangeUpdateDebounceTimer;
  DateTimeRange? _currentRange;
  String? _defaultCalendarId;
  SharedPreferences? _prefs;
  bool _backgroundSyncInProgress = false;
  Future<void>? _pushLocalChangesInFlight;
  bool _pushLocalChangesNeedsAnotherPass = false;

  // Keep this aligned with LocalEventStore database version.
  static const int _localDbSchemaVersion = 3;
  static const int _syncEngineVersion = 1;
  static const Duration _startupSyncFreshWindow = Duration(minutes: 5);
  static const Duration _rangeSyncDebounce = Duration(milliseconds: 320);
  static const String _prefLastSuccessfulSyncMs = 'sync_last_successful_ms';
  static const String _prefKnownDbVersion = 'sync_known_db_version';
  static const String _prefKnownEngineVersion = 'sync_known_engine_version';

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

    final lastSyncTime = _getStoredLastSuccessfulSyncTime();
    if (lastSyncTime != null) {
      _setStatus(SyncStatus(state: SyncState.idle, lastSyncTime: lastSyncTime));
    }
    await _runStartupSync(range: range, calendarId: calendarId);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) async {
      await _runBackgroundSyncTask(() async {
        await pushLocalChanges();
        await incrementalSync(showProgress: false);
      });
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _rangeUpdateDebounceTimer?.cancel();
    _rangeUpdateDebounceTimer = null;
  }

  Future<void> updateRange(DateTimeRange range) async {
    if (_defaultCalendarId == null) return;
    _currentRange = range;
    _rangeUpdateDebounceTimer?.cancel();
    _rangeUpdateDebounceTimer = Timer(_rangeSyncDebounce, () async {
      await _runBackgroundSyncTask(() async {
        await pushLocalChanges();
        await incrementalSync(showProgress: false);
      });
    });
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
      await _persistSuccessfulSyncMetadata();
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
      await _persistSuccessfulSyncMetadata();
      return hasChanges;
    } catch (e) {
      _setStatus(SyncStatus(state: SyncState.error, error: e.toString()));
      return false;
    }
  }

  Future<void> pushLocalChanges() async {
    if (!await _ensureSignedIn()) return;

    if (_pushLocalChangesInFlight != null) {
      _pushLocalChangesNeedsAnotherPass = true;
      await _pushLocalChangesInFlight;
      return;
    }

    final inFlight = _runQueuedPushLocalChanges();
    _pushLocalChangesInFlight = inFlight;
    try {
      await inFlight;
    } finally {
      if (identical(_pushLocalChangesInFlight, inFlight)) {
        _pushLocalChangesInFlight = null;
      }
    }
  }

  Future<void> _runQueuedPushLocalChanges() async {
    do {
      _pushLocalChangesNeedsAnotherPass = false;
      await _pushLocalChangesOnce();
    } while (_pushLocalChangesNeedsAnotherPass);
  }

  Future<void> _pushLocalChangesOnce() async {
    final pending = await _localStore.getPendingEvents();
    if (pending.isEmpty) return;

    for (final event in pending) {
      final normalizedEvent = _normalizeRemoteIdentity(event);
      try {
        if (normalizedEvent.pendingAction == PendingAction.create) {
          final created = await _remoteSource.insertEvent(
            event: normalizedEvent,
          );
          final remoteUpdatedAt =
              created.updatedAtRemote ?? DateTime.now().toUtc();
          final remoteLocalId =
              created.gEventId != null && created.gEventId!.isNotEmpty
              ? _buildRemoteLocalId(
                  calendarId: normalizedEvent.calendarId,
                  gEventId: created.gEventId!,
                )
              : normalizedEvent.id;
          final updated = normalizedEvent.copyWith(
            id: remoteLocalId,
            gEventId: created.gEventId,
            dirty: false,
            deleted: false,
            pendingAction: PendingAction.none,
            updatedAtRemote: remoteUpdatedAt,
          );
          final latestLocal = await _localStore.getById(normalizedEvent.id);
          if (_hasNewerLocalMutation(latestLocal, normalizedEvent)) {
            final rebased = _rebaseLocalEventOnRemoteAck(
              latest: latestLocal!,
              pushedSnapshot: normalizedEvent,
              remoteGEventId: created.gEventId,
              remoteUpdatedAt: remoteUpdatedAt,
            ).copyWith(id: remoteLocalId);
            await _upsertEventWithIdentityTransition(
              oldId: normalizedEvent.id,
              event: rebased,
            );
          } else {
            await _upsertEventWithIdentityTransition(
              oldId: normalizedEvent.id,
              event: updated,
            );
          }
          if (updated.gEventId != null) {
            await _localStore.removeDuplicateGoogleEventCopies(
              gEventId: updated.gEventId!,
              keepEventId: remoteLocalId,
            );
          }
        } else if (normalizedEvent.pendingAction == PendingAction.update) {
          if (normalizedEvent.gEventId == null) {
            final created = await _remoteSource.insertEvent(
              event: normalizedEvent,
            );
            final remoteUpdatedAt =
                created.updatedAtRemote ?? DateTime.now().toUtc();
            final remoteLocalId =
                created.gEventId != null && created.gEventId!.isNotEmpty
                ? _buildRemoteLocalId(
                    calendarId: normalizedEvent.calendarId,
                    gEventId: created.gEventId!,
                  )
                : normalizedEvent.id;
            final updated = normalizedEvent.copyWith(
              id: remoteLocalId,
              gEventId: created.gEventId,
              dirty: false,
              deleted: false,
              pendingAction: PendingAction.none,
              updatedAtRemote: remoteUpdatedAt,
            );
            final latestLocal = await _localStore.getById(normalizedEvent.id);
            if (_hasNewerLocalMutation(latestLocal, normalizedEvent)) {
              final rebased = _rebaseLocalEventOnRemoteAck(
                latest: latestLocal!,
                pushedSnapshot: normalizedEvent,
                remoteGEventId: created.gEventId,
                remoteUpdatedAt: remoteUpdatedAt,
              ).copyWith(id: remoteLocalId);
              await _upsertEventWithIdentityTransition(
                oldId: normalizedEvent.id,
                event: rebased,
              );
            } else {
              await _upsertEventWithIdentityTransition(
                oldId: normalizedEvent.id,
                event: updated,
              );
            }
            if (updated.gEventId != null) {
              await _localStore.removeDuplicateGoogleEventCopies(
                gEventId: updated.gEventId!,
                keepEventId: remoteLocalId,
              );
            }
          } else {
            var eventForRemote = normalizedEvent;
            var sourceCalendarId = _extractCalendarIdFromLocalId(
              normalizedEvent.id,
            );
            if ((sourceCalendarId == null || sourceCalendarId.isEmpty) &&
                normalizedEvent.gEventId != null) {
              final syncedCopy = await _localStore.getSyncedCopyByGoogleId(
                gEventId: normalizedEvent.gEventId!,
                excludeEventId: normalizedEvent.id,
              );
              sourceCalendarId = syncedCopy?.calendarId;
            }

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
                final latestBeforeIdMove = await _localStore.getById(
                  normalizedEvent.id,
                );
                final shouldCarryLatestMutation = _hasNewerLocalMutation(
                  latestBeforeIdMove,
                  normalizedEvent,
                );
                final sourceForMove =
                    shouldCarryLatestMutation && latestBeforeIdMove != null
                    ? latestBeforeIdMove
                    : normalizedEvent;
                eventForRemote = sourceForMove.copyWith(
                  id: movedLocalId,
                  calendarId: normalizedEvent.calendarId,
                  gEventId: normalizedEvent.gEventId,
                );
                await _localStore.replaceEventId(
                  oldId: normalizedEvent.id,
                  eventWithNewId: eventForRemote,
                );
              }
            }

            final updatedRemote = await _remoteSource.updateEvent(
              event: eventForRemote,
            );
            final remoteUpdatedAt =
                updatedRemote.updatedAtRemote ?? DateTime.now().toUtc();
            final updated = eventForRemote.copyWith(
              dirty: false,
              pendingAction: PendingAction.none,
              updatedAtRemote: remoteUpdatedAt,
            );
            final latestLocal = await _localStore.getById(eventForRemote.id);
            if (_hasNewerLocalMutation(latestLocal, eventForRemote)) {
              final rebased = _rebaseLocalEventOnRemoteAck(
                latest: latestLocal!,
                pushedSnapshot: eventForRemote,
                remoteGEventId: eventForRemote.gEventId,
                remoteUpdatedAt: remoteUpdatedAt,
              );
              await _localStore.upsertEvent(rebased);
            } else {
              await _localStore.upsertEvent(updated);
            }
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
      } catch (e) {
        debugPrint('Local push failed for event ${normalizedEvent.id}: $e');
        // Keep dirty state; will retry later.
      }
    }
  }

  Future<void> _upsertEventWithIdentityTransition({
    required String oldId,
    required CalendarEvent event,
  }) async {
    if (event.id != oldId) {
      await _localStore.replaceEventId(oldId: oldId, eventWithNewId: event);
      return;
    }
    await _localStore.upsertEvent(event);
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

    final conflictingDirty = await _localStore.getAnyByGoogleId(
      remoteEvent.gEventId!,
    );
    if (conflictingDirty != null && conflictingDirty.dirty) {
      return false;
    }

    final existing = await _localStore.getByGoogleId(
      remoteEvent.gEventId!,
      remoteEvent.calendarId,
    );

    if (existing != null && existing.dirty) {
      return false;
    }

    // Guard against out-of-order remote snapshots (or same-timestamp echoes)
    // right after a successful local push.
    if (existing != null && _isOlderRemoteSnapshot(existing, remoteEvent)) {
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
        preserveDirty: true,
      );
    }
    return true;
  }

  bool _isOlderRemoteSnapshot(CalendarEvent local, CalendarEvent remote) {
    final localUpdated = local.updatedAtRemote;
    final remoteUpdated = remote.updatedAtRemote;
    if (localUpdated == null || remoteUpdated == null) {
      return false;
    }
    return !remoteUpdated.isAfter(localUpdated);
  }

  bool _hasNewerLocalMutation(
    CalendarEvent? latestLocal,
    CalendarEvent pushedSnapshot,
  ) {
    if (latestLocal == null) return false;
    if (latestLocal.id != pushedSnapshot.id) return false;
    if (latestLocal.pendingAction == PendingAction.delete &&
        pushedSnapshot.pendingAction != PendingAction.delete) {
      return true;
    }
    if (!latestLocal.dirty && latestLocal.pendingAction == PendingAction.none) {
      return false;
    }
    return !_eventPayloadEquals(latestLocal, pushedSnapshot);
  }

  bool _eventPayloadEquals(CalendarEvent a, CalendarEvent b) {
    if (a.title != b.title) return false;
    if (a.description != b.description) return false;
    if (a.location != b.location) return false;
    if (a.startDateTime != b.startDateTime) return false;
    if (a.endDateTime != b.endDateTime) return false;
    if (a.allDay != b.allDay) return false;
    if (a.timezone != b.timezone) return false;
    if (a.color.toARGB32() != b.color.toARGB32()) return false;
    if (a.calendarId != b.calendarId) return false;
    if (a.deleted != b.deleted) return false;
    if (a.reminders.length != b.reminders.length) return false;
    for (var i = 0; i < a.reminders.length; i++) {
      if (a.reminders[i] != b.reminders[i]) return false;
    }
    return true;
  }

  CalendarEvent _rebaseLocalEventOnRemoteAck({
    required CalendarEvent latest,
    required CalendarEvent pushedSnapshot,
    required String? remoteGEventId,
    required DateTime remoteUpdatedAt,
  }) {
    final resolvedGEventId =
        remoteGEventId ?? latest.gEventId ?? pushedSnapshot.gEventId;
    final nextPending = latest.pendingAction == PendingAction.delete
        ? PendingAction.delete
        : PendingAction.update;

    return latest.copyWith(
      gEventId: resolvedGEventId,
      updatedAtRemote: remoteUpdatedAt,
      dirty: true,
      pendingAction: nextPending,
    );
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

  Future<void> _runStartupSync({
    required DateTimeRange range,
    required String calendarId,
  }) async {
    final hasPendingLocalChanges =
        (await _localStore.getPendingEvents()).isNotEmpty;
    if (hasPendingLocalChanges) {
      await pushLocalChanges();
    }

    final shouldForceFull = await _shouldForceFullSyncOnStartup();
    final isFresh = _isLastSyncFresh();

    if (shouldForceFull) {
      await fullSync(range: range, calendarId: calendarId);
      return;
    }

    // Avoid redundant startup network calls when we already synced very recently.
    if (isFresh && !hasPendingLocalChanges) {
      return;
    }

    final hasToken = await _hasAtLeastOneSyncToken(
      fallbackCalendarId: calendarId,
    );
    if (hasToken) {
      await incrementalSync(showProgress: false);
    } else {
      await fullSync(range: range, calendarId: calendarId);
    }
  }

  Future<bool> _shouldForceFullSyncOnStartup() async {
    _prefs ??= await SharedPreferences.getInstance();
    final knownDbVersion = _prefs!.getInt(_prefKnownDbVersion) ?? -1;
    final knownEngineVersion = _prefs!.getInt(_prefKnownEngineVersion) ?? -1;
    final changed =
        knownDbVersion != _localDbSchemaVersion ||
        knownEngineVersion != _syncEngineVersion;
    if (!changed) return false;

    await _prefs!.setInt(_prefKnownDbVersion, _localDbSchemaVersion);
    await _prefs!.setInt(_prefKnownEngineVersion, _syncEngineVersion);
    return true;
  }

  bool _isLastSyncFresh() {
    final lastSync = _getStoredLastSuccessfulSyncTime();
    if (lastSync == null) return false;
    return DateTime.now().difference(lastSync) <= _startupSyncFreshWindow;
  }

  DateTime? _getStoredLastSuccessfulSyncTime() {
    if (_prefs == null) return null;
    final epochMs = _prefs!.getInt(_prefLastSuccessfulSyncMs);
    if (epochMs == null || epochMs <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(epochMs);
  }

  Future<void> _persistSuccessfulSyncMetadata() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(
      _prefLastSuccessfulSyncMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<bool> _hasAtLeastOneSyncToken({
    required String fallbackCalendarId,
  }) async {
    final calendarIds = await _getTargetCalendarIds(
      fallback: fallbackCalendarId,
    );
    for (final calendarId in calendarIds) {
      final token = await _getSyncToken(calendarId);
      if (token != null && token.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<void> _runBackgroundSyncTask(Future<void> Function() task) async {
    if (_backgroundSyncInProgress) return;
    _backgroundSyncInProgress = true;
    try {
      await task();
    } finally {
      _backgroundSyncInProgress = false;
    }
  }
}
