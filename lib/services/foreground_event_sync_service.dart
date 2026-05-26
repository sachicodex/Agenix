import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../data/local/local_event_store.dart';
import 'background_event_sync.dart';
import 'background_sync_config.dart';
import '../services/event_sync_activity_tracker.dart';
import '../services/google_calendar_service.dart';

const String kEventSyncNotificationChannelId = 'event_sync';
const Duration kEventSyncQuietPeriod = Duration(seconds: 25);

void initForegroundEventSync() {
  if (!Platform.isAndroid ||
      !BackgroundSyncConfig.enableAndroidForegroundSyncNotification) {
    return;
  }
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: kEventSyncNotificationChannelId,
      channelName: 'Event sync',
      channelDescription: 'Keeps Agenix event sync running in background.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      iconData: const NotificationIconData(
        resType: ResourceType.mipmap,
        resPrefix: ResourcePrefix.ic,
        name: 'launcher',
      ),
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: const ForegroundTaskOptions(
      interval: 5000,
      isOnceEvent: false,
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

@pragma('vm:entry-point')
void startEventSyncCallback() {
  FlutterForegroundTask.setTaskHandler(EventSyncTaskHandler());
}

class EventSyncTaskHandler extends TaskHandler {
  bool _running = false;
  int _attempts = 0;
  String _notificationText =
      BackgroundSyncConfig.androidForegroundNotificationPreparingText;

  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {
    unawaited(_syncOnce());
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    unawaited(_syncOnce());
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
    GoogleCalendarService.instance.setAllowInteractiveSignIn(true);
  }

  Future<void> _syncOnce() async {
    if (_running) return;
    _running = true;
    var shouldStopService = false;
    try {
      GoogleCalendarService.instance.setAllowInteractiveSignIn(false);
      await _updateNotification(
        BackgroundSyncConfig.androidForegroundNotificationPreparingText,
      );

      final outcome = await BackgroundEventSync.runPendingUploadCycle(
        rescheduleNotifications: false,
        onStatus: _updateNotification,
      );
      _attempts++;

      if (outcome.success && !outcome.stillPendingLocalChanges) {
        shouldStopService = true;
        await _updateNotification(
          BackgroundSyncConfig.androidForegroundNotificationCompleteText,
        );
        return;
      }

      if (!outcome.hadPendingLocalChanges) {
        final lastChangeMs = await EventSyncActivityTracker.lastChangeMs() ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastChangeMs < kEventSyncQuietPeriod.inMilliseconds) {
          return;
        }
        shouldStopService = true;
      }

      if (_attempts >=
          BackgroundSyncConfig.androidForegroundUploadMaxAttempts) {
        await BackgroundEventSync.scheduleOneOffSync(immediate: true);
        shouldStopService = true;
      }
    } catch (_) {
      _attempts++;
      if (_attempts >=
          BackgroundSyncConfig.androidForegroundUploadMaxAttempts) {
        await BackgroundEventSync.scheduleOneOffSync(immediate: true);
        shouldStopService = true;
      }
    } finally {
      await _stopServiceIfIdle(force: shouldStopService);
      GoogleCalendarService.instance.setAllowInteractiveSignIn(true);
      _running = false;
    }
  }

  Future<void> _updateNotification(String text) async {
    _notificationText = text;
    await FlutterForegroundTask.updateService(
      notificationTitle:
          BackgroundSyncConfig.androidForegroundNotificationTitle,
      notificationText: _notificationText,
    );
  }

  Future<void> _stopServiceIfIdle({bool force = false}) async {
    final hasPendingLocalChanges =
        (await LocalEventStore.instance.getPendingEvents()).isNotEmpty;
    if (!force && hasPendingLocalChanges) {
      return;
    }
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

class ForegroundEventSyncService {
  static Future<void> startIfNeeded() async {
    if (!Platform.isAndroid) {
      return;
    }

    await LocalEventStore.instance.initialize();
    final hasPendingLocalChanges = await LocalEventStore.instance
        .getPendingEvents();
    if (hasPendingLocalChanges.isEmpty) {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      return;
    }

    if (!BackgroundSyncConfig.enableAndroidForegroundSyncNotification) {
      await BackgroundEventSync.scheduleOneOffSync(immediate: true);
      return;
    }

    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle:
            BackgroundSyncConfig.androidForegroundNotificationTitle,
        notificationText:
            BackgroundSyncConfig.androidForegroundNotificationPreparingText,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle:
          BackgroundSyncConfig.androidForegroundNotificationTitle,
      notificationText:
          BackgroundSyncConfig.androidForegroundNotificationPreparingText,
      callback: startEventSyncCallback,
    );
  }
}
