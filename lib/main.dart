import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'data/local/local_event_store.dart';
import 'navigation/app_navigator.dart';
import 'navigation/app_route_observer.dart';
import 'providers/event_providers.dart';
import 'screens/auth_wrapper.dart';
import 'screens/calendar_day_view_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_feedback_screen.dart';
import 'services/background_event_sync.dart';
import 'services/firebase_bootstrap.dart';
import 'services/google_calendar_service.dart';
import 'services/settings_sync_coordinator.dart';
import 'services/sync_service.dart';
import 'services/system_tray_service.dart';
import 'theme/app_theme.dart';
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
  await dotenv.load(isOptional: true);
  try {
    await FirebaseBootstrap.ensureInitialized();
  } catch (error, stackTrace) {
    debugPrint('Firebase init failed: $error\n$stackTrace');
  }
  await LocalEventStore.instance.initialize();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final syncService = ref.read(syncServiceProvider);
    SystemTrayService.instance.setExitGuard(() async {
      if (_windowsExitPushInFlight != null) return true;
      if ((await LocalEventStore.instance.getPendingEvents()).isEmpty) {
        return false;
      }
      final push = syncService.pushLocalChanges(retryWhenLocked: true);
      _windowsExitPushInFlight = push;
      unawaited(push.whenComplete(() => _windowsExitPushInFlight = null));
      return true;
    });
    _syncStatusSub = ref.listenManual<AsyncValue<SyncStatus>>(
      syncStatusProvider,
      (previous, next) {
        final status = next.valueOrNull;
        if (status != null) SystemTrayService.instance.updateSyncStatus(status);
      },
    );
    SystemTrayService.instance.updateSyncStatus(syncService.status);
    Future.microtask(() async {
      SettingsSyncCoordinator.instance.start();
      await SystemTrayService.instance.initialize();
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
    if (Platform.isAndroid &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      unawaited(BackgroundEventSync.scheduleOneOffSync(immediate: true));
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: appNavigatorKey,
    title: 'Agenix',
    theme: AppTheme.build(),
    builder: (context, child) =>
        WindowsAppFrame(child: child ?? const SizedBox.shrink()),
    scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
    home: const AuthWrapper(),
    navigatorObservers: [appRouteObserver],
    routes: {
      SyncFeedbackScreen.routeName: (_) => const SyncFeedbackScreen(),
      SettingsScreen.routeName: (_) => const SettingsScreen(),
      '/calendar': (_) => const CalendarDayViewScreen(),
    },
  );
}
