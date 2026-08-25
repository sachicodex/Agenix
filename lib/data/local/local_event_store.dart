import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/calendar_event.dart';
import '../../services/app_data_service.dart';
import '../../services/debug_perf_logger.dart';

class LocalEventStore {
  LocalEventStore._();

  static final LocalEventStore instance = LocalEventStore._();

  Database? _db;
  final StreamController<void> _changeController =
      StreamController<void>.broadcast();
  Timer? _changeEmitTimer;
  final Map<String, String> _idAliases = <String, String>{};
  final Map<String, CalendarEvent> _eventCache = <String, CalendarEvent>{};
  bool _eventCacheLoaded = false;

  static const Duration _changeEmitDebounce = Duration(milliseconds: 120);

  Future<void> initialize() async {
    if (_db != null) return;
    final watch = DebugPerfLogger.start('LocalEventStore', 'initialize');

    final dbPath = await AppDataService.instance.getDatabasePath();

    _db = await openDatabase(
      dbPath,
      version: 3,
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
        await db.execute('''
CREATE TABLE user_profile (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  email TEXT,
  photo_url TEXT,
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
        if (oldVersion < 3) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS user_profile (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  email TEXT,
  photo_url TEXT,
  updated_at INTEGER NOT NULL
)
''');
        }
      },
    );
    DebugPerfLogger.end(
      'LocalEventStore',
      watch,
      'initialize',
      data: {'dbPath': dbPath},
    );
  }

  Future<void> close() async {
    _changeEmitTimer?.cancel();
    _changeEmitTimer = null;
    await _db?.close();
    _db = null;
    _eventCache.clear();
    _eventCacheLoaded = false;
  }

  Stream<List<CalendarEvent>> watchEvents(DateTimeRange range) async* {
    yield await getEventsForDateRange(range);
    await for (final _ in _changeController.stream) {
      yield await getEventsForDateRange(range);
    }
  }

  Stream<void> onEventsChanged() {
    return _changeController.stream;
  }

  Future<List<CalendarEvent>> getEventsForDateRange(DateTimeRange range) async {
    await _ensureEventCacheLoaded();
    final rangeStartUtc = range.start.toUtc();
    final rangeEndUtc = range.end.toUtc();

    final events = _eventCache.values.where((event) {
      if (event.deleted) return false;
      final startUtc = event.startDateTime.toUtc();
      final endUtc = event.endDateTime.toUtc();
      return startUtc.isBefore(rangeEndUtc) && endUtc.isAfter(rangeStartUtc);
    }).toList()..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));

    return events;
  }

  Future<List<CalendarEvent>> getEventsBetween(
    DateTime startUtc,
    DateTime endUtc,
  ) async {
    final db = _requireDb();
    final startMs = startUtc.toUtc().millisecondsSinceEpoch;
    final endMs = endUtc.toUtc().millisecondsSinceEpoch;
    final rows = await db.query(
      'events',
      where: 'deleted = 0 AND start_utc < ? AND end_utc > ?',
      whereArgs: [endMs, startMs],
    );
    return rows.map(_fromRow).toList();
  }

  Future<List<CalendarEvent>> getAllActiveEvents({int limit = 500}) async {
    await _ensureEventCacheLoaded();
    final events = _eventCache.values.where((event) => !event.deleted).toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    if (events.length <= limit) {
      return events;
    }
    return events.take(limit).toList();
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
    await _ensureEventCacheLoaded();
    for (final event in _eventCache.values) {
      if (event.gEventId == gEventId && event.calendarId == calendarId) {
        return event;
      }
    }
    return null;
  }

  Future<CalendarEvent?> getAnyByGoogleId(String gEventId) async {
    await _ensureEventCacheLoaded();
    final matches =
        _eventCache.values.where((event) => event.gEventId == gEventId).toList()
          ..sort((a, b) {
            final dirtyCompare = (b.dirty ? 1 : 0).compareTo(a.dirty ? 1 : 0);
            if (dirtyCompare != 0) return dirtyCompare;
            final aUpdated =
                a.updatedAtRemote?.millisecondsSinceEpoch ??
                -9223372036854775808;
            final bUpdated =
                b.updatedAtRemote?.millisecondsSinceEpoch ??
                -9223372036854775808;
            return bUpdated.compareTo(aUpdated);
          });
    return matches.isEmpty ? null : matches.first;
  }

  Future<CalendarEvent?> getSyncedCopyByGoogleId({
    required String gEventId,
    required String excludeEventId,
  }) async {
    await _ensureEventCacheLoaded();
    for (final event in _eventCache.values) {
      if (event.gEventId == gEventId &&
          event.id != excludeEventId &&
          !event.deleted &&
          !event.dirty &&
          event.pendingAction == PendingAction.none) {
        return event;
      }
    }
    return null;
  }

  Future<CalendarEvent?> getById(String id) async {
    final canonicalId = resolveCanonicalId(id);
    await _ensureEventCacheLoaded();
    return _eventCache[canonicalId];
  }

  Future<void> upsertEvent(CalendarEvent event) async {
    final watch = DebugPerfLogger.start('LocalEventStore', 'upsertEvent');
    final db = _requireDb();
    final canonicalId = resolveCanonicalId(event.id);
    final record = canonicalId == event.id
        ? event
        : event.copyWith(id: canonicalId);
    if (canonicalId != event.id) {
      _idAliases[event.id] = canonicalId;
    }
    await db.insert(
      'events',
      _toRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _eventCache[record.id] = record;
    _emitChange();
    DebugPerfLogger.end(
      'LocalEventStore',
      watch,
      'upsertEvent',
      data: {
        'id': record.id,
        'dirty': record.dirty,
        'pendingAction': record.pendingAction.name,
      },
    );
  }

  Future<void> deleteEventById(String id) async {
    final watch = DebugPerfLogger.start('LocalEventStore', 'deleteEventById');
    final db = _requireDb();
    final canonicalId = resolveCanonicalId(id);
    await db.delete('events', where: 'id = ?', whereArgs: [canonicalId]);
    _eventCache.remove(canonicalId);
    _emitChange();
    DebugPerfLogger.end(
      'LocalEventStore',
      watch,
      'deleteEventById',
      data: {'id': canonicalId},
    );
  }

  Future<void> replaceEventId({
    required String oldId,
    required CalendarEvent eventWithNewId,
  }) async {
    final watch = DebugPerfLogger.start('LocalEventStore', 'replaceEventId');
    final db = _requireDb();
    final canonicalOldId = resolveCanonicalId(oldId);
    await db.transaction((txn) async {
      await txn.insert(
        'events',
        _toRow(eventWithNewId),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (canonicalOldId != eventWithNewId.id) {
        await txn.delete(
          'events',
          where: 'id = ?',
          whereArgs: [canonicalOldId],
        );
      }
    });
    if (canonicalOldId != eventWithNewId.id) {
      _idAliases[canonicalOldId] = eventWithNewId.id;
      _idAliases[oldId] = eventWithNewId.id;
      _eventCache.remove(canonicalOldId);
    }
    _eventCache[eventWithNewId.id] = eventWithNewId;
    _emitChange();
    DebugPerfLogger.end(
      'LocalEventStore',
      watch,
      'replaceEventId',
      data: {'oldId': canonicalOldId, 'newId': eventWithNewId.id},
    );
  }

  Future<void> markDeleted(String id) async {
    final watch = DebugPerfLogger.start('LocalEventStore', 'markDeleted');
    final db = _requireDb();
    final canonicalId = resolveCanonicalId(id);
    await db.update(
      'events',
      {'deleted': 1, 'dirty': 0, 'pending_action': PendingAction.none.name},
      where: 'id = ?',
      whereArgs: [canonicalId],
    );
    final cached = _eventCache[canonicalId];
    if (cached != null) {
      _eventCache[canonicalId] = cached.copyWith(
        deleted: true,
        dirty: false,
        pendingAction: PendingAction.none,
      );
    }
    _emitChange();
    DebugPerfLogger.end(
      'LocalEventStore',
      watch,
      'markDeleted',
      data: {'id': canonicalId},
    );
  }

  String resolveCanonicalId(String id) {
    var current = id;
    final visited = <String>{};
    while (true) {
      final next = _idAliases[current];
      if (next == null || next.isEmpty || visited.contains(current)) {
        return current;
      }
      visited.add(current);
      current = next;
    }
  }

  Future<List<CalendarEvent>> getPendingEvents() async {
    final watch = DebugPerfLogger.start('LocalEventStore', 'getPendingEvents');
    await _ensureEventCacheLoaded();
    final pending = _eventCache.values
        .where(
          (event) => event.pendingAction != PendingAction.none || event.dirty,
        )
        .toList();
    DebugPerfLogger.end(
      'LocalEventStore',
      watch,
      'getPendingEvents',
      data: {'count': pending.length},
    );
    return pending;
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

  Future<void> deleteCalendar(String calendarId) async {
    final db = _requireDb();
    await db.delete('calendars', where: 'id = ?', whereArgs: [calendarId]);
  }

  Future<void> upsertUserProfile({
    required String? email,
    required String? photoUrl,
  }) async {
    final db = _requireDb();
    await db.insert('user_profile', {
      'id': 1,
      'email': email,
      'photo_url': photoUrl,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String?>> getCachedUserProfile() async {
    final db = _requireDb();
    final rows = await db.query(
      'user_profile',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) {
      return {'email': null, 'photoUrl': null};
    }
    final row = rows.first;
    return {
      'email': row['email'] as String?,
      'photoUrl': row['photo_url'] as String?,
    };
  }

  Future<void> clearUserProfile() async {
    final db = _requireDb();
    await db.delete('user_profile', where: 'id = ?', whereArgs: [1]);
  }

  Future<void> removeDuplicateGoogleEventCopies({
    required String gEventId,
    required String keepEventId,
    bool preserveDirty = false,
  }) async {
    final db = _requireDb();
    final where = preserveDirty
        ? 'g_event_id = ? AND id != ? AND dirty = 0 AND pending_action = ?'
        : 'g_event_id = ? AND id != ?';
    final whereArgs = preserveDirty
        ? <Object?>[gEventId, keepEventId, PendingAction.none.name]
        : <Object?>[gEventId, keepEventId];
    final deleted = await db.delete(
      'events',
      where: where,
      whereArgs: whereArgs,
    );
    if (deleted > 0) {
      final toRemove = _eventCache.entries
          .where((entry) {
            final event = entry.value;
            if (event.gEventId != gEventId || event.id == keepEventId) {
              return false;
            }
            if (!preserveDirty) {
              return true;
            }
            return !event.dirty && event.pendingAction == PendingAction.none;
          })
          .map((entry) => entry.key)
          .toList();
      for (final eventId in toRemove) {
        _eventCache.remove(eventId);
      }
      _emitChange();
    }
  }

  Future<void> _ensureEventCacheLoaded() async {
    if (_eventCacheLoaded) return;
    final watch = DebugPerfLogger.start('LocalEventStore', 'loadEventCache');
    final db = _requireDb();
    final rows = await db.query('events');
    _eventCache
      ..clear()
      ..addEntries(
        rows.map((row) {
          final event = _fromRow(row);
          return MapEntry(event.id, event);
        }),
      );
    _eventCacheLoaded = true;
    DebugPerfLogger.end(
      'LocalEventStore',
      watch,
      'loadEventCache',
      data: {'rowCount': rows.length},
    );
  }

  void _emitChange() {
    _changeEmitTimer?.cancel();
    _changeEmitTimer = Timer(_changeEmitDebounce, () {
      _changeEmitTimer = null;
      if (!_changeController.isClosed) {
        _changeController.add(null);
      }
    });
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
      'color': event.color.toARGB32(),
    };
  }

  CalendarEvent _fromRow(Map<String, Object?> row) {
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
      color: Color((row['color'] as int?) ?? Colors.blue.toARGB32()),
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
