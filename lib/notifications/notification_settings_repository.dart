import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'notification_models.dart';

class NotificationSettingsRepository {
  NotificationSettingsRepository(this._preferencesLoader);

  final Future<SharedPreferences> Function() _preferencesLoader;
  final StreamController<NotificationUserSettings> _controller =
      StreamController<NotificationUserSettings>.broadcast();

  static const String _defaultReminderMinutesKey =
      'notif_default_reminder_minutes';
  static const String _dailyAgendaEnabledKey = 'notif_daily_agenda_enabled';
  static const String _eventRemindersEnabledKey =
      'notif_event_reminders_enabled';

  static const int _defaultReminderMinutes = 15;

  Future<NotificationUserSettings> getSettings() async {
    final prefs = await _preferencesLoader();
    return NotificationUserSettings(
      defaultReminderMinutes:
          prefs.getInt(_defaultReminderMinutesKey) ?? _defaultReminderMinutes,
      dailyAgendaEnabled: prefs.getBool(_dailyAgendaEnabledKey) ?? true,
      eventRemindersEnabled: prefs.getBool(_eventRemindersEnabledKey) ?? true,
    );
  }

  Stream<NotificationUserSettings> watchSettings() async* {
    yield await getSettings();
    yield* _controller.stream;
  }

  Future<void> saveSettings(NotificationUserSettings settings) async {
    final prefs = await _preferencesLoader();
    await prefs.setInt(
      _defaultReminderMinutesKey,
      settings.defaultReminderMinutes,
    );
    await prefs.setBool(_dailyAgendaEnabledKey, settings.dailyAgendaEnabled);
    await prefs.setBool(
      _eventRemindersEnabledKey,
      settings.eventRemindersEnabled,
    );
    _emit(settings);
  }

  Future<void> setDefaultReminderMinutes(int value) async {
    final next = (await getSettings()).copyWith(
      defaultReminderMinutes: value.clamp(0, 7 * 24 * 60),
    );
    await saveSettings(next);
  }

  Future<void> setDailyAgendaEnabled(bool enabled) async {
    final next = (await getSettings()).copyWith(dailyAgendaEnabled: enabled);
    await saveSettings(next);
  }

  Future<void> setEventRemindersEnabled(bool enabled) async {
    final next = (await getSettings()).copyWith(eventRemindersEnabled: enabled);
    await saveSettings(next);
  }

  void _emit(NotificationUserSettings settings) {
    if (!_controller.isClosed) {
      _controller.add(settings);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
