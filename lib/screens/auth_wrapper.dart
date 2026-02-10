import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import '../services/google_calendar_service.dart';
import 'sign_in_screen.dart';
import 'calendar_selection_screen.dart';
import 'calendar_day_view_screen.dart';
import '../widgets/app_animations.dart';

/// Wrapper widget that checks authentication status and routes accordingly.
/// Shows sign-in screen if not authenticated, otherwise shows the main app.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isSignedIn = false;
  bool _hasDefaultCalendar = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // Try silent sign-in first (especially for Android/iOS)
    if (Platform.isAndroid || Platform.isIOS) {
      await GoogleCalendarService.instance.trySilentSignIn();
    }

    // Check final authentication status
    final signedIn = await GoogleCalendarService.instance.isSignedIn();

    if (signedIn) {
      // Check if default calendar is set
      final hasDefault = await GoogleCalendarService.instance.storage.hasDefaultCalendar();
      if (mounted) {
        setState(() {
          _isSignedIn = signedIn;
          _hasDefaultCalendar = hasDefault;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isSignedIn = false;
          _hasDefaultCalendar = false;
          _isLoading = false;
        });
      }
    }
  }

  void _onSignInSuccess() async {
    // User successfully signed in, check if default calendar is set
    final hasDefault = await GoogleCalendarService.instance.storage.hasDefaultCalendar();
    if (mounted) {
      setState(() {
        _isSignedIn = true;
        _hasDefaultCalendar = hasDefault;
      });
    }
  }

  void _onCalendarSelected() {
    // User selected default calendar, navigate to main app
    setState(() {
      _hasDefaultCalendar = true;
    });
  }

  void _onReAuthenticationNeeded() async {
    // User needs to re-authenticate (e.g., missing permissions)
    // Sign out and reset state
    await GoogleCalendarService.instance.signOut();
    if (mounted) {
      setState(() {
        _isSignedIn = false;
        _hasDefaultCalendar = false;
      });
    }
  }

  void _onSignOut() async {
    // User signed out, clear default calendar and update state
    await GoogleCalendarService.instance.storage.clearDefaultCalendar();
    if (mounted) {
      setState(() {
        _isSignedIn = false;
        _hasDefaultCalendar = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_isLoading) {
      // Show loading screen while checking auth
      child = const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    } else if (!_isSignedIn) {
      // Not signed in - show sign-in screen
      child = SignInScreen(
        onSignInSuccess: _onSignInSuccess,
      );
    } else if (!_hasDefaultCalendar) {
      // Signed in but no default calendar selected - show calendar selection
      child = CalendarSelectionScreen(
        onCalendarSelected: _onCalendarSelected,
        onReAuthenticationNeeded: _onReAuthenticationNeeded,
      );
    } else {
      // Signed in and has default calendar - show main app (CalendarDayViewScreen)
      child = CalendarDayViewScreen(
        onSignOut: _onSignOut,
      );
    }

    return AnimatedSwitcher(
      duration: AppAnimationDurations.slow,
      switchInCurve: AppAnimationCurves.emphasized,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey<String>('auth-${child.runtimeType}'),
        child: AppFadeSlideIn(
          key: ValueKey<String>('auth-entry-${child.runtimeType}'),
          child: child,
        ),
      ),
    );
  }
}

