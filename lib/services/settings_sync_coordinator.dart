import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/notification_settings_repository.dart';
import '../services/api_key_storage_service.dart';
import '../services/google_calendar_service.dart';
import '../services/settings_encryption_service.dart';
import '../services/settings_sync_service.dart';
import '../services/settings_sync_state_store.dart';
import '../services/windows_startup_service.dart';

class SettingsSyncCoordinator with WidgetsBindingObserver {
  SettingsSyncCoordinator._();

  static final SettingsSyncCoordinator instance = SettingsSyncCoordinator._();

  final SettingsSyncService _settingsSyncService = SettingsSyncService();
  final SettingsSyncStateStore _syncStateStore = SettingsSyncStateStore();
  final ApiKeyStorageService _apiKeyStorageService = ApiKeyStorageService();
  final SettingsEncryptionService _settingsEncryptionService =
      SettingsEncryptionService();
  Timer? _timer;
  bool _started = false;
  bool _syncing = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_syncOnce());
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_syncOnce());
    });
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncOnce());
    }
  }

  Future<void> _syncOnce() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final online = await _hasInternetConnection();
      if (!online) return;

      final signedIn = await GoogleCalendarService.instance.isSignedIn();
      if (!signedIn) return;

      final user =
          await GoogleCalendarService.instance.ensureFirebaseAuthSignedInSilently();
      if (user == null) return;

      final state = await _syncStateStore.load(user.uid);
      final localMs = state.lastLocalUpdatedAtMs ?? 0;
      final data = await _settingsSyncService.fetchForUser(user.uid);
      if (data == null) {
        if (state.pendingPush) {
          await _pushSettingsToCloud(user);
        }
        return;
      }

      final cloudMs = _extractUpdatedAtMs(data) ?? 0;
      await _syncStateStore.updateCloudTimestamp(user.uid, cloudMs);

      if (state.pendingPush && localMs > cloudMs) {
        await _pushSettingsToCloud(user);
        return;
      }

      if (cloudMs > localMs) {
        await _applyCloudSettings(data, user);
        await _syncStateStore.markSynced(user.uid, cloudMs);
        return;
      }

      if (localMs > cloudMs) {
        await _pushSettingsToCloud(user);
      }
    } finally {
      _syncing = false;
    }
  }

  Future<bool> _pushSettingsToCloud(User user) async {
    try {
      final storage = GoogleCalendarService.instance.storage;
      final calendarId = await storage.getDefaultCalendarId();
      final calendarName = await storage.getDefaultCalendarName();
      final notificationSettings = await NotificationSettingsRepository(
        SharedPreferences.getInstance,
      ).getSettings();

      final ok = await _settingsSyncService.saveForUser(user.uid, {
        'userEmail': user.email,
        'defaultCalendarId': calendarId,
        'defaultCalendarName': calendarName,
        'aiApiKey': await _apiKeyStorageService.getApiKey(),
        'notificationSettings': {
          'defaultReminderMinutes': notificationSettings.defaultReminderMinutes,
          'dailyAgendaEnabled': notificationSettings.dailyAgendaEnabled,
          'eventRemindersEnabled': notificationSettings.eventRemindersEnabled,
          'dailyAgendaMinutesAfterMidnight':
              notificationSettings.dailyAgendaMinutesAfterMidnight,
        },
        'launchOnStartup':
            Platform.isWindows
                ? await WindowsStartupService.instance
                    .getLaunchOnStartupEnabled()
                : null,
      });

      if (ok) {
        final state = await _syncStateStore.load(user.uid);
        final localMs =
            state.lastLocalUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
        await _syncStateStore.markSynced(user.uid, localMs);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  int? _extractUpdatedAtMs(Map<String, dynamic> data) {
    final raw = data['updatedAt'];
    if (raw is Timestamp) {
      return raw.millisecondsSinceEpoch;
    }
    if (raw is DateTime) {
      return raw.toUtc().millisecondsSinceEpoch;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return null;
  }

  Future<void> _applyCloudSettings(
    Map<String, dynamic> data,
    User user,
  ) async {
    final notif = data['notificationSettings'];
    if (notif is Map) {
      final repository = NotificationSettingsRepository(
        SharedPreferences.getInstance,
      );
      final current = await repository.getSettings();
      var next = current;
      final reminder = notif['defaultReminderMinutes'];
      if (reminder is num) {
        next = next.copyWith(defaultReminderMinutes: reminder.toInt());
      }
      final agendaEnabled = notif['dailyAgendaEnabled'];
      if (agendaEnabled is bool) {
        next = next.copyWith(dailyAgendaEnabled: agendaEnabled);
      }
      final remindersEnabled = notif['eventRemindersEnabled'];
      if (remindersEnabled is bool) {
        next = next.copyWith(eventRemindersEnabled: remindersEnabled);
      }
      final agendaMinutes = notif['dailyAgendaMinutesAfterMidnight'];
      if (agendaMinutes is num) {
        next = next.copyWith(
          dailyAgendaMinutesAfterMidnight: agendaMinutes.toInt(),
        );
      }
      await repository.saveSettings(next);
    }

    final calendarId = data['defaultCalendarId'];
    final calendarName = data['defaultCalendarName'];
    if (calendarId is String && calendarId.isNotEmpty) {
      final name =
          calendarName is String && calendarName.isNotEmpty
              ? calendarName
              : 'Unknown';
      await GoogleCalendarService.instance.storage.saveDefaultCalendar(
        calendarId,
        name,
      );
    }

    final apiKey = data['aiApiKey'];
    if (apiKey is String && apiKey.trim().isNotEmpty) {
      await _apiKeyStorageService.saveApiKey(apiKey.trim());
    }

    final encApiKey = data['aiApiKeyEnc'];
    if (encApiKey is String && encApiKey.isNotEmpty) {
      final clear = await _settingsEncryptionService.decryptApiKey(
        uid: user.uid,
        encoded: encApiKey,
      );
      if (clear != null && clear.trim().isNotEmpty) {
        await _apiKeyStorageService.saveApiKey(clear.trim());
      }
    }
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
