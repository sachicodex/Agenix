import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'notifications/firebase_push_service.dart';
import 'navigation/app_navigator.dart';
import 'navigation/app_route_observer.dart';
import 'data/local/local_event_store.dart';
import 'providers/event_providers.dart';
import 'providers/notification_providers.dart';
import 'screens/auth_wrapper.dart';
import 'screens/calendar_day_view_screen.dart';
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
import 'widgets/windows_title_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        backgroundColor: Colors.transparent,
      ),
      () async {},
    );
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

  // Restore OAuth session before the first auth gate runs.
  await GoogleCalendarService.instance.initialize();

  await BackgroundEventSync.initialize();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  ProviderSubscription<AsyncValue<SyncStatus>>? _syncStatusSub;
  Future<void>? _windowsExitPushInFlight;
  Future<void>? _windowsExitNotificationRescheduleInFlight;
  bool _windowsExitNeedsNotificationFlush = false;

  void _logWindowsExit(String message) {
    if (kDebugMode && Platform.isWindows) {
      debugPrint('[WindowsExit] $message');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final syncService = ref.read(syncServiceProvider);
    final notificationCoordinator = ref.read(
      notificationRescheduleCoordinatorProvider,
    );
    SystemTrayService.instance.setExitGuard(() async {
      final pendingEvents = await LocalEventStore.instance.getPendingEvents();
      _logWindowsExit(
        'guard check pendingCount=${pendingEvents.length} '
        'pushInFlight=${_windowsExitPushInFlight != null} '
        'notifInFlight=${_windowsExitNotificationRescheduleInFlight != null} '
        'needsNotifFlush=$_windowsExitNeedsNotificationFlush '
        'notifPending=${notificationCoordinator.hasPendingWork}',
      );
      if (_windowsExitPushInFlight != null) {
        _logWindowsExit(
          'guard blocks exit: close-triggered push still running',
        );
        return true;
      }
      if (_windowsExitNotificationRescheduleInFlight != null) {
        _logWindowsExit(
          'guard blocks exit: close-triggered notification reschedule still running',
        );
        return true;
      }
      if (pendingEvents.isEmpty) {
        final shouldFlushNotifications =
            _windowsExitNeedsNotificationFlush ||
            notificationCoordinator.hasPendingWork;
        if (!shouldFlushNotifications) {
          _logWindowsExit(
            'guard allows exit: no pending local changes or notification work',
          );
          return false;
        }
        _logWindowsExit('starting close-triggered notification reschedule');
        _windowsExitNeedsNotificationFlush = false;
        unawaited(
          (() async {
            final notificationFuture = notificationCoordinator.flushPendingWork(
              force: true,
            );
            _windowsExitNotificationRescheduleInFlight = notificationFuture;
            try {
              await notificationFuture;
              _logWindowsExit(
                'close-triggered notification reschedule finished',
              );
            } catch (error) {
              _logWindowsExit(
                'close-triggered notification reschedule failed error=$error',
              );
            } finally {
              if (identical(
                _windowsExitNotificationRescheduleInFlight,
                notificationFuture,
              )) {
                _windowsExitNotificationRescheduleInFlight = null;
              }
              _logWindowsExit(
                'close-triggered notification reschedule in-flight flag cleared',
              );
            }
          })(),
        );
        return true;
      }
      _windowsExitNeedsNotificationFlush = true;
      _logWindowsExit('starting close-triggered pushLocalChanges');
      unawaited(
        (() async {
          final pushFuture = syncService.pushLocalChanges(
            retryWhenLocked: true,
          );
          _windowsExitPushInFlight = pushFuture;
          try {
            await pushFuture;
            final remaining = await LocalEventStore.instance.getPendingEvents();
            _logWindowsExit(
              'close-triggered push finished remainingPending=${remaining.length}',
            );
            if (remaining.isNotEmpty) {
              _windowsExitNeedsNotificationFlush = true;
            }
          } catch (error) {
            _logWindowsExit('close-triggered push failed error=$error');
          } finally {
            if (identical(_windowsExitPushInFlight, pushFuture)) {
              _windowsExitPushInFlight = null;
            }
            _logWindowsExit('close-triggered push in-flight flag cleared');
          }
        })(),
      );
      return true;
    });
    _syncStatusSub = ref.listenManual<AsyncValue<SyncStatus>>(
      syncStatusProvider,
      (prev, next) {
        final status = next.valueOrNull;
        if (status != null) {
          SystemTrayService.instance.updateSyncStatus(status);
        }
      },
    );
    SystemTrayService.instance.updateSyncStatus(syncService.status);
    Future.microtask(() async {
      final coordinator = ref.read(notificationRescheduleCoordinatorProvider);
      if (!(kDebugMode && Platform.isWindows)) {
        await coordinator.start();
      }
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
    _syncStatusSub?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _windowsExitNeedsNotificationFlush = false;
      if (!(kDebugMode && Platform.isWindows)) {
        ref.read(notificationRescheduleCoordinatorProvider).rescheduleNow();
      }
      return;
    }

    if (Platform.isAndroid &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.detached)) {
      unawaited(
        BackgroundEventSync.scheduleOneOffSync(immediate: true).catchError((
          Object error,
        ) {
          debugPrint('Android immediate upload schedule failed: $error');
        }),
      );
      unawaited(
        ref
            .read(notificationRescheduleCoordinatorProvider)
            .rescheduleNow(force: true)
            .catchError((Object error) {
              debugPrint('Android exit notification reschedule failed: $error');
            }),
      );
      unawaited(
        ForegroundEventSyncService.startIfNeeded().catchError((Object error) {
          debugPrint('Android close upload service failed: $error');
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        title: 'Agenix',
        theme: AppTheme.build(),
        builder: (context, child) {
          final appChild = child ?? const SizedBox.shrink();
          return WindowsAppFrame(child: appChild);
        },
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          scrollbars: false,
        ),
        home: const AuthWrapper(),
        navigatorObservers: [appRouteObserver],
        routes: {
          SyncFeedbackScreen.routeName: (_) => const SyncFeedbackScreen(),
          SettingsScreen.routeName: (_) => const SettingsScreen(),
          '/calendar': (_) => const CalendarDayViewScreen(),
        },
      ),
    );
  }
}
