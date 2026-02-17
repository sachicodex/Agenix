import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/agenda_builder.dart';
import '../notifications/firebase_push_service.dart';
import '../notifications/local_event_notification_source.dart';
import '../notifications/local_notification_id_store.dart';
import '../notifications/notification_event_source.dart';
import '../notifications/notification_reschedule_coordinator.dart';
import '../notifications/notification_scheduler.dart';
import '../notifications/notification_service.dart';
import '../notifications/notification_settings_repository.dart';
import 'event_providers.dart';

final flutterLocalNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>((ref) {
      return FlutterLocalNotificationsPlugin();
    });

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.read(flutterLocalNotificationsPluginProvider));
});

final firebaseMessagingProvider = Provider<FirebaseMessaging>((ref) {
  return FirebaseMessaging.instance;
});

final firebasePushServiceProvider = Provider<FirebasePushService>((ref) {
  final service = FirebasePushService(
    messaging: ref.read(firebaseMessagingProvider),
    notificationService: ref.read(notificationServiceProvider),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>((ref) {
      final repository = NotificationSettingsRepository(
        SharedPreferences.getInstance,
      );
      ref.onDispose(() async {
        await repository.dispose();
      });
      return repository;
    });

final localNotificationIdStoreProvider = Provider<LocalNotificationIdStore>((
  ref,
) {
  return LocalNotificationIdStore(SharedPreferences.getInstance);
});

final notificationEventSourceProvider = Provider<NotificationEventSource>((
  ref,
) {
  return LocalEventNotificationSource(ref.read(localEventStoreProvider));
});

final agendaBuilderProvider = Provider<AgendaBuilder>((ref) {
  return const AgendaBuilder();
});

final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  return NotificationScheduler(
    notificationService: ref.read(notificationServiceProvider),
    eventSource: ref.read(notificationEventSourceProvider),
    settingsRepository: ref.read(notificationSettingsRepositoryProvider),
    idStore: ref.read(localNotificationIdStoreProvider),
    agendaBuilder: ref.read(agendaBuilderProvider),
  );
});

final notificationRescheduleCoordinatorProvider =
    Provider<NotificationRescheduleCoordinator>((ref) {
      final coordinator = NotificationRescheduleCoordinator(
        scheduler: ref.read(notificationSchedulerProvider),
        eventSource: ref.read(notificationEventSourceProvider),
        settingsRepository: ref.read(notificationSettingsRepositoryProvider),
        syncStatusStream: ref.read(syncServiceProvider).statusStream,
      );
      ref.onDispose(() async {
        await coordinator.dispose();
      });
      return coordinator;
    });
