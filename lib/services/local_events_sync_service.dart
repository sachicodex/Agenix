import 'package:flutter/material.dart';
import '../data/local/local_event_store.dart';
import '../data/remote/remote_calendar_data_source.dart';
import '../services/google_calendar_service.dart';
import 'sync_service.dart';

/// Service to sync local events to Google Calendar
class LocalEventsSyncService {
  static LocalEventsSyncService? _instance;
  static LocalEventsSyncService get instance {
    _instance ??= LocalEventsSyncService._();
    return _instance!;
  }

  LocalEventsSyncService._();

  final LocalEventStore _localStore = LocalEventStore.instance;
  final RemoteCalendarDataSource _remoteSource =
      RemoteCalendarDataSource(GoogleCalendarService.instance);

  /// Upload all local events to Google Calendar
  Future<void> syncLocalEventsToGoogle({
    String calendarId = 'primary',
    Function(int total, int current)? onProgress,
  }) async {
    try {
      final syncService = SyncService(_localStore, _remoteSource);
      await syncService.pushLocalChanges();
    } catch (e) {
      debugPrint('Error syncing local events: $e');
      rethrow;
    }
  }

  /// Check if there are unsynced local events
  Future<bool> hasUnsyncedEvents() async {
    final pending = await _localStore.getPendingEvents();
    return pending.isNotEmpty;
  }
}

