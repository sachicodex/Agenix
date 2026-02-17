import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

bool isFirebaseMessagingSupportedPlatform() {
  if (kIsWeb) {
    return false;
  }
  return Platform.isAndroid;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM background message: ${message.messageId}');
}

class FirebasePushService {
  static const String broadcastTopic = 'all_devices';

  FirebasePushService({
    required FirebaseMessaging messaging,
    required NotificationService notificationService,
  }) : _messaging = messaging,
       _notificationService = notificationService;

  final FirebaseMessaging _messaging;
  final NotificationService _notificationService;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || !isFirebaseMessagingSupportedPlatform()) {
      return;
    }

    try {
      await _messaging.setAutoInitEnabled(true);
    } catch (e) {
      debugPrint('FCM auto-init error: $e');
    }
    await _notificationService.initialize();

    try {
      final permission = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
      debugPrint('FCM permission status: ${permission.authorizationStatus}');
    } catch (e) {
      debugPrint('FCM permission request error: $e');
    }

    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('FCM foreground presentation error: $e');
    }

    String? token;
    try {
      token = await _messaging.getToken();
      debugPrint('FCM token: $token');
      if (token == null || token.isEmpty) {
        debugPrint(
          'FCM token is empty. Check internet + Google Play services.',
        );
      }
    } catch (e) {
      debugPrint('FCM token fetch error: $e');
    }

    await _subscribeToBroadcastTopic();

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
      debugPrint('FCM token refreshed: $token');
      unawaited(_subscribeToBroadcastTopic());
    });

    _onMessageSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    _onMessageOpenedAppSubscription = FirebaseMessaging.onMessageOpenedApp
        .listen(_handleMessageOpened);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpened(initialMessage, fromTerminated: true);
    }

    _initialized = true;
  }

  Future<String?> getToken() async {
    if (!isFirebaseMessagingSupportedPlatform()) {
      return null;
    }
    return _messaging.getToken();
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _onMessageSubscription?.cancel();
    await _onMessageOpenedAppSubscription?.cancel();
    _initialized = false;
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('FCM foreground message: id=${message.messageId}');
    final notification = message.notification;
    if (notification == null && message.data.isEmpty) {
      return;
    }

    final title = notification?.title ?? 'Agenix';
    final body =
        notification?.body ?? _buildBodyFromData(message.data) ?? 'New update';
    final payload = _encodeDataPayload(message.data);

    try {
      await _notificationService.showPushNotification(
        notificationId: _stableMessageId(message),
        title: title,
        body: body,
        payload: payload,
      );
    } catch (e) {
      debugPrint('FCM foreground notify error: $e');
    }
  }

  void _handleMessageOpened(
    RemoteMessage message, {
    bool fromTerminated = false,
  }) {
    debugPrint(
      'FCM opened (terminated: $fromTerminated) '
      'id=${message.messageId} data=${message.data}',
    );
  }

  String? _buildBodyFromData(Map<String, dynamic> data) {
    const candidates = <String>['body', 'message', 'content', 'text'];
    for (final key in candidates) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _encodeDataPayload(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return null;
    }
    try {
      return jsonEncode(data);
    } catch (_) {
      return null;
    }
  }

  int _stableMessageId(RemoteMessage message) {
    final raw =
        message.messageId ??
        '${message.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}:${message.data.hashCode}';
    var hash = 0x811C9DC5;
    for (final codeUnit in raw.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<void> _subscribeToBroadcastTopic() async {
    try {
      await _messaging.subscribeToTopic(broadcastTopic);
      debugPrint('FCM subscribed topic: $broadcastTopic');
    } catch (e) {
      debugPrint('FCM topic subscribe error: $e');
    }
  }
}
