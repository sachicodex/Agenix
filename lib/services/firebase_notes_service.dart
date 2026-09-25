import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'google_calendar_service.dart';

class FirebaseNote {
  const FirebaseNote({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.order = 0,
    this.noteType = 'text',
    this.checklist = const <FirebaseChecklistItem>[],
    this.colorValue = 0xFF1A1A1A,
    this.pinned = false,
    this.archived = false,
    this.trashed = false,
    this.labels = const <String>[],
  });

  final String id;
  final String title;
  final String content;
  final DateTime? updatedAt;
  final int order;
  final String noteType;
  final List<FirebaseChecklistItem> checklist;
  final int colorValue;
  final bool pinned;
  final bool archived;
  final bool trashed;
  final List<String> labels;

  FirebaseNote copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? updatedAt,
    int? order,
    String? noteType,
    List<FirebaseChecklistItem>? checklist,
    int? colorValue,
    bool? pinned,
    bool? archived,
    bool? trashed,
    List<String>? labels,
  }) {
    return FirebaseNote(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      updatedAt: updatedAt ?? this.updatedAt,
      order: order ?? this.order,
      noteType: noteType ?? this.noteType,
      checklist: checklist ?? this.checklist,
      colorValue: colorValue ?? this.colorValue,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      trashed: trashed ?? this.trashed,
      labels: labels ?? this.labels,
    );
  }

  Map<String, dynamic> toLocalMap() => {
    'id': id,
    'title': title,
    'content': content,
    'updatedAt': updatedAt?.toIso8601String(),
    'order': order,
    'noteType': noteType,
    'checklist': checklist
        .map((item) => {'text': item.text, 'checked': item.checked})
        .toList(growable: false),
    'colorValue': colorValue,
    'pinned': pinned,
    'archived': archived,
    'trashed': trashed,
    'labels': labels,
  };

  factory FirebaseNote.fromLocalMap(Map<String, dynamic> data) {
    final rawChecklist = data['checklist'];
    return FirebaseNote(
      id: data['id'] as String? ?? '',
      title: data['title'] as String? ?? 'Untitled note',
      content: data['content'] as String? ?? '',
      updatedAt: DateTime.tryParse(data['updatedAt'] as String? ?? ''),
      order: data['order'] is int ? data['order'] as int : 0,
      noteType: data['noteType'] as String? ?? 'text',
      checklist: rawChecklist is List
          ? rawChecklist
                .whereType<Map>()
                .map(
                  (item) => FirebaseChecklistItem(
                    text: item['text'] as String? ?? '',
                    checked: item['checked'] == true,
                  ),
                )
                .toList(growable: false)
          : const <FirebaseChecklistItem>[],
      colorValue: data['colorValue'] is int
          ? data['colorValue'] as int
          : 0xFF1A1A1A,
      pinned: data['pinned'] == true,
      archived: data['archived'] == true,
      trashed: data['trashed'] == true,
      labels: data['labels'] is List
          ? (data['labels'] as List).whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }

  factory FirebaseNote.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? <String, dynamic>{};
    final timestamp = data['updatedAt'];
    final rawChecklist = data['checklist'];
    return FirebaseNote(
      id: document.id,
      title: data['title'] as String? ?? 'Untitled note',
      content: data['content'] as String? ?? '',
      updatedAt: timestamp is Timestamp ? timestamp.toDate() : null,
      order: data['order'] is int ? data['order'] as int : 0,
      noteType: data['noteType'] as String? ?? 'text',
      checklist: rawChecklist is List
          ? rawChecklist
                .whereType<Map>()
                .map(
                  (item) => FirebaseChecklistItem(
                    text: item['text'] as String? ?? '',
                    checked: item['checked'] == true,
                  ),
                )
                .toList(growable: false)
          : const <FirebaseChecklistItem>[],
      colorValue: data['colorValue'] is int
          ? data['colorValue'] as int
          : 0xFF1A1A1A,
      pinned: data['pinned'] == true,
      archived: data['archived'] == true,
      trashed: data['trashed'] == true,
      labels: data['labels'] is List
          ? (data['labels'] as List).whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }
}

class FirebaseChecklistItem {
  const FirebaseChecklistItem({required this.text, required this.checked});

  final String text;
  final bool checked;
}

/// Stores Agenix notes in the signed-in user's private Firestore collection.
class FirebaseNotesService {
  FirebaseNotesService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore,
      _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  static const String _collection = 'user_notes';

  Stream<List<FirebaseNote>> streamNotes(String uid) {
    return (_firestore ?? FirebaseFirestore.instance)
        .collection(_collection)
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final notes = snapshot.docs
              .map(FirebaseNote.fromDocument)
              .toList(growable: false);
          return notes.toList()..sort((a, b) {
            final orderCompare = b.order.compareTo(a.order);
            if (orderCompare != 0) return orderCompare;
            final aDate = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
        });
  }

  Future<void> createNote({
    String? noteId,
    required String title,
    required String content,
    String noteType = 'text',
    List<FirebaseChecklistItem> checklist = const <FirebaseChecklistItem>[],
    int colorValue = 0xFF1A1A1A,
    bool pinned = false,
    bool archived = false,
    bool trashed = false,
    List<String> labels = const <String>[],
    int? order,
  }) async {
    var user = (_auth ?? FirebaseAuth.instance).currentUser;
    user ??= await GoogleCalendarService.instance.ensureFirebaseAuthSignedIn();
    if (user == null) {
      throw StateError('Firebase sign-in is required to save notes.');
    }

    final firestore = _firestore ?? FirebaseFirestore.instance;
    final data = {
      'uid': user.uid,
      'title': title.trim(),
      'content': content.trim(),
      'noteType': noteType,
      'checklist': checklist
          .map((item) => {'text': item.text.trim(), 'checked': item.checked})
          .toList(growable: false),
      'colorValue': colorValue,
      'pinned': pinned,
      'archived': archived,
      'trashed': trashed,
      'labels': labels,
      'order': order ?? DateTime.now().microsecondsSinceEpoch,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (noteId == null || noteId.isEmpty) {
      await firestore.collection(_collection).add(data);
    } else {
      await firestore.collection(_collection).doc(noteId).set(data);
    }
  }

  Future<void> updateNote({
    required String noteId,
    required String title,
    required String content,
    required String noteType,
    required List<FirebaseChecklistItem> checklist,
    required int colorValue,
    required bool pinned,
    required bool archived,
    required bool trashed,
    required List<String> labels,
    required int order,
  }) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw StateError('Firebase sign-in is required to update notes.');
    }
    await (_firestore ?? FirebaseFirestore.instance)
        .collection(_collection)
        .doc(noteId)
        .update({
          'title': title.trim(),
          'content': content.trim(),
          'noteType': noteType,
          'checklist': checklist
              .map(
                (item) => {'text': item.text.trim(), 'checked': item.checked},
              )
              .toList(growable: false),
          'colorValue': colorValue,
          'pinned': pinned,
          'archived': archived,
          'trashed': trashed,
          'labels': labels,
          'order': order,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> updateNoteOrder(List<String> noteIds) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw StateError('Firebase sign-in is required to reorder notes.');
    }
    final firestore = _firestore ?? FirebaseFirestore.instance;
    final batch = firestore.batch();
    for (var index = 0; index < noteIds.length; index++) {
      batch.update(firestore.collection(_collection).doc(noteIds[index]), {
        'order': noteIds.length - index,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> deleteNote(String noteId) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw StateError('Firebase sign-in is required to delete notes.');
    }
    await (_firestore ?? FirebaseFirestore.instance)
        .collection(_collection)
        .doc(noteId)
        .delete();
  }
}
