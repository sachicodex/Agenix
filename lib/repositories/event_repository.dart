import 'package:flutter/material.dart';

import '../data/local/local_event_store.dart';
import '../models/calendar_event.dart';

class EventRepository {
  EventRepository(this._localStore);

  final LocalEventStore _localStore;

  Stream<List<CalendarEvent>> watchEvents(DateTimeRange range) {
    return _localStore.watchEvents(range);
  }

  Future<CalendarEvent> createEvent(CalendarEvent event) async {
    final localId = event.id.isNotEmpty
        ? event.id
        : DateTime.now().microsecondsSinceEpoch.toString();

    final record = event.copyWith(
      id: localId,
      dirty: true,
      deleted: false,
      pendingAction: PendingAction.create,
      updatedAtRemote: null,
    );

    await _localStore.upsertEvent(record);
    return record;
  }

  Future<CalendarEvent> updateEvent(CalendarEvent event) async {
    final nextPending = _mergePendingAction(event.pendingAction);

    final record = event.copyWith(
      dirty: true,
      pendingAction: nextPending,
    );
    await _localStore.upsertEvent(record);
    return record;
  }

  Future<void> deleteEvent(String eventId) async {
    final existing = await _localStore.getById(eventId);
    if (existing == null) {
      return;
    }

    if (existing.pendingAction == PendingAction.create &&
        existing.gEventId == null) {
      await _localStore.deleteEventById(eventId);
      return;
    }

    final record = existing.copyWith(
      deleted: true,
      dirty: true,
      pendingAction: PendingAction.delete,
    );
    await _localStore.upsertEvent(record);
  }

  PendingAction _mergePendingAction(PendingAction current) {
    if (current == PendingAction.create) {
      return PendingAction.create;
    }
    if (current == PendingAction.delete) {
      return PendingAction.delete;
    }
    return PendingAction.update;
  }
}
