import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'notifications/firebase_push_service.dart';
import 'navigation/app_route_observer.dart';
import 'data/local/local_event_store.dart';
import 'providers/event_providers.dart';
import 'providers/notification_providers.dart';
import 'screens/auth_wrapper.dart';
import 'screens/calendar_day_view_screen.dart';
import 'screens/create_event_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_feedback_screen.dart';
import 'services/google_calendar_service.dart';
import 'services/firebase_bootstrap.dart';
import 'services/background_event_sync.dart';
import 'services/foreground_event_sync_service.dart';
import 'services/settings_sync_coordinator.dart';
import 'services/system_tray_service.dart';
import 'services/sync_service.dart';
import 'theme/app_theme.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  initForegroundEventSync();

  // Load .env early because desktop Firebase init may depend on it.
  // Keep optional so the app can still run without Firebase configuration.
  await dotenv.load(isOptional: true);

  // Android/iOS uses native config; desktop can use .env FirebaseOptions.
  try {
    await FirebaseBootstrap.ensureInitialized();
  } catch (e, st) {
    // Keep app running even if Firebase isn't configured, but log for debug.
    debugPrint('Firebase init failed: $e');
    debugPrint('$st');
  }

  if (isFirebaseMessagingSupportedPlatform()) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  await LocalEventStore.instance.initialize();

  // Initialize authentication service to restore any stored credentials
  // Run in background to not block app startup
  GoogleCalendarService.instance.initialize().catchError((e) {
    // Log error but don't prevent app from starting
  });

  await BackgroundEventSync.initialize();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final syncService = ref.read(syncServiceProvider);
    SystemTrayService.instance.setExitGuard(() async {
      return syncService.isBusy;
    });
    ref.listen<AsyncValue<SyncStatus>>(syncStatusProvider, (prev, next) {
      final status = next.valueOrNull;
      if (status != null) {
        SystemTrayService.instance.updateSyncStatus(status);
      }
    });
    SystemTrayService.instance.updateSyncStatus(syncService.status);
    Future.microtask(() async {
      final coordinator = ref.read(notificationRescheduleCoordinatorProvider);
      await coordinator.start();
      SettingsSyncCoordinator.instance.start();
      unawaited(SystemTrayService.instance.initialize());
      try {
        if (isFirebaseMessagingSupportedPlatform()) {
          await ref.read(firebasePushServiceProvider).initialize();
        }
      } catch (e, st) {
        debugPrint('FCM initialize error: $e');
        debugPrint('$st');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(notificationRescheduleCoordinatorProvider).rescheduleNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
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
      ),
    );
  }
}
