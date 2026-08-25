import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import '../data/local/local_event_store.dart';
import '../data/remote/remote_calendar_data_source.dart';
import 'auth_storage_service.dart';
import 'google_calendar_service.dart';
import 'sync_service.dart';

const String kEventSyncTaskName = 'event_sync_task';
const String kEventSyncOneOffUniqueName = 'event_sync_oneoff';
const String kEventSyncPeriodicId = 'event_sync_periodic';

/// Background calendar synchronization only. This service deliberately does
/// not create, schedule, or display notifications.
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
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> scheduleOneOffSync({bool immediate = false}) async {
    if (!Platform.isAndroid) return;
    _oneOffSyncDebounceTimer?.cancel();
    if (immediate) return _registerOneOffSync();
    _oneOffSyncDebounceTimer = Timer(
      const Duration(seconds: 6),
      () => unawaited(_registerOneOffSync()),
    );
  }

  static Future<void> _registerOneOffSync() => Workmanager().registerOneOffTask(
    kEventSyncOneOffUniqueName,
    kEventSyncTaskName,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );

  static Future<bool> runSyncCycle() async {
    try {
      await LocalEventStore.instance.initialize();
      await GoogleCalendarService.instance.initialize();
      GoogleCalendarService.instance.setAllowInteractiveSignIn(false);
      if (!await GoogleCalendarService.instance.isSignedIn()) return false;
      final calendarId = await AuthStorageService().getDefaultCalendarId();
      if (calendarId == null || calendarId.isEmpty) return false;
      final now = DateTime.now();
      await SyncService(
        LocalEventStore.instance,
        RemoteCalendarDataSource(GoogleCalendarService.instance),
      ).backgroundPushAndPull(
        calendarId: calendarId,
        range: DateTimeRange(
          start: now.subtract(const Duration(days: 1)),
          end: now.add(const Duration(days: 31)),
        ),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      GoogleCalendarService.instance.setAllowInteractiveSignIn(true);
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    return task == kEventSyncTaskName &&
        await BackgroundEventSync.runSyncCycle();
  });
}
