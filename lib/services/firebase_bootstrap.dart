import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class FirebaseBootstrap {
  static Future<void> ensureInitialized() async {
    if (Firebase.apps.isNotEmpty) {
      return;
    }

    if (kIsWeb) {
      // Web should use generated firebase_options.dart; not supported here.
      // Keep the app running; Firebase features will be unavailable.
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      // Uses native config: google-services.json / GoogleService-Info.plist
      await Firebase.initializeApp();
      return;
    }

    // Desktop: requires explicit FirebaseOptions.
    final opts = _desktopOptionsFromEnv();
    if (opts == null) {
      debugPrint(
        'Firebase not configured for desktop (.env missing FIREBASE_* values).',
      );
      return;
    }
    await Firebase.initializeApp(options: opts);
  }

  static FirebaseOptions? _desktopOptionsFromEnv() {
    String? apiKey;
    String? appId;
    String? projectId;
    String? senderId;

    try {
      apiKey = dotenv.env['FIREBASE_API_KEY']?.trim();
      appId = dotenv.env['FIREBASE_APP_ID']?.trim();
      projectId = dotenv.env['FIREBASE_PROJECT_ID']?.trim();
      senderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID']?.trim();
    } catch (_) {
      // dotenv may not be initialized; treat as missing config.
      return null;
    }

    if (apiKey == null ||
        appId == null ||
        projectId == null ||
        senderId == null ||
        apiKey.isEmpty ||
        appId.isEmpty ||
        projectId.isEmpty ||
        senderId.isEmpty) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      projectId: projectId,
      messagingSenderId: senderId,
    );
  }
}
