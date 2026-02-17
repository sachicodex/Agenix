import 'package:intl/intl.dart';

import '../models/calendar_event.dart';

class AgendaNotificationContent {
  const AgendaNotificationContent({required this.title, required this.body});

  final String title;
  final String body;
}

class AgendaBuilder {
  const AgendaBuilder();

  AgendaNotificationContent buildForDay({
    required DateTime localDayStart,
    required List<CalendarEvent> events,
  }) {
    final dayStart = DateTime(
      localDayStart.year,
      localDayStart.month,
      localDayStart.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final sameDayEvents = events.where((event) {
      final start = event.startDateTime.toLocal();
      final end = event.endDateTime.toLocal();
      return start.isBefore(dayEnd) && end.isAfter(dayStart);
    }).toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));

    if (sameDayEvents.isEmpty) {
      return const AgendaNotificationContent(
        title: "Today's Agenda",
        body: 'No events today \u{1F389}',
      );
    }

    CalendarEvent? firstTimed;
    for (final event in sameDayEvents) {
      if (!event.allDay) {
        firstTimed = event;
        break;
      }
    }

    final firstEvent = firstTimed ?? sameDayEvents.first;
    final firstLabel = firstEvent.allDay
        ? 'all-day'
        : DateFormat('h:mm a').format(firstEvent.startDateTime.toLocal());

    return AgendaNotificationContent(
      title: "Today's Agenda",
      body:
          '${sameDayEvents.length} events - First at $firstLabel: ${firstEvent.title}',
    );
  }
}
