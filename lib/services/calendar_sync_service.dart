import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_calendar_service.dart';

/// Service to manage real-time calendar sync with Google Calendar
class CalendarSyncService {
  static CalendarSyncService? _instance;
  static CalendarSyncService get instance {
    _instance ??= CalendarSyncService._();
    return _instance!;
  }

  CalendarSyncService._();

  SharedPreferences? _prefs;
  Timer? _syncTimer;
  String? _currentSyncToken; // Saved for potential future incremental sync optimization
  String? _currentChannelId;
  String? _currentResourceId;
  Function(List<Map<String, dynamic>>)? _onEventsUpdated;
  String? _currentCalendarId;
  DateTime? _currentTimeMin;
  DateTime? _currentTimeMax;

  Future<void> _ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Start real-time sync for a calendar
  Future<void> startSync({
    required String calendarId,
    required DateTime timeMin,
    required DateTime timeMax,
    required Function(List<Map<String, dynamic>>) onEventsUpdated,
    bool forceFullSync = false,
  }) async {
    await _ensureInitialized();
    
    _currentCalendarId = calendarId;
    _currentTimeMin = timeMin;
    _currentTimeMax = timeMax;
    _onEventsUpdated = onEventsUpdated;

    // Load saved syncToken (unless forcing full sync)
    if (forceFullSync) {
      _currentSyncToken = null;
      await _prefs!.remove('syncToken_$calendarId');
    } else {
      final savedToken = _prefs!.getString('syncToken_$calendarId');
      _currentSyncToken = savedToken;
    }

    // Perform initial sync (will do full sync if no token)
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

  /// Perform incremental sync
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
      final newSyncToken = result['syncToken'] as String?;

      debugPrint('Sync returned ${events.length} events from Google Calendar');

      if (newSyncToken != null && newSyncToken.isNotEmpty) {
        _currentSyncToken = newSyncToken;
        await _prefs!.setString('syncToken_$_currentCalendarId', newSyncToken);
      }
      
      // Always return all events (full sync)
      if (_onEventsUpdated != null) {
        _onEventsUpdated!(events);
      }
    } catch (e) {
      debugPrint('Sync error: $e');
      // On error, clear syncToken and retry
      if (e.toString().contains('410') || e.toString().contains('GONE')) {
        _currentSyncToken = null;
        await _prefs!.remove('syncToken_$_currentCalendarId');
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
    // Clear syncToken to force full sync with new range
    _currentSyncToken = null;
    if (_currentCalendarId != null) {
      await _prefs!.remove('syncToken_$_currentCalendarId');
    }
    // Perform immediate sync
    await _performSync();
  }
}

