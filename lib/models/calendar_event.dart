import 'package:flutter/material.dart';

class CalendarEvent {
  final String id;
  final String title;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final bool allDay;
  final Color color;
  final String description;
  final List<int> reminders; // minutes before event
  final String? googleCalendarId; // ID in Google Calendar if uploaded
  final bool syncedToGoogle; // Whether this event has been synced to Google Calendar

  CalendarEvent({
    required this.id,
    required this.title,
    required this.startDateTime,
    required this.endDateTime,
    this.allDay = false,
    Color? color,
    this.description = '',
    this.reminders = const [],
    this.googleCalendarId,
    this.syncedToGoogle = false,
  }) : color = color ?? Colors.blue;

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startDateTime': startDateTime.toIso8601String(),
      'endDateTime': endDateTime.toIso8601String(),
      'allDay': allDay,
      'color': color.value,
      'description': description,
      'reminders': reminders,
      'googleCalendarId': googleCalendarId,
      'syncedToGoogle': syncedToGoogle,
    };
  }

  // Create from JSON
  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      startDateTime: DateTime.parse(json['startDateTime'] as String),
      endDateTime: DateTime.parse(json['endDateTime'] as String),
      allDay: json['allDay'] as bool? ?? false,
      color: Color(json['color'] as int),
      description: json['description'] as String? ?? '',
      reminders: (json['reminders'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      googleCalendarId: json['googleCalendarId'] as String?,
      syncedToGoogle: json['syncedToGoogle'] as bool? ?? false,
    );
  }

  // Create a copy with modified fields
  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? startDateTime,
    DateTime? endDateTime,
    bool? allDay,
    Color? color,
    String? description,
    List<int>? reminders,
    String? googleCalendarId,
    bool? syncedToGoogle,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      allDay: allDay ?? this.allDay,
      color: color ?? this.color,
      description: description ?? this.description,
      reminders: reminders ?? this.reminders,
      googleCalendarId: googleCalendarId ?? this.googleCalendarId,
      syncedToGoogle: syncedToGoogle ?? this.syncedToGoogle,
    );
  }

  // Get duration in minutes
  int get durationMinutes {
    return endDateTime.difference(startDateTime).inMinutes;
  }

  // Check if event overlaps with another event
  bool overlapsWith(CalendarEvent other) {
    if (allDay || other.allDay) return false;
    return startDateTime.isBefore(other.endDateTime) &&
        endDateTime.isAfter(other.startDateTime);
  }
}

