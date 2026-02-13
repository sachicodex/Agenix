import 'dart:async';
import 'package:flutter/material.dart';
import 'google_calendar_service.dart';

/// Service to manage real-time calendar sync with Google Calendar
class CalendarSyncService {
  static CalendarSyncService? _instance;
  static CalendarSyncService get instance {
    _instance ??= CalendarSyncService._();
    return _instance!;
  }

  CalendarSyncService._();

  Timer? _syncTimer;
  String? _currentChannelId;
  String? _currentResourceId;
  Function(List<Map<String, dynamic>>)? _onEventsUpdated;
  String? _currentCalendarId;
  DateTime? _currentTimeMin;
  DateTime? _currentTimeMax;

  /// Start real-time sync for a calendar
  Future<void> startSync({
    required String calendarId,
    required DateTime timeMin,
    required DateTime timeMax,
    required Function(List<Map<String, dynamic>>) onEventsUpdated,
  }) async {
    _currentCalendarId = calendarId;
    _currentTimeMin = timeMin;
    _currentTimeMax = timeMax;
    _onEventsUpdated = onEventsUpdated;

    // Perform initial sync
    await _performSync();

    // Set up periodic sync (every 10 seconds for real-time feel)
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _performSync();
    });

    // Set up push notification watch (if supported)
    await _setupWatch();
  }

  /// Stop real-time sync
  Future<void> stopSync() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    
    if (_currentChannelId != null && _currentResourceId != null) {
      try {
        await GoogleCalendarService.instance.stopWatch(
          channelId: _currentChannelId!,
          resourceId: _currentResourceId!,
        );
      } catch (e) {
        debugPrint('Error stopping watch: $e');
      }
    }
    
    _currentChannelId = null;
    _currentResourceId = null;
    _onEventsUpdated = null;
  }

  /// Perform sync
  Future<void> _performSync() async {
    if (_currentCalendarId == null || _currentTimeMin == null || _currentTimeMax == null) {
      return;
    }

    try {
      // Always do full sync to ensure we get ALL events from Google Calendar
      // This ensures events created manually in Google Calendar always show up
      // We skip syncToken to get complete event list every time
      debugPrint('Performing FULL sync: calendarId=$_currentCalendarId, timeMin=$_currentTimeMin, timeMax=$_currentTimeMax');
      
      final result = await GoogleCalendarService.instance.getEventsWithSync(
        start: _currentTimeMin!,
        end: _currentTimeMax!,
        calendarId: _currentCalendarId!,
        syncToken: null, // Always full sync to get ALL events
      );

      final events = result['events'] as List<Map<String, dynamic>>;

      debugPrint('Sync returned ${events.length} events from Google Calendar');
      
      // Always return all events (full sync)
      if (_onEventsUpdated != null) {
        _onEventsUpdated!(events);
      }
    } catch (e) {
      debugPrint('Sync error: $e');
      // Retry once on "sync state invalid" style errors
      if (e.toString().contains('410') || e.toString().contains('GONE')) {
        // Retry with full sync
        try {
          await _performSync();
        } catch (retryError) {
          debugPrint('Retry sync also failed: $retryError');
        }
      }
    }
  }

  /// Set up push notification watch
  Future<void> _setupWatch() async {
    if (_currentCalendarId == null) return;

    try {
      // Generate unique channel ID
      final channelId = 'channel_${DateTime.now().millisecondsSinceEpoch}';
      // For desktop/web, use a unique identifier (in production, use actual webhook URL)
      final address = 'https://agenix.app/webhook/$channelId';

      final watchInfo = await GoogleCalendarService.instance.watchCalendar(
        calendarId: _currentCalendarId!,
        channelId: channelId,
        address: address,
      );

      _currentChannelId = watchInfo['channelId'];
      _currentResourceId = watchInfo['resourceId'];

      debugPrint('Watch channel created: $_currentChannelId');
    } catch (e) {
      debugPrint('Error setting up watch: $e');
      // Continue without push notifications, fallback to polling
    }
  }

  /// Manually trigger sync
  Future<void> refresh() async {
    await _performSync();
  }

  /// Update sync time range
  Future<void> updateTimeRange({
    required DateTime timeMin,
    required DateTime timeMax,
  }) async {
    _currentTimeMin = timeMin;
    _currentTimeMax = timeMax;
    // Perform immediate sync
    await _performSync();
  }
}

