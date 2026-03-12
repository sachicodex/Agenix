import 'package:shared_preferences/shared_preferences.dart';

class EventSyncActivityTracker {
  static const String _keyLastChangeMs = 'event_sync_last_change_ms';

  static Future<void> markLocalChange() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyLastChangeMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<int?> lastChangeMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastChangeMs);
  }
}
