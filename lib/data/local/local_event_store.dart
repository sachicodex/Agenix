import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/calendar_event.dart';

class LocalEventStore {
  LocalEventStore._();

  static final LocalEventStore instance = LocalEventStore._();

  Database? _db;
  final StreamController<void> _changeController =
      StreamController<void>.broadcast();

  Future<void> initialize() async {
    if (_db != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'agenix_events.db');

    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE events (
  id TEXT PRIMARY KEY,
  g_event_id TEXT,
  calendar_id TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  location TEXT,
  start_utc INTEGER NOT NULL,
  end_utc INTEGER NOT NULL,
  all_day INTEGER NOT NULL,
  timezone TEXT,
  updated_at_remote INTEGER,
  dirty INTEGER NOT NULL,
  deleted INTEGER NOT NULL,
  pending_action TEXT NOT NULL,
  color INTEGER NOT NULL,
  reminders TEXT
)
''');
        await db.execute(
          'CREATE INDEX idx_events_start_end ON events(start_utc, end_utc)',
        );
        await db.execute(
          'CREATE INDEX idx_events_calendar ON events(calendar_id)',
        );
        await db.execute(
          'CREATE INDEX idx_events_g_event_id ON events(g_event_id)',
        );
        await db.execute('''
CREATE TABLE calendars (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  color INTEGER NOT NULL,
  selected INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL
)
''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS calendars (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  color INTEGER NOT NULL,
  selected INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL
)
''');
        }
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Stream<List<CalendarEvent>> watchEvents(DateTimeRange range) async* {
    yield await getEventsForDateRange(range);
    await for (final _ in _changeController.stream) {
      yield await getEventsForDateRange(range);
    }
  }

  Future<List<CalendarEvent>> getEventsForDateRange(DateTimeRange range) async {
    final db = _requireDb();
    final rangeStartUtc = range.start.toUtc().millisecondsSinceEpoch;
    final rangeEndUtc = range.end.toUtc().millisecondsSinceEpoch;

    final rows = await db.query(
      'events',
      where: 'deleted = 0 AND start_utc < ? AND end_utc > ?',
      whereArgs: [rangeEndUtc, rangeStartUtc],
    );

    return rows.map(_fromRow).toList();
  }

  Future<List<CalendarEvent>> getSyncedEventsForCalendarInRange({
    required String calendarId,
    required DateTimeRange range,
  }) async {
    final db = _requireDb();
    final rangeStartUtc = range.start.toUtc().millisecondsSinceEpoch;
    final rangeEndUtc = range.end.toUtc().millisecondsSinceEpoch;

    final rows = await db.query(
      'events',
      where:
          'deleted = 0 AND dirty = 0 AND pending_action = ? AND g_event_id IS NOT NULL '
          'AND calendar_id = ? AND start_utc < ? AND end_utc > ?',
      whereArgs: [
        PendingAction.none.name,
        calendarId,
        rangeEndUtc,
        rangeStartUtc,
      ],
    );

    return rows.map(_fromRow).toList();
  }

  Future<CalendarEvent?> getByGoogleId(
    String gEventId,
    String calendarId,
  ) async {
    final db = _requireDb();
    final rows = await db.query(
      'events',
      where: 'g_event_id = ? AND calendar_id = ?',
      whereArgs: [gEventId, calendarId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<CalendarEvent?> getById(String id) async {
    final db = _requireDb();
    final rows = await db.query(
      'events',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> upsertEvent(CalendarEvent event) async {
    final db = _requireDb();
    await db.insert(
      'events',
      _toRow(event),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _emitChange();
  }

  Future<void> deleteEventById(String id) async {
    final db = _requireDb();
    await db.delete('events', where: 'id = ?', whereArgs: [id]);
    _emitChange();
  }

  Future<void> replaceEventId({
    required String oldId,
    required CalendarEvent eventWithNewId,
  }) async {
    final db = _requireDb();
    await db.transaction((txn) async {
      await txn.insert(
        'events',
        _toRow(eventWithNewId),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (oldId != eventWithNewId.id) {
        await txn.delete('events', where: 'id = ?', whereArgs: [oldId]);
      }
    });
    _emitChange();
  }

  Future<void> markDeleted(String id) async {
    final db = _requireDb();
    await db.update(
      'events',
      {'deleted': 1, 'dirty': 0, 'pending_action': PendingAction.none.name},
      where: 'id = ?',
      whereArgs: [id],
    );
    _emitChange();
  }

  Future<List<CalendarEvent>> getPendingEvents() async {
    final db = _requireDb();
    final rows = await db.query(
      'events',
      where: 'pending_action != ? OR dirty = 1',
      whereArgs: [PendingAction.none.name],
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> upsertCalendars(List<Map<String, dynamic>> calendars) async {
    final db = _requireDb();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final calendar in calendars) {
        final id = (calendar['id'] as String?) ?? '';
        if (id.isEmpty) continue;
        await txn.insert('calendars', {
          'id': id,
          'name': (calendar['name'] as String?) ?? id,
          'color': (calendar['color'] as int?) ?? 0xFF039BE5,
          'selected': ((calendar['selected'] as bool?) ?? true) ? 1 : 0,
          'updated_at': nowMs,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCachedCalendars() async {
    final db = _requireDb();
    final rows = await db.query(
      'calendars',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows
        .map(
          (row) => <String, dynamic>{
            'id': row['id'] as String,
            'name': row['name'] as String,
            'color': row['color'] as int,
            'selected': (row['selected'] as int? ?? 1) == 1,
          },
        )
        .toList();
  }

  Future<void> removeDuplicateGoogleEventCopies({
    required String gEventId,
    required String keepEventId,
  }) async {
    final db = _requireDb();
    final deleted = await db.delete(
      'events',
      where: 'g_event_id = ? AND id != ?',
      whereArgs: [gEventId, keepEventId],
    );
    if (deleted > 0) {
      _emitChange();
    }
  }

  void _emitChange() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('LocalEventStore not initialized');
    }
    return db;
  }

  Map<String, Object?> _toRow(CalendarEvent event) {
    return {
      'id': event.id,
      'g_event_id': event.gEventId,
      'calendar_id': event.calendarId,
      'title': event.title,
      'description': event.description,
      'location': event.location,
      'start_utc': event.startDateTime.toUtc().millisecondsSinceEpoch,
      'end_utc': event.endDateTime.toUtc().millisecondsSinceEpoch,
      'all_day': event.allDay ? 1 : 0,
      'timezone': event.timezone,
      'updated_at_remote': event.updatedAtRemote?.millisecondsSinceEpoch,
      'dirty': event.dirty ? 1 : 0,
      'deleted': event.deleted ? 1 : 0,
      'pending_action': event.pendingAction.name,
      'color': event.color.value,
      'reminders': jsonEncode(event.reminders),
    };
  }

  CalendarEvent _fromRow(Map<String, Object?> row) {
    final remindersRaw = row['reminders'] as String?;
    final reminders = remindersRaw == null
        ? <int>[]
        : (jsonDecode(remindersRaw) as List<dynamic>)
              .map((e) => e as int)
              .toList();

    return CalendarEvent(
      id: row['id'] as String,
      gEventId: row['g_event_id'] as String?,
      calendarId: row['calendar_id'] as String? ?? 'primary',
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      location: row['location'] as String? ?? '',
      startDateTime: DateTime.fromMillisecondsSinceEpoch(
        row['start_utc'] as int,
        isUtc: true,
      ).toLocal(),
      endDateTime: DateTime.fromMillisecondsSinceEpoch(
        row['end_utc'] as int,
        isUtc: true,
      ).toLocal(),
      allDay: (row['all_day'] as int? ?? 0) == 1,
      timezone: row['timezone'] as String? ?? '',
      updatedAtRemote: row['updated_at_remote'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['updated_at_remote'] as int,
              isUtc: true,
            ),
      dirty: (row['dirty'] as int? ?? 0) == 1,
      deleted: (row['deleted'] as int? ?? 0) == 1,
      pendingAction: _pendingActionFromRow(row['pending_action'] as String?),
      color: Color((row['color'] as int?) ?? Colors.blue.value),
      reminders: reminders,
    );
  }

  PendingAction _pendingActionFromRow(String? value) {
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
}
