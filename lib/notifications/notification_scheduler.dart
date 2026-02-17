import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/calendar_event.dart';
import 'agenda_builder.dart';
import 'local_notification_id_store.dart';
import 'notification_event_source.dart';
import 'notification_models.dart';
import 'notification_service.dart';
import 'notification_settings_repository.dart';

class NotificationScheduler {
  NotificationScheduler({
    required NotificationService notificationService,
    required NotificationEventSource eventSource,
    required NotificationSettingsRepository settingsRepository,
    required LocalNotificationIdStore idStore,
    required AgendaBuilder agendaBuilder,
  }) : _notificationService = notificationService,
       _eventSource = eventSource,
       _settingsRepository = settingsRepository,
       _idStore = idStore,
       _agendaBuilder = agendaBuilder;

  final NotificationService _notificationService;
  final NotificationEventSource _eventSource;
  final NotificationSettingsRepository _settingsRepository;
  final LocalNotificationIdStore _idStore;
  final AgendaBuilder _agendaBuilder;

  Future<void> syncAndReschedule({int daysAhead = 30}) async {
    await _notificationService.initialize();
    await scheduleDailyAgenda(daysAhead: daysAhead);
    await scheduleEventReminders(daysAhead: daysAhead);
  }

  Future<void> scheduleDailyAgenda({int daysAhead = 30}) async {
    final settings = await _settingsRepository.getSettings();
    final previousAgendaMap = await _idStore.getAgendaNotificationIds();

    if (!settings.dailyAgendaEnabled) {
      await _cancelIds(previousAgendaMap.values);
      await _idStore.saveAgendaNotificationIds(<String, int>{});
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    final startDay = tz.TZDateTime(tz.local, now.year, now.month, now.day);
    final endDay = startDay.add(Duration(days: daysAhead));
    final events = await _eventSource.getEventsBetween(
      startDay.toUtc(),
      endDay.toUtc(),
    );

    final nextAgendaMap = <String, int>{};
    for (var i = 0; i < daysAhead; i++) {
      final dayStart = startDay.add(Duration(days: i));
      final dayKey = _dateKey(dayStart);
      final notificationId = _stablePositiveId('agenda:$dayKey');
      final previouslyScheduledId = previousAgendaMap[dayKey];

      final scheduledAt = tz.TZDateTime(
        tz.local,
        dayStart.year,
        dayStart.month,
        dayStart.day,
        6,
      );
      if (!scheduledAt.isAfter(now)) {
        continue;
      }

      final content = _agendaBuilder.buildForDay(
        localDayStart: dayStart,
        events: events,
      );

      // Avoid re-scheduling the same pending notification repeatedly.
      if (previouslyScheduledId != notificationId) {
        await _notificationService.scheduleAgendaNotification(
          notificationId: notificationId,
          title: content.title,
          body: content.body,
          scheduledDate: scheduledAt,
          payload: 'agenda:$dayKey',
        );
      }
      nextAgendaMap[dayKey] = notificationId;
    }

    final staleIds = previousAgendaMap.entries
        .where((entry) => !nextAgendaMap.containsKey(entry.key))
        .map((entry) => entry.value);
    await _cancelIds(staleIds);
    await _idStore.saveAgendaNotificationIds(nextAgendaMap);
  }

  Future<void> scheduleEventReminders({int daysAhead = 30}) async {
    final settings = await _settingsRepository.getSettings();
    final previousEventMap = await _idStore.getEventNotificationIds();

    if (!settings.eventRemindersEnabled) {
      final allPreviousIds = previousEventMap.values.expand((ids) => ids);
      await _cancelIds(allPreviousIds);
      await _idStore.saveEventNotificationIds(<String, List<int>>{});
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    final windowEnd = now.add(Duration(days: daysAhead));
    final events = await _eventSource.getEventsBetween(
      now.toUtc(),
      windowEnd.toUtc(),
    );

    final nextEventMap = <String, List<int>>{};
    for (final event in events) {
      if (event.deleted) {
        continue;
      }

      // Chosen behavior: skip all-day reminders to avoid noisy midnight alerts.
      if (event.allDay) {
        continue;
      }

      final reminderMinutes = _resolveReminderMinutes(event, settings);
      final eventStartLocal = tz.TZDateTime.from(event.startDateTime, tz.local);
      final triggerLocal = eventStartLocal.subtract(
        Duration(minutes: reminderMinutes),
      );
      if (!triggerLocal.isAfter(now)) {
        continue;
      }

      final eventKey = event.id;
      final notificationId = _stablePositiveId(
        'event:$eventKey:${triggerLocal.millisecondsSinceEpoch}',
      );
      final previouslyScheduledIds =
          previousEventMap[eventKey]?.toSet() ?? <int>{};
      final body = _buildReminderBody(
        reminderMinutes: reminderMinutes,
        eventStartLocal: eventStartLocal,
        location: event.location,
      );

      // Avoid duplicate reminder notifications for the same event/time.
      if (!previouslyScheduledIds.contains(notificationId)) {
        await _notificationService.scheduleReminderNotification(
          notificationId: notificationId,
          title: event.title,
          body: body,
          scheduledDate: triggerLocal,
          payload: 'event:${event.id}',
        );
      }

      nextEventMap.update(
        eventKey,
        (existing) => <int>[...existing, notificationId],
        ifAbsent: () => <int>[notificationId],
      );
    }

    final staleIds = <int>[];
    for (final entry in previousEventMap.entries) {
      final eventId = entry.key;
      final previousIds = entry.value.toSet();
      final nextIds = nextEventMap[eventId]?.toSet() ?? <int>{};
      staleIds.addAll(previousIds.difference(nextIds));
    }

    await _cancelIds(staleIds);
    await _idStore.saveEventNotificationIds(nextEventMap);
  }

  Future<void> cancelAll() async {
    final agendaMap = await _idStore.getAgendaNotificationIds();
    final eventMap = await _idStore.getEventNotificationIds();

    await _cancelIds(agendaMap.values);
    await _cancelIds(eventMap.values.expand((ids) => ids));
    await _idStore.clearAll();
  }

  Future<void> cancelForEvent(String eventId) async {
    final eventMap = await _idStore.getEventNotificationIds();
    final ids = eventMap[eventId] ?? const <int>[];
    await _cancelIds(ids);
    eventMap.remove(eventId);
    await _idStore.saveEventNotificationIds(eventMap);
  }

  int _resolveReminderMinutes(
    CalendarEvent event,
    NotificationUserSettings settings,
  ) {
    if (event.reminders.isNotEmpty) {
      return event.reminders.first.clamp(0, 7 * 24 * 60);
    }
    return settings.defaultReminderMinutes.clamp(0, 7 * 24 * 60);
  }

  String _buildReminderBody({
    required int reminderMinutes,
    required DateTime eventStartLocal,
    required String location,
  }) {
    final startText = DateFormat('h:mm a').format(eventStartLocal);
    final base = 'In $reminderMinutes min - $startText';
    if (location.trim().isEmpty) {
      return base;
    }
    return '$base - ${location.trim()}';
  }

  Future<void> _cancelIds(Iterable<int> ids) async {
    for (final id in ids.toSet()) {
      await _notificationService.cancel(id);
    }
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int _stablePositiveId(String value) {
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    if (hash == 0) {
      return 1;
    }
    return hash;
  }
}
