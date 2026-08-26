import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_calendar_service.dart';

/// The custom calendar palette stored for one signed-in user.
class CalendarPaletteData {
  const CalendarPaletteData({required this.userId, required this.colors});

  final String userId;
  final List<int> colors;
}

/// Persists custom calendar colors in the existing user-scoped settings
/// document. The Firestore rules already restrict that document to its owner.
class CalendarPaletteSyncService {
  CalendarPaletteSyncService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore,
      _auth = auth;

  static const _collection = 'user_settings';
  static const _field = 'customCalendarColors';
  static const _localCacheKey = 'calendar_custom_colors';

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  /// Keeps the palette available when Firebase is not configured or the app is
  /// offline. The same values are uploaded on the next successful save.
  Future<List<int>> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_localCacheKey) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .toSet()
        .toList();
  }

  /// Returns null when Firebase authentication is unavailable. An empty list
  /// means the signed-in user has not saved any custom colors yet.
  Future<CalendarPaletteData?> loadForCurrentUser() async {
    try {
      final user = await _currentUser();
      if (user == null) return null;

      final snapshot = await (_firestore ?? FirebaseFirestore.instance)
          .collection(_collection)
          .doc(user.uid)
          .get();
      final raw = snapshot.data()?[_field];
      final colors = raw is Iterable
          ? raw.whereType<num>().map((color) => color.toInt()).toSet().toList()
          : <int>[];
      return CalendarPaletteData(userId: user.uid, colors: colors);
    } catch (_) {
      return null;
    }
  }

  /// Emits the palette whenever it changes in Firestore, including changes
  /// made from another device signed in as the same user.
  Stream<CalendarPaletteData> watchForUser(String userId) {
    return (_firestore ?? FirebaseFirestore.instance)
        .collection(_collection)
        .doc(userId)
        .snapshots()
        .map(
          (snapshot) => CalendarPaletteData(
            userId: userId,
            colors: _colorsFrom(snapshot.data()?[_field]),
          ),
        );
  }

  /// Saves the full palette atomically for the current signed-in user.
  Future<bool> saveForCurrentUser(List<int> colors) async {
    final distinct = colors.toSet().toList(growable: false);
    await _saveCached(distinct);
    try {
      final user = await _currentUser();
      if (user == null) return false;

      await (_firestore ?? FirebaseFirestore.instance)
          .collection(_collection)
          .doc(user.uid)
          .set({
            _field: distinct,
            'customCalendarColorsUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      return true;
    } catch (_) {
      debugPrint('Could not save custom calendar colors to Firestore.');
      return false;
    }
  }

  Future<User?> _currentUser() async {
    final existing = (_auth ?? FirebaseAuth.instance).currentUser;
    return existing ??
        GoogleCalendarService.instance.ensureFirebaseAuthSignedInSilently();
  }

  List<int> _colorsFrom(Object? raw) => raw is Iterable
      ? raw.whereType<num>().map((color) => color.toInt()).toSet().toList()
      : <int>[];

  Future<void> _saveCached(List<int> colors) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _localCacheKey,
      colors.map((color) => color.toString()).toList(),
    );
  }
}
