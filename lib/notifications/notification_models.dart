class NotificationUserSettings {
  const NotificationUserSettings({
    required this.defaultReminderMinutes,
    required this.dailyAgendaEnabled,
    required this.eventRemindersEnabled,
  });

  final int defaultReminderMinutes;
  final bool dailyAgendaEnabled;
  final bool eventRemindersEnabled;

  NotificationUserSettings copyWith({
    int? defaultReminderMinutes,
    bool? dailyAgendaEnabled,
    bool? eventRemindersEnabled,
  }) {
    return NotificationUserSettings(
      defaultReminderMinutes:
          defaultReminderMinutes ?? this.defaultReminderMinutes,
      dailyAgendaEnabled: dailyAgendaEnabled ?? this.dailyAgendaEnabled,
      eventRemindersEnabled:
          eventRemindersEnabled ?? this.eventRemindersEnabled,
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
}
