import 'package:shared_preferences/shared_preferences.dart';

class SettingsSyncState {
  const SettingsSyncState({
    required this.lastLocalUpdatedAtMs,
    required this.lastCloudUpdatedAtMs,
    required this.pendingPush,
  });

  final int? lastLocalUpdatedAtMs;
  final int? lastCloudUpdatedAtMs;
  final bool pendingPush;
}

class SettingsSyncStateStore {
  static const String _keyPrefix = 'settings_sync';

  Future<SettingsSyncState> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final localMs = prefs.getInt(_keyLocal(uid));
    final cloudMs = prefs.getInt(_keyCloud(uid));
    final pending = prefs.getBool(_keyPending(uid)) ?? false;
    return SettingsSyncState(
      lastLocalUpdatedAtMs: localMs,
      lastCloudUpdatedAtMs: cloudMs,
      pendingPush: pending,
    );
  }

  Future<int> markLocalDirty(String uid, {int? atMs}) async {
    final prefs = await SharedPreferences.getInstance();
    final stamp = atMs ?? DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_keyLocal(uid), stamp);
    await prefs.setBool(_keyPending(uid), true);
    return stamp;
  }

  Future<void> markSynced(String uid, int atMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLocal(uid), atMs);
    await prefs.setInt(_keyCloud(uid), atMs);
    await prefs.setBool(_keyPending(uid), false);
  }

  Future<void> updateCloudTimestamp(String uid, int atMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCloud(uid), atMs);
  }

  String _keyLocal(String uid) => '$_keyPrefix.${uid}.local_ms';
  String _keyCloud(String uid) => '$_keyPrefix.${uid}.cloud_ms';
  String _keyPending(String uid) => '$_keyPrefix.${uid}.pending';
}
