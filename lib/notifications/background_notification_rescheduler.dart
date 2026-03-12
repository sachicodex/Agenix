import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/local_event_store.dart';
import 'agenda_builder.dart';
import 'local_event_notification_source.dart';
import 'local_notification_id_store.dart';
import 'notification_scheduler.dart';
import 'notification_service.dart';
import 'notification_settings_repository.dart';

/// Standalone notification rescheduler for use in WorkManager/background context.
/// Ensures reminders are scheduled after background sync (no Riverpod).
Future<bool> rescheduleNotificationsInBackground() async {
  if (!Platform.isAndroid) return true;

  try {
    final prefs = await SharedPreferences.getInstance();
    final plugin = FlutterLocalNotificationsPlugin();
    final notificationService = NotificationService(plugin);
    final settingsRepo = NotificationSettingsRepository(() async => prefs);
    final idStore = LocalNotificationIdStore(() async => prefs);
    final eventSource = LocalEventNotificationSource(LocalEventStore.instance);
    final agendaBuilder = const AgendaBuilder();
    final scheduler = NotificationScheduler(
      notificationService: notificationService,
      eventSource: eventSource,
      settingsRepository: settingsRepo,
      idStore: idStore,
      agendaBuilder: agendaBuilder,
    );

    await scheduler.syncAndReschedule();
    return true;
  } catch (_) {
    return false;
  }
}
