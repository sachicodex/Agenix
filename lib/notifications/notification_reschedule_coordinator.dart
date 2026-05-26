import 'dart:async';

import '../services/sync_service.dart';
import 'notification_event_source.dart';
import 'notification_scheduler.dart';
import 'notification_settings_repository.dart';

class NotificationRescheduleCoordinator {
  NotificationRescheduleCoordinator({
    required NotificationScheduler scheduler,
    required NotificationEventSource eventSource,
    required NotificationSettingsRepository settingsRepository,
    Stream<SyncStatus>? syncStatusStream,
    Duration debounce = const Duration(seconds: 12),
  }) : _scheduler = scheduler,
       _eventSource = eventSource,
       _settingsRepository = settingsRepository,
       _syncStatusStream = syncStatusStream,
       _debounce = debounce;

  final NotificationScheduler _scheduler;
  final NotificationEventSource _eventSource;
  final NotificationSettingsRepository _settingsRepository;
  final Stream<SyncStatus>? _syncStatusStream;
  final Duration _debounce;

  StreamSubscription<void>? _eventChangesSubscription;
  StreamSubscription<SyncStatus>? _syncStatusSubscription;
  StreamSubscription<dynamic>? _settingsSubscription;
  Timer? _debounceTimer;
  bool _started = false;
  bool _rescheduleInFlight = false;
  bool _needsAnotherPass = false;
  bool _syncInProgress = false;
  bool _rescheduleAfterSync = false;
  SyncState? _lastSyncState;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    _triggerDebouncedReschedule();
    _eventChangesSubscription = _eventSource.onEventsChanged().listen((_) {
      _triggerDebouncedReschedule();
    });
    _settingsSubscription = _settingsRepository.watchSettings().skip(1).listen((
      _,
    ) {
      _triggerDebouncedReschedule();
    });
    _syncStatusSubscription = _syncStatusStream?.listen(_onSyncStatus);
  }

  void _onSyncStatus(SyncStatus status) {
    final previous = _lastSyncState;
    _lastSyncState = status.state;
    _syncInProgress = status.state == SyncState.syncing;
    if (previous == SyncState.syncing && status.state == SyncState.idle) {
      _rescheduleAfterSync = false;
      _triggerDebouncedReschedule();
    }
  }

  /// Reschedule immediately (no debounce). Use on app open and app resume.
  ///
  /// [force] is reserved for lifecycle exits where delayed notification
  /// scheduling is riskier than doing the work while the app is still alive.
  Future<void> rescheduleNow({bool force = false}) async {
    await _runQueuedReschedule(force: force);
  }

  void _triggerDebouncedReschedule() {
    if (_syncInProgress) {
      _rescheduleAfterSync = true;
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () async {
      await _runQueuedReschedule();
    });
  }

  Future<void> _runQueuedReschedule({bool force = false}) async {
    if (_syncInProgress && !force) {
      _rescheduleAfterSync = true;
      return;
    }

    if (_rescheduleInFlight) {
      _needsAnotherPass = true;
      return;
    }

    _rescheduleInFlight = true;
    try {
      if (force) {
        _rescheduleAfterSync = false;
      }
      do {
        _needsAnotherPass = false;
        await _scheduler.syncAndReschedule();
      } while (_needsAnotherPass && (!_syncInProgress || force));
    } finally {
      _rescheduleInFlight = false;
      if (_rescheduleAfterSync && !_syncInProgress) {
        _rescheduleAfterSync = false;
        _triggerDebouncedReschedule();
      }
    }
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _eventChangesSubscription?.cancel();
    await _settingsSubscription?.cancel();
    await _syncStatusSubscription?.cancel();
    _started = false;
  }
}
