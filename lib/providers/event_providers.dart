import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/local_event_store.dart';
import '../data/remote/remote_calendar_data_source.dart';
import '../models/calendar_event.dart';
import '../repositories/event_repository.dart';
import '../services/google_calendar_service.dart';
import '../services/sync_service.dart';

final localEventStoreProvider = Provider<LocalEventStore>((ref) {
  return LocalEventStore.instance;
});

final remoteCalendarDataSourceProvider = Provider<RemoteCalendarDataSource>((ref) {
  return RemoteCalendarDataSource(GoogleCalendarService.instance);
});

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(ref.read(localEventStoreProvider));
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.read(localEventStoreProvider),
    ref.read(remoteCalendarDataSourceProvider),
  );
});

final eventsProvider =
    StreamProvider.family<List<CalendarEvent>, DateTimeRange>((ref, range) {
  final repo = ref.watch(eventRepositoryProvider);
  return repo.watchEvents(range);
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final sync = ref.watch(syncServiceProvider);
  return sync.statusStream;
});
