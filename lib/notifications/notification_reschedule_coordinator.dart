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
    Duration debounce = const Duration(seconds: 2),
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
  SyncState? _lastSyncState;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    await _scheduler.syncAndReschedule();
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
    if (previous == SyncState.syncing && status.state == SyncState.idle) {
      _triggerDebouncedReschedule();
    }
  }

  void _triggerDebouncedReschedule() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () async {
      await _runQueuedReschedule();
    });
  }

  Future<void> _runQueuedReschedule() async {
    if (_rescheduleInFlight) {
      _needsAnotherPass = true;
      return;
    }

    _rescheduleInFlight = true;
    try {
      do {
        _needsAnotherPass = false;
        await _scheduler.syncAndReschedule();
      } while (_needsAnotherPass);
    } finally {
      _rescheduleInFlight = false;
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
