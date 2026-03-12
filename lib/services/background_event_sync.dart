import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/local/local_event_store.dart';
import '../notifications/background_notification_rescheduler.dart';
import '../services/google_calendar_service.dart';
import '../services/local_events_sync_service.dart';

const String kEventSyncTaskName = 'event_sync_task';
const String kEventSyncOneOffPrefix = 'event_sync_oneoff';
const String kEventSyncPeriodicId = 'event_sync_periodic';

class BackgroundEventSync {
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    await Workmanager().registerPeriodicTask(
      kEventSyncPeriodicId,
      kEventSyncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> scheduleOneOffSync() async {
    if (!Platform.isAndroid) return;
    final uniqueName =
        '${kEventSyncOneOffPrefix}_${DateTime.now().millisecondsSinceEpoch}';
    await Workmanager().registerOneOffTask(
      uniqueName,
      kEventSyncTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!Platform.isAndroid) return true;

    try {
      await LocalEventStore.instance.initialize();
    } catch (_) {}

    if (task == kEventSyncTaskName) {
      GoogleCalendarService.instance.setAllowInteractiveSignIn(false);
      bool syncOk = false;
      try {
        await LocalEventsSyncService.instance.syncLocalEventsToGoogle();
        syncOk = true;
      } catch (_) {
        return false;
      } finally {
        GoogleCalendarService.instance.setAllowInteractiveSignIn(true);
      }

      if (syncOk) {
        await rescheduleNotificationsInBackground();
      }
      return true;
    }

    return false;
  });
}
