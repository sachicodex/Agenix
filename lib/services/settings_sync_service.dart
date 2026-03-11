import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsSyncService {
  SettingsSyncService({FirebaseFirestore? firestore}) : _firestore = firestore;

  FirebaseFirestore? _firestore;
  String? lastError;

  static const String _collection = 'user_settings';

  Future<Map<String, dynamic>?> fetchForUser(String uid) async {
    try {
      lastError = null;
      final firestore = _firestore ?? FirebaseFirestore.instance;
      final doc = await firestore.collection(_collection).doc(uid).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null || data.isEmpty) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      lastError = e.toString();
      // Most common on desktop when Firebase wasn't configured/initialized.
      return null;
    }
  }

  Future<bool> saveForUser(String uid, Map<String, dynamic> data) async {
    try {
      lastError = null;
      final firestore = _firestore ?? FirebaseFirestore.instance;
      final payload = _stripNulls(Map<String, dynamic>.from(data));
      payload['updatedAt'] = FieldValue.serverTimestamp();
      await firestore
          .collection(_collection)
          .doc(uid)
          .set(payload, SetOptions(merge: true));
      return true;
    } catch (e) {
      lastError = e.toString();
      // Most common on desktop when Firebase wasn't configured/initialized.
      return false;
    }
  }

  Map<String, dynamic> _stripNulls(Map<String, dynamic> input) {
    input.removeWhere((key, value) => value == null);
    for (final entry in input.entries.toList()) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        input[entry.key] = _stripNulls(Map<String, dynamic>.from(value));
      }
    }
    return input;
  }
}
