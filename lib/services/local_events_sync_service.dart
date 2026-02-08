import 'package:flutter/material.dart';
import 'event_storage_service.dart';
import 'google_calendar_service.dart';

/// Service to sync local events to Google Calendar
class LocalEventsSyncService {
  static LocalEventsSyncService? _instance;
  static LocalEventsSyncService get instance {
    _instance ??= LocalEventsSyncService._();
    return _instance!;
  }

  LocalEventsSyncService._();

  final EventStorageService _localStorage = EventStorageService.instance;
  final GoogleCalendarService _googleService = GoogleCalendarService.instance;

  /// Upload all local events to Google Calendar
  Future<void> syncLocalEventsToGoogle({
    String calendarId = 'primary',
    Function(int total, int current)? onProgress,
  }) async {
    try {
      // Check if signed in
      final signedIn = await _googleService.isSignedIn();
      if (!signedIn) {
        debugPrint('Not signed in to Google Calendar, skipping sync');
        return;
      }

      // Get default calendar ID
      final defaultCalendarId = await _googleService.storage.getDefaultCalendarId() ?? calendarId;

      // Load all local events
      final allLocalEvents = await _localStorage.loadEvents();
      
      if (allLocalEvents.isEmpty) {
        debugPrint('No local events to sync');
        return;
      }

      debugPrint('Syncing ${allLocalEvents.length} local events to Google Calendar');

      int synced = 0;
      int failed = 0;
      int skipped = 0;

      for (var i = 0; i < allLocalEvents.length; i++) {
        final event = allLocalEvents[i];
        
        // Skip if already synced to Google Calendar
        if (event.syncedToGoogle && event.googleCalendarId != null) {
          skipped++;
          debugPrint('Skipping already synced event: ${event.title}');
          continue;
        }
        
        try {
          final reminders = event.reminders.isNotEmpty
              ? [{'method': 'popup', 'minutes': event.reminders.first}]
              : null;

          final createdEvent = await _googleService.insertEvent(
            summary: event.title,
            description: event.description,
            start: event.startDateTime,
            end: event.endDateTime,
            calendarId: defaultCalendarId,
            reminders: reminders,
          );

          // Mark event as synced and save Google Calendar ID
          final updatedEvent = event.copyWith(
            googleCalendarId: createdEvent.id,
            syncedToGoogle: true,
          );
          
          // Update in local storage
          await _localStorage.updateEvent(updatedEvent);

          synced++;
          debugPrint('Synced event: ${event.title} (Google ID: ${createdEvent.id})');

          // Report progress
          if (onProgress != null) {
            onProgress(allLocalEvents.length, i + 1);
          }
        } catch (e) {
          failed++;
          debugPrint('Failed to sync event ${event.title}: $e');
          // Continue with next event
        }
      }

      debugPrint('Sync complete: $synced synced, $skipped skipped (already synced), $failed failed');

      // Events are now marked as synced in local storage
    } catch (e) {
      debugPrint('Error syncing local events: $e');
      rethrow;
    }
  }

  /// Check if there are unsynced local events
  Future<bool> hasUnsyncedEvents() async {
    final events = await _localStorage.loadEvents();
    // Only return true if there are events that haven't been synced
    return events.any((e) => !e.syncedToGoogle);
  }
}

