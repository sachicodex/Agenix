import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../data/local/local_event_store.dart';
import '../services/event_sync_activity_tracker.dart';
import '../services/google_calendar_service.dart';
import '../services/local_events_sync_service.dart';

const String kEventSyncNotificationChannelId = 'event_sync';
const Duration kEventSyncQuietPeriod = Duration(seconds: 25);

void initForegroundEventSync() {
  if (!Platform.isAndroid) return;
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: kEventSyncNotificationChannelId,
      channelName: 'Event sync',
      channelDescription: 'Uploads events to Google Calendar in background.',
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
    try {
      await LocalEventStore.instance.initialize();
      GoogleCalendarService.instance.setAllowInteractiveSignIn(false);

      final hasPending =
          await LocalEventsSyncService.instance.hasUnsyncedEvents();
      if (!hasPending) {
        final lastChangeMs =
            await EventSyncActivityTracker.lastChangeMs() ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastChangeMs < kEventSyncQuietPeriod.inMilliseconds) {
          return;
        }
        await FlutterForegroundTask.stopService();
        return;
      }

      await LocalEventsSyncService.instance.syncLocalEventsToGoogle();

      final stillPending =
          await LocalEventsSyncService.instance.hasUnsyncedEvents();
      if (!stillPending) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // Keep service alive for retry via next interval.
    } finally {
      GoogleCalendarService.instance.setAllowInteractiveSignIn(true);
      _running = false;
    }
  }
}

class ForegroundEventSyncService {
  static Future<void> startIfNeeded() async {
    if (!Platform.isAndroid) return;

    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'Syncing events',
      notificationText: 'Uploading to Google Calendar...',
      callback: startEventSyncCallback,
    );
  }
}
