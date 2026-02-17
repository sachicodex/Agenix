import '../models/calendar_event.dart';

abstract class NotificationEventSource {
  Future<List<CalendarEvent>> getEventsBetween(
    DateTime startUtc,
    DateTime endUtc,
  );

  Stream<void> onEventsChanged();
}
