import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import '../data/local/local_event_store.dart';
import '../data/remote/remote_calendar_data_source.dart';
import '../notifications/background_notification_rescheduler.dart';
import 'background_sync_config.dart';
import '../services/google_calendar_service.dart';
import '../services/sync_service.dart';

const String kEventSyncTaskName = 'event_sync_task';
const String kEventSyncOneOffUniqueName = 'event_sync_oneoff';
const String kEventSyncPeriodicId = 'event_sync_periodic';
typedef BackgroundSyncStatusCallback = Future<void> Function(String text);

class BackgroundSyncOutcome {
  const BackgroundSyncOutcome({
    required this.success,
    required this.hadPendingLocalChanges,
    required this.stillPendingLocalChanges,
    this.error,
  });

  final bool success;
  final bool hadPendingLocalChanges;
  final bool stillPendingLocalChanges;
  final String? error;
}

class BackgroundEventSync {
  static Timer? _oneOffSyncDebounceTimer;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(callbackDispatcher);
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

  static Future<void> scheduleOneOffSync({bool immediate = false}) async {
    if (!Platform.isAndroid) return;
    if (immediate) {
      _oneOffSyncDebounceTimer?.cancel();
      await _registerOneOffSync();
      return;
    }
    _oneOffSyncDebounceTimer?.cancel();
    _oneOffSyncDebounceTimer = Timer(
      BackgroundSyncConfig.androidOneOffScheduleDebounce,
      () {
        unawaited(_registerOneOffSync());
      },
    );
  }

  static Future<void> _registerOneOffSync() async {
    if (!Platform.isAndroid) return;
    await Workmanager().registerOneOffTask(
      kEventSyncOneOffUniqueName,
      kEventSyncTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  static Future<BackgroundSyncOutcome> runBackgroundSyncCycle({
    bool rescheduleNotifications = true,
    BackgroundSyncStatusCallback? onStatus,
  }) async {
    return runPendingUploadCycle(
      rescheduleNotifications: rescheduleNotifications,
      onStatus: onStatus,
    );
  }

  static Future<BackgroundSyncOutcome> runPendingUploadCycle({
    bool rescheduleNotifications = true,
    BackgroundSyncStatusCallback? onStatus,
  }) async {
    bool hadPendingLocalChanges = false;

    try {
      await onStatus?.call(
        BackgroundSyncConfig.androidForegroundNotificationPreparingText,
      );

      await LocalEventStore.instance.initialize();
      await GoogleCalendarService.instance.initialize();
      GoogleCalendarService.instance.setAllowInteractiveSignIn(false);

      hadPendingLocalChanges =
          (await LocalEventStore.instance.getPendingEvents()).isNotEmpty;
      final signedIn = await GoogleCalendarService.instance.isSignedIn();
      if (!signedIn) {
        return BackgroundSyncOutcome(
          success: false,
          hadPendingLocalChanges: hadPendingLocalChanges,
          stillPendingLocalChanges: hadPendingLocalChanges,
          error: 'Not signed in',
        );
      }

      await onStatus?.call(
        BackgroundSyncConfig.androidForegroundNotificationActiveText,
      );

      final syncService = SyncService(
        LocalEventStore.instance,
        RemoteCalendarDataSource(GoogleCalendarService.instance),
      );
      await syncService.pushLocalChanges(retryWhenLocked: true);

      final stillPendingLocalChanges =
          (await LocalEventStore.instance.getPendingEvents()).isNotEmpty;

      if (rescheduleNotifications) {
        await onStatus?.call(
          BackgroundSyncConfig.androidForegroundNotificationFinalizingText,
        );
        await rescheduleNotificationsInBackground();
      }

      return BackgroundSyncOutcome(
        success: !stillPendingLocalChanges,
        hadPendingLocalChanges: hadPendingLocalChanges,
        stillPendingLocalChanges: stillPendingLocalChanges,
      );
    } catch (e) {
      final stillPendingLocalChanges =
          (await LocalEventStore.instance.getPendingEvents()).isNotEmpty;
      debugPrint('Background sync failed: $e');
      return BackgroundSyncOutcome(
        success: false,
        hadPendingLocalChanges: hadPendingLocalChanges,
        stillPendingLocalChanges: stillPendingLocalChanges,
        error: e.toString(),
      );
    } finally {
      GoogleCalendarService.instance.setAllowInteractiveSignIn(true);
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!Platform.isAndroid) return true;

    if (task == kEventSyncTaskName) {
      final outcome = await BackgroundEventSync.runBackgroundSyncCycle(
        rescheduleNotifications: false,
      );
      return outcome.success;
    }

    return false;
  });
}
