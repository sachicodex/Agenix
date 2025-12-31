import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import '../services/google_calendar_service.dart';
import 'sign_in_screen.dart';
import 'calendar_selection_screen.dart';
import 'create_event_screen_v2.dart';

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
    if (_isLoading) {
      // Show loading screen while checking auth
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isSignedIn) {
      // Not signed in - show sign-in screen
      return SignInScreen(
        onSignInSuccess: _onSignInSuccess,
      );
    }

    if (!_hasDefaultCalendar) {
      // Signed in but no default calendar selected - show calendar selection
      return CalendarSelectionScreen(
        onCalendarSelected: _onCalendarSelected,
        onReAuthenticationNeeded: _onReAuthenticationNeeded,
      );
    }

    // Signed in and has default calendar - show main app
    return CreateEventScreenV2(
      onSignOut: _onSignOut,
    );
  }
}

