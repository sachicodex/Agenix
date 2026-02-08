import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:flutter/material.dart';

import '../../models/calendar_event.dart';
import '../../services/google_calendar_service.dart';

class RemoteCalendarDataSource {
  RemoteCalendarDataSource(this._googleService);

  final GoogleCalendarService _googleService;

  Future<ListEventsResult> listEvents({
    required DateTime timeMin,
    required DateTime timeMax,
    required String calendarId,
    String? syncToken,
  }) async {
    final calendarColor = await _getCalendarColor(calendarId);
    final result = await _googleService.getEventsWithSync(
      start: timeMin,
      end: timeMax,
      calendarId: calendarId,
      syncToken: syncToken,
      calendarColor: calendarColor,
      includeCancelled: syncToken != null && syncToken.isNotEmpty,
    );

    final events = (result['events'] as List<Map<String, dynamic>>)
        .map(_mapToCalendarEvent)
        .toList();

    return ListEventsResult(
      events: events,
      nextSyncToken: result['syncToken'] as String?,
    );
  }

  Future<CalendarEvent> insertEvent({required CalendarEvent event}) async {
    final reminders = event.reminders.isNotEmpty
        ? [
            {'method': 'popup', 'minutes': event.reminders.first},
          ]
        : null;

    final created = await _googleService.insertEvent(
      summary: event.title,
      description: event.description,
      start: event.startDateTime,
      end: event.endDateTime,
      calendarId: event.calendarId,
      reminders: reminders,
    );

    return _mapFromApiEvent(
      created,
      calendarId: event.calendarId,
      fallbackColor: event.color,
    );
  }

  Future<CalendarEvent> updateEvent({required CalendarEvent event}) async {
    if (event.gEventId == null) {
      throw StateError('Cannot update event without gEventId');
    }

    final reminders = event.reminders.isNotEmpty
        ? [
            {'method': 'popup', 'minutes': event.reminders.first},
          ]
        : null;

    final updated = await _googleService.updateEvent(
      eventId: event.gEventId!,
      summary: event.title,
      description: event.description,
      start: event.startDateTime,
      end: event.endDateTime,
      calendarId: event.calendarId,
      reminders: reminders,
    );

    return _mapFromApiEvent(
      updated,
      calendarId: event.calendarId,
      fallbackColor: event.color,
    );
  }

  Future<CalendarEvent> moveEvent({
    required CalendarEvent event,
    required String sourceCalendarId,
  }) async {
    if (event.gEventId == null) {
      throw StateError('Cannot move event without gEventId');
    }

    final moved = await _googleService.moveEvent(
      eventId: event.gEventId!,
      sourceCalendarId: sourceCalendarId,
      destinationCalendarId: event.calendarId,
    );

    return _mapFromApiEvent(
      moved,
      calendarId: event.calendarId,
      fallbackColor: event.color,
    );
  }

  Future<void> deleteEvent({required CalendarEvent event}) async {
    if (event.gEventId == null) {
      return;
    }
    await _googleService.deleteEvent(
      eventId: event.gEventId!,
      calendarId: event.calendarId,
    );
  }

  CalendarEvent _mapToCalendarEvent(Map<String, dynamic> data) {
    final colorValue = data['color'] as int? ?? Colors.blue.value;
    final updatedAt = data['updatedAtRemote'] as DateTime?;
    final deleted = data['deleted'] as bool? ?? false;
    return CalendarEvent(
      id: _buildRemoteLocalId(
        calendarId: data['calendarId'] as String? ?? 'primary',
        gEventId: data['id'] as String? ?? data['googleCalendarId'] as String?,
      ),
      gEventId: data['id'] as String? ?? data['googleCalendarId'] as String?,
      calendarId: data['calendarId'] as String? ?? 'primary',
      title: data['title'] as String? ?? '(No Title)',
      description: data['description'] as String? ?? '',
      location: data['location'] as String? ?? '',
      startDateTime: data['startDateTime'] as DateTime,
      endDateTime: data['endDateTime'] as DateTime,
      allDay: data['allDay'] as bool? ?? false,
      timezone: data['timezone'] as String? ?? '',
      updatedAtRemote: updatedAt,
      dirty: false,
      deleted: deleted,
      pendingAction: PendingAction.none,
      color: Color(colorValue),
      reminders:
          (data['reminders'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
    );
  }

  CalendarEvent _mapFromApiEvent(
    calendar.Event event, {
    required String calendarId,
    required Color fallbackColor,
  }) {
    final startDateTime = event.start?.dateTime ?? event.start?.date;
    final endDateTime = event.end?.dateTime ?? event.end?.date;
    final isAllDay = event.start?.date != null;

    final start = startDateTime?.toLocal() ?? DateTime.now();
    final end = endDateTime?.toLocal() ?? start.add(const Duration(hours: 1));

    return CalendarEvent(
      id: _buildRemoteLocalId(calendarId: calendarId, gEventId: event.id),
      gEventId: event.id,
      calendarId: calendarId,
      title: event.summary?.trim().isNotEmpty == true
          ? event.summary!.trim()
          : '(No Title)',
      description: event.description ?? '',
      location: event.location ?? '',
      startDateTime: start,
      endDateTime: end,
      allDay: isAllDay,
      timezone: event.start?.timeZone ?? '',
      updatedAtRemote: event.updated?.toUtc(),
      dirty: false,
      deleted: event.status == 'cancelled',
      pendingAction: PendingAction.none,
      color: fallbackColor,
      reminders:
          event.reminders?.overrides?.map((r) => r.minutes ?? 0).toList() ?? [],
    );
  }

  String _buildRemoteLocalId({
    required String calendarId,
    required String? gEventId,
  }) {
    final safeGId = gEventId ?? 'unknown';
    return 'g:$calendarId:$safeGId';
  }

  Future<int?> _getCalendarColor(String calendarId) async {
    try {
      final calendars = await _googleService.getUserCalendars();
      for (final cal in calendars) {
        if (cal['id'] == calendarId) {
          return cal['color'] as int?;
        }
      }
    } catch (_) {}
    return null;
  }
}

class ListEventsResult {
  final List<CalendarEvent> events;
  final String? nextSyncToken;

  ListEventsResult({required this.events, required this.nextSyncToken});
}
