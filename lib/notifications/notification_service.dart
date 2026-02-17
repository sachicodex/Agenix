import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_models.dart';

class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final Map<int, Timer> _windowsTimers = <int, Timer>{};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await _configureTimezone();
    await _initializePlugin();
    await _createAndroidChannels();
    await requestPermissions();
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      await androidImplementation?.requestNotificationsPermission();
    } catch (_) {}

    try {
      await androidImplementation?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  Future<void> scheduleAgendaNotification({
    required int notificationId,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    String? payload,
  }) {
    return _schedule(
      notificationId: notificationId,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.agendaId,
          NotificationChannels.agendaName,
          channelDescription: NotificationChannels.agendaDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        windows: WindowsNotificationDetails(),
      ),
      payload: payload,
    );
  }

  Future<void> scheduleReminderNotification({
    required int notificationId,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    String? payload,
  }) {
    return _schedule(
      notificationId: notificationId,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      details: const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.remindersId,
          NotificationChannels.remindersName,
          channelDescription: NotificationChannels.remindersDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        windows: WindowsNotificationDetails(),
      ),
      payload: payload,
    );
  }

  Future<void> cancel(int id) {
    _windowsTimers.remove(id)?.cancel();
    return _plugin.cancel(id: id);
  }

  Future<void> cancelAll() {
    for (final timer in _windowsTimers.values) {
      timer.cancel();
    }
    _windowsTimers.clear();
    return _plugin.cancelAll();
  }

  Future<void> scheduleTestNotification({int secondsFromNow = 10}) async {
    await initialize();
    final now = tz.TZDateTime.now(tz.local);
    final scheduled = now.add(Duration(seconds: secondsFromNow));
    await scheduleReminderNotification(
      notificationId: 900001,
      title: 'Agenix test notification',
      body: 'If you see this, notifications are working.',
      scheduledDate: scheduled,
      payload: 'test-notification',
    );
  }

  Future<void> _schedule({
    required int notificationId,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    String? payload,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final canScheduleInOs = MsixUtils.hasPackageIdentity();
      if (!canScheduleInOs) {
        _scheduleWindowsInProcess(
          notificationId: notificationId,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          details: details,
          payload: payload,
        );
        return;
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Prefer alarmClock for best delivery reliability when app is closed.
      // If unavailable/denied on a device, fall back gracefully.
      try {
        await _plugin.zonedSchedule(
          id: notificationId,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          payload: payload,
        );
        return;
      } catch (_) {}

      try {
        await _plugin.zonedSchedule(
          id: notificationId,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: payload,
        );
        return;
      } catch (_) {}

      await _plugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
      return;
    }

    try {
      await _plugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (_) {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        // If native scheduling fails, still deliver while app is running.
        _scheduleWindowsInProcess(
          notificationId: notificationId,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          details: details,
          payload: payload,
        );
        return;
      }
      rethrow;
    }
  }

  void _scheduleWindowsInProcess({
    required int notificationId,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    String? payload,
  }) {
    _windowsTimers.remove(notificationId)?.cancel();

    final now = tz.TZDateTime.now(tz.local);
    final delay = scheduledDate.difference(now);
    if (delay <= Duration.zero) {
      unawaited(
        _plugin.show(
          id: notificationId,
          title: title,
          body: body,
          notificationDetails: details,
          payload: payload,
        ),
      );
      return;
    }

    final timer = Timer(delay, () {
      unawaited(
        _plugin.show(
          id: notificationId,
          title: title,
          body: body,
          notificationDetails: details,
          payload: payload,
        ),
      );
      _windowsTimers.remove(notificationId);
    });
    _windowsTimers[notificationId] = timer;
  }

  Future<void> _initializePlugin() async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: 'Agenix',
        appUserModelId: 'com.sachicodex.agenix',
        guid: '7f4a3103-d0c7-4dd4-bfe6-30b5fcf55d70',
      ),
    );
    await _plugin.initialize(settings: initializationSettings);
  }

  Future<void> _createAndroidChannels() async {
    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImplementation == null) {
      return;
    }

    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationChannels.agendaId,
        NotificationChannels.agendaName,
        description: NotificationChannels.agendaDescription,
        importance: Importance.defaultImportance,
      ),
    );

    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationChannels.remindersId,
        NotificationChannels.remindersName,
        description: NotificationChannels.remindersDescription,
        importance: Importance.high,
      ),
    );
  }

  Future<void> _configureTimezone() async {
    tzdata.initializeTimeZones();
    try {
      final localTzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTzName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }
}
