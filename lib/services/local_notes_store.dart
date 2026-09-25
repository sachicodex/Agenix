import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_notes_service.dart';

class LocalNotesStore {
  LocalNotesStore._();

  static final LocalNotesStore instance = LocalNotesStore._();

  Future<List<FirebaseNote>> load(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(uid));
    if (raw == null || raw.isEmpty) return const <FirebaseNote>[];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                FirebaseNote.fromLocalMap(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } catch (_) {
      return const <FirebaseNote>[];
    }
  }

  Future<void> save(String uid, List<FirebaseNote> notes) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(uid),
      jsonEncode(notes.map((note) => note.toLocalMap()).toList()),
    );
  }

  String _key(String uid) => 'local_notes_$uid';
}
