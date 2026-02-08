import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/calendar_event.dart';

class EventStorageService {
  static const String _eventsKey = 'calendar_events';
  static EventStorageService? _instance;
  SharedPreferences? _prefs;

  EventStorageService._();

  static EventStorageService get instance {
    _instance ??= EventStorageService._();
    return _instance!;
  }

  Future<void> _ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Load all events
  Future<List<CalendarEvent>> loadEvents() async {
    await _ensureInitialized();
    final eventsJson = _prefs!.getString(_eventsKey);
    if (eventsJson == null) return [];

    try {
      final List<dynamic> decoded = json.decode(eventsJson);
      return decoded
          .map((json) => CalendarEvent.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Save all events
  Future<void> saveEvents(List<CalendarEvent> events) async {
    await _ensureInitialized();
    final eventsJson = json.encode(events.map((e) => e.toJson()).toList());
    await _prefs!.setString(_eventsKey, eventsJson);
  }

  // Add a new event
  Future<void> addEvent(CalendarEvent event) async {
    final events = await loadEvents();
    events.add(event);
    await saveEvents(events);
  }

  // Update an existing event
  Future<void> updateEvent(CalendarEvent event) async {
    final events = await loadEvents();
    final index = events.indexWhere((e) => e.id == event.id);
    if (index != -1) {
      events[index] = event;
      await saveEvents(events);
    }
  }

  // Delete an event
  Future<void> deleteEvent(String eventId) async {
    final events = await loadEvents();
    events.removeWhere((e) => e.id == eventId);
    await saveEvents(events);
  }

  // Get events for a specific date range
  Future<List<CalendarEvent>> getEventsForDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final allEvents = await loadEvents();
    return allEvents.where((event) {
      if (event.allDay) {
        final eventDate = DateTime(
          event.startDateTime.year,
          event.startDateTime.month,
          event.startDateTime.day,
        );
        final rangeStart = DateTime(start.year, start.month, start.day);
        final rangeEnd = DateTime(end.year, end.month, end.day);
        return eventDate.isAtSameMomentAs(rangeStart) ||
            (eventDate.isAfter(rangeStart) && eventDate.isBefore(rangeEnd));
      }
      return event.startDateTime.isBefore(end) &&
          event.endDateTime.isAfter(start);
    }).toList();
  }
}

