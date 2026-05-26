class NotificationUserSettings {
  const NotificationUserSettings({
    required this.defaultReminderMinutes,
    required this.dailyAgendaEnabled,
    required this.eventRemindersEnabled,
    required this.dailyAgendaMinutesAfterMidnight,
  });

  final int defaultReminderMinutes;
  final bool dailyAgendaEnabled;
  final bool eventRemindersEnabled;
  final int dailyAgendaMinutesAfterMidnight;

  NotificationUserSettings copyWith({
    int? defaultReminderMinutes,
    bool? dailyAgendaEnabled,
    bool? eventRemindersEnabled,
    int? dailyAgendaMinutesAfterMidnight,
  }) {
    return NotificationUserSettings(
      defaultReminderMinutes:
          defaultReminderMinutes ?? this.defaultReminderMinutes,
      dailyAgendaEnabled: dailyAgendaEnabled ?? this.dailyAgendaEnabled,
      eventRemindersEnabled:
          eventRemindersEnabled ?? this.eventRemindersEnabled,
      dailyAgendaMinutesAfterMidnight:
          dailyAgendaMinutesAfterMidnight ?? this.dailyAgendaMinutesAfterMidnight,
    );
  }
}

class NotificationChannels {
  static const String agendaId = 'agenda';
  static const String agendaName = 'Daily agenda';
  static const String agendaDescription =
      'Daily agenda summary notifications around 6:00 AM.';

  static const String remindersId = 'reminders';
  static const String remindersName = 'Event reminders';
  static const String remindersDescription =
      'High-priority reminders before events.';

  static const String pushId = 'push';
  static const String pushName = 'Push notifications';
  static const String pushDescription = 'Firebase Cloud Messaging alerts.';
}
