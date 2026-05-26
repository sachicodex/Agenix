import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalNotificationIdStore {
  LocalNotificationIdStore(this._preferencesLoader);

  final Future<SharedPreferences> Function() _preferencesLoader;

  static const String _eventMapKey = 'notif_event_ids_v1';
  static const String _agendaMapKey = 'notif_agenda_ids_v1';

  Future<Map<String, List<int>>> getEventNotificationIds() async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(_eventMapKey);
    if (raw == null || raw.isEmpty) {
      return <String, List<int>>{};
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) {
        final ids = (value as List<dynamic>).map((e) => e as int).toList();
        return MapEntry(key, ids);
      });
    } catch (_) {
      return <String, List<int>>{};
    }
  }

  Future<void> saveEventNotificationIds(Map<String, List<int>> mapping) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(_eventMapKey, jsonEncode(mapping));
  }

  Future<Map<String, int>> getAgendaNotificationIds() async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(_agendaMapKey);
    if (raw == null || raw.isEmpty) {
      return <String, int>{};
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as int));
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> saveAgendaNotificationIds(Map<String, int> mapping) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(_agendaMapKey, jsonEncode(mapping));
  }

  Future<void> clearAll() async {
    final prefs = await _preferencesLoader();
    await prefs.remove(_eventMapKey);
    await prefs.remove(_agendaMapKey);
  }
}
