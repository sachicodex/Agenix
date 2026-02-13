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
    final canonicalEvent = await _resolveCanonicalIdentity(event);
    final existing = await _localStore.getById(canonicalEvent.id);
    final currentPending =
        existing?.pendingAction ?? canonicalEvent.pendingAction;
    final nextPending = _mergePendingAction(currentPending);

    final record = canonicalEvent.copyWith(
      gEventId: canonicalEvent.gEventId ?? existing?.gEventId,
      dirty: true,
      pendingAction: nextPending,
    );
    await _upsertWithIdentityTransition(oldId: event.id, event: record);
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

  Future<CalendarEvent> _resolveCanonicalIdentity(CalendarEvent event) async {
    final gEventId = event.gEventId;
    if (gEventId == null || gEventId.isEmpty) {
      return event;
    }

    final canonical = await _localStore.getAnyByGoogleId(gEventId);
    if (canonical == null || canonical.id == event.id) {
      return event;
    }

    return event.copyWith(id: canonical.id);
  }

  Future<void> _upsertWithIdentityTransition({
    required String oldId,
    required CalendarEvent event,
  }) async {
    if (oldId != event.id) {
      await _localStore.replaceEventId(oldId: oldId, eventWithNewId: event);
      return;
    }
    await _localStore.upsertEvent(event);
  }
}
