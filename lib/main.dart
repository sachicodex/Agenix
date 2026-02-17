import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'notifications/firebase_push_service.dart';
import 'navigation/app_route_observer.dart';
import 'data/local/local_event_store.dart';
import 'providers/notification_providers.dart';
import 'screens/auth_wrapper.dart';
import 'screens/calendar_day_view_screen.dart';
import 'screens/create_event_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_feedback_screen.dart';
import 'services/google_calendar_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  if (isFirebaseMessagingSupportedPlatform()) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  await LocalEventStore.instance.initialize();

  // Load environment variables from .env (optional) - non-blocking
  // If the .env file is missing, dotenv.load() may throw; catch and continue
  // so the app can run using system environment variables instead.
  dotenv.load().catchError((e) {
    // Silently continue - app can use system environment variables
  });

  // Initialize authentication service to restore any stored credentials
  // Run in background to not block app startup
  GoogleCalendarService.instance.initialize().catchError((e) {
    // Log error but don't prevent app from starting
  });

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(notificationRescheduleCoordinatorProvider).start();
      try {
        await ref.read(firebasePushServiceProvider).initialize();
      } catch (e, st) {
        debugPrint('FCM initialize error: $e');
        debugPrint('$st');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agenix',
      theme: AppTheme.build(),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      home: const AuthWrapper(),
      navigatorObservers: [appRouteObserver],
      routes: {
        CreateEventScreen.routeName: (_) => const CreateEventScreen(),
        SyncFeedbackScreen.routeName: (_) => const SyncFeedbackScreen(),
        SettingsScreen.routeName: (_) => const SettingsScreen(),
        '/calendar': (_) => const CalendarDayViewScreen(),
      },
    );
  }
}
