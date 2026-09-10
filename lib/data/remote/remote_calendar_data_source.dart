import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:flutter/material.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';

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
    final created = await _googleService.insertEvent(
      summary: event.title,
      description: _descriptionForGoogle(event.description),
      recurrence: event.recurrence.isEmpty
          ? null
          : event.recurrence.split('\n'),
      start: event.startDateTime,
      end: event.endDateTime,
      calendarId: event.calendarId,
      customEventId: _buildStableInsertEventId(event.id),
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

    final updated = await _googleService.updateEvent(
      eventId: event.gEventId!,
      summary: event.title,
      description: _descriptionForGoogle(event.description),
      recurrence: event.recurrence.isEmpty
          ? null
          : event.recurrence.split('\n'),
      start: event.startDateTime,
      end: event.endDateTime,
      calendarId: event.calendarId,
    );

    return _mapFromApiEvent(
      updated,
      calendarId: event.calendarId,
      fallbackColor: event.color,
    );
  }

  String _descriptionForGoogle(String value) {
    if (!value.startsWith('quill:')) {
      return _plainTextToHtml(value);
    }
    try {
      final operations = jsonDecode(value.substring(6)) as List;
      final html = StringBuffer();
      final currentLine = StringBuffer();
      String? openList;

      void closeList() {
        if (openList != null) {
          html.write('</$openList>');
          openList = null;
        }
      }

      void writeLine(Map<String, dynamic> attributes) {
        final list = attributes['list'] as String?;
        if (list == 'ordered' || list == 'bullet') {
          final tag = list == 'ordered' ? 'ol' : 'ul';
          if (openList != tag) {
            closeList();
            html.write('<$tag>');
            openList = tag;
          }
          html
            ..write('<li>')
            ..write(currentLine)
            ..write('</li>');
        } else {
          closeList();
          html
            ..write('<p>')
            // Keep empty paragraphs when Google normalizes the description.
            // A bare <br> can be removed by another client, which makes
            // Enter-created spacing disappear on mobile.
            ..write(currentLine.isEmpty ? '&nbsp;' : currentLine)
            ..write('</p>');
        }
        currentLine.clear();
      }

      for (final operation in operations) {
        if (operation is! Map) continue;
        final insert = operation['insert'];
        final attributes = Map<String, dynamic>.from(
          (operation['attributes'] as Map?) ?? const <String, dynamic>{},
        );
        if (insert is! String) continue;

        final parts = insert.split('\n');
        for (var index = 0; index < parts.length; index++) {
          if (parts[index].isNotEmpty) {
            currentLine.write(_inlineHtml(parts[index], attributes));
          }
          if (index < parts.length - 1) writeLine(attributes);
        }
      }
      if (currentLine.isNotEmpty) writeLine(const <String, dynamic>{});
      closeList();
      return html.toString();
    } catch (_) {
      return _plainTextToHtml(value.substring(6));
    }
  }

  String _plainTextToHtml(String value) {
    return value
        .split('\n')
        .map(
          (line) =>
              line.isEmpty ? '<p>&nbsp;</p>' : '<p>${_escapeHtml(line)}</p>',
        )
        .join();
  }

  String _inlineHtml(String value, Map<String, dynamic> attributes) {
    var result = _escapeHtml(value);
    if (attributes['bold'] == true) result = '<strong>$result</strong>';
    if (attributes['italic'] == true) result = '<em>$result</em>';
    if (attributes['underline'] == true) result = '<u>$result</u>';
    if (attributes['strike'] == true) result = '<s>$result</s>';
    final link = attributes['link'];
    if (link is String && link.isNotEmpty) {
      result = '<a href="${_escapeHtml(link)}">$result</a>';
    }
    return result;
  }

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  String _descriptionFromGoogle(String value) {
    if (value.isEmpty || value.startsWith('quill:')) return value;
    if (!RegExp(r'<[a-z][^>]*>', caseSensitive: false).hasMatch(value)) {
      return value;
    }
    try {
      final delta = HtmlToDelta().convert(value, transformTableAsEmbed: false);
      return 'quill:${jsonEncode(delta.toJson())}';
    } catch (_) {
      // Preserve readable server content if the HTML contains an unsupported
      // construct.
      return value;
    }
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
      eventId: event.deleteSeries
          ? (event.recurringEventId ?? event.gEventId!)
          : event.gEventId!,
      calendarId: event.calendarId,
    );
  }

  /// Returns false when this account no longer has access to [calendarId].
  /// A null result means the availability check itself could not be completed.
  Future<bool?> canAccessCalendar(String calendarId) async {
    try {
      final calendars = await _googleService.getUserCalendars();
      return calendars.any((calendar) => calendar['id'] == calendarId);
    } catch (_) {
      return null;
    }
  }

  CalendarEvent _mapToCalendarEvent(Map<String, dynamic> data) {
    final colorValue = data['color'] as int? ?? Colors.blue.toARGB32();
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
      description: _descriptionFromGoogle(data['description'] as String? ?? ''),
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
      recurrence: (data['recurrence'] as List<dynamic>?)?.join('\n') ?? '',
      recurringEventId: data['recurringEventId'] as String?,
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
      description: _descriptionFromGoogle(event.description ?? ''),
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
      recurrence: event.recurrence?.join('\n') ?? '',
      recurringEventId: event.recurringEventId,
    );
  }

  String _buildRemoteLocalId({
    required String calendarId,
    required String? gEventId,
  }) {
    final safeGId = gEventId ?? 'unknown';
    return 'g:$calendarId:$safeGId';
  }

  String _buildStableInsertEventId(String localId) {
    final digest = sha1.convert(utf8.encode(localId)).toString();
    // Google Calendar custom event IDs must stay within its limited character set.
    return 'ageniv$digest';
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
