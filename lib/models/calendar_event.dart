import 'package:flutter/material.dart';

enum PendingAction { none, create, update, delete }

class CalendarEvent {
  final String id; // Local DB id
  final String? gEventId; // Google Calendar event id
  final String calendarId;
  final String title;
  final String description;
  final String location;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final bool allDay;
  final String timezone;
  final DateTime? updatedAtRemote;
  final bool dirty;
  final bool deleted;
  final PendingAction pendingAction;
  final Color color;
  final List<int> reminders; // minutes before event

  CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.startDateTime,
    required this.endDateTime,
    this.allDay = false,
    Color? color,
    this.description = '',
    this.location = '',
    this.timezone = '',
    this.updatedAtRemote,
    this.dirty = false,
    this.deleted = false,
    this.pendingAction = PendingAction.none,
    this.reminders = const [],
    this.gEventId,
  }) : color = color ?? Colors.blue;

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gEventId': gEventId,
      'calendarId': calendarId,
      'title': title,
      'description': description,
      'location': location,
      'startDateTime': startDateTime.toIso8601String(),
      'endDateTime': endDateTime.toIso8601String(),
      'allDay': allDay,
      'timezone': timezone,
      'updatedAtRemote': updatedAtRemote?.toIso8601String(),
      'dirty': dirty,
      'deleted': deleted,
      'pendingAction': pendingAction.name,
      'color': color.value,
      'reminders': reminders,
    };
  }

  // Create from JSON
  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String,
      gEventId: json['gEventId'] as String?,
      calendarId: json['calendarId'] as String? ?? 'primary',
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? '',
      startDateTime: DateTime.parse(json['startDateTime'] as String),
      endDateTime: DateTime.parse(json['endDateTime'] as String),
      allDay: json['allDay'] as bool? ?? false,
      timezone: json['timezone'] as String? ?? '',
      updatedAtRemote: json['updatedAtRemote'] != null
          ? DateTime.tryParse(json['updatedAtRemote'] as String)
          : null,
      dirty: json['dirty'] as bool? ?? false,
      deleted: json['deleted'] as bool? ?? false,
      pendingAction: _pendingActionFromJson(
        json['pendingAction'] as String?,
      ),
      color: Color(json['color'] as int),
      reminders: (json['reminders'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
    );
  }

  static PendingAction _pendingActionFromJson(String? value) {
    switch (value) {
      case 'create':
        return PendingAction.create;
      case 'update':
        return PendingAction.update;
      case 'delete':
        return PendingAction.delete;
      default:
        return PendingAction.none;
    }
  }

  // Create a copy with modified fields
  CalendarEvent copyWith({
    String? id,
    String? gEventId,
    String? calendarId,
    String? title,
    String? description,
    String? location,
    DateTime? startDateTime,
    DateTime? endDateTime,
    bool? allDay,
    String? timezone,
    DateTime? updatedAtRemote,
    bool? dirty,
    bool? deleted,
    PendingAction? pendingAction,
    Color? color,
    List<int>? reminders,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      gEventId: gEventId ?? this.gEventId,
      calendarId: calendarId ?? this.calendarId,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      allDay: allDay ?? this.allDay,
      timezone: timezone ?? this.timezone,
      updatedAtRemote: updatedAtRemote ?? this.updatedAtRemote,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      pendingAction: pendingAction ?? this.pendingAction,
      color: color ?? this.color,
      reminders: reminders ?? this.reminders,
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

