import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/auth_wrapper.dart';
import 'screens/create_event_screen.dart';
import 'screens/sync_feedback_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/calendar_day_view_screen.dart';
import 'theme/app_theme.dart';
import 'services/google_calendar_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agenix',
      theme: AppTheme.build(),
      home: const AuthWrapper(),
      routes: {
        CreateEventScreen.routeName: (_) => const CreateEventScreen(),
        SyncFeedbackScreen.routeName: (_) => const SyncFeedbackScreen(),
        SettingsScreen.routeName: (_) => const SettingsScreen(),
        '/calendar': (_) => const CalendarDayViewScreen(),
      },
    );
  }
}
