import 'dart:async';
import 'dart:io' show Platform, InternetAddress;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/google_calendar_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/modern_splash_screen.dart';
import 'calendar_day_view_screen.dart';
import 'calendar_selection_screen.dart';
import 'sign_in_screen.dart';

/// Wrapper widget that checks authentication status and routes accordingly.
/// Shows sign-in screen if not authenticated, otherwise shows the main app.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  static const Duration _minimumSplashDuration = Duration(seconds: 3);

  bool _isLoading = true;
  bool _isSignedIn = false;
  bool _hasDefaultCalendar = false;
  bool _offlineDialogActive = false;
  bool _watchingReconnect = false;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkAuthStatus() async {
    final splashStart = DateTime.now();

    // Try silent sign-in first (especially for Android/iOS).
    if (Platform.isAndroid || Platform.isIOS) {
      await GoogleCalendarService.instance.trySilentSignIn();
    }

    // Check final authentication status.
    final signedIn = await GoogleCalendarService.instance.isSignedIn();
    var hasDefault = false;

    if (signedIn) {
      hasDefault = await GoogleCalendarService.instance.storage
          .hasDefaultCalendar();
    }

    if (signedIn && hasDefault) {
      unawaited(_warmUpDayViewData());
    }

    final elapsed = DateTime.now().difference(splashStart);
    final remaining = _minimumSplashDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (!mounted) return;
    setState(() {
      _isSignedIn = signedIn;
      _hasDefaultCalendar = hasDefault;
      _isLoading = false;
    });

    unawaited(_showOfflineDialogIfNeeded());
  }

  Future<void> _warmUpDayViewData() async {
    try {
      await Future.wait([
        GoogleCalendarService.instance.storage.getDefaultCalendarId(),
        GoogleCalendarService.instance.getCachedCalendars(),
        GoogleCalendarService.instance.getAccountDetails(),
      ]);
    } catch (_) {
      // Best-effort warm-up only.
    }
  }

  Future<void> _onSignInSuccess() async {
    final hasDefault = await GoogleCalendarService.instance.storage
        .hasDefaultCalendar();
    if (!mounted) return;
    setState(() {
      _isSignedIn = true;
      _hasDefaultCalendar = hasDefault;
    });
  }

  void _onCalendarSelected() {
    setState(() {
      _hasDefaultCalendar = true;
    });
  }

  Future<void> _onReAuthenticationNeeded() async {
    await GoogleCalendarService.instance.signOut();
    if (!mounted) return;
    setState(() {
      _isSignedIn = false;
      _hasDefaultCalendar = false;
    });
  }

  Future<void> _onSignOut() async {
    await GoogleCalendarService.instance.storage.clearDefaultCalendar();
    if (!mounted) return;
    setState(() {
      _isSignedIn = false;
      _hasDefaultCalendar = false;
    });
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final resp = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 204 || resp.statusCode == 200) return true;
    } catch (_) {
      // Fallback below.
    }

    try {
      final result = await InternetAddress.lookup(
        'one.one.one.one',
      ).timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showOfflineDialogIfNeeded() async {
    if (!mounted || _isLoading || _offlineDialogActive) return;

    final online = await _hasInternetConnection();
    if (!mounted || online || _offlineDialogActive) return;

    _offlineDialogActive = true;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 20,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 10),
            const Text('No Internet'),
          ],
        ),
        content: const Text(
          'You are offline now.\n\n'
          'Retry to check connection again.\n'
          'Continue to use the app offline. It will auto sync when internet returns.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('continue'),
            child: const Text('Continue'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop('retry'),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
    _offlineDialogActive = false;
    if (!mounted) return;

    if (choice == 'retry') {
      await _showOfflineDialogIfNeeded();
      return;
    }

    _startReconnectWatcher();
  }

  void _startReconnectWatcher() {
    if (_watchingReconnect) return;
    _watchingReconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted) return;
      final online = await _hasInternetConnection();
      if (!mounted || !online) return;

      _reconnectTimer?.cancel();
      _watchingReconnect = false;

      showAppSnackBar(
        context,
        'Internet is back. Auto sync is now running.',
        type: AppSnackBarType.success,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_isLoading) {
      child = const ModernSplashScreen();
    } else if (!_isSignedIn) {
      child = SignInScreen(
        onSignInSuccess: () {
          unawaited(_onSignInSuccess());
        },
      );
    } else if (!_hasDefaultCalendar) {
      child = CalendarSelectionScreen(
        onCalendarSelected: _onCalendarSelected,
        onReAuthenticationNeeded: () {
          unawaited(_onReAuthenticationNeeded());
        },
      );
    } else {
      child = _DayViewTransitionShell(onSignOut: _onSignOut);
    }

    final shouldBypassRootSwitcher = _isSignedIn && _hasDefaultCalendar;
    if (shouldBypassRootSwitcher) {
      return child;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      transitionBuilder: (widget, animation) {
        return FadeTransition(opacity: animation, child: widget);
      },
      child: KeyedSubtree(
        key: ValueKey<String>('auth-${child.runtimeType}'),
        child: child,
      ),
    );
  }
}

class _DayViewTransitionShell extends StatefulWidget {
  const _DayViewTransitionShell({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  State<_DayViewTransitionShell> createState() =>
      _DayViewTransitionShellState();
}

class _DayViewTransitionShellState extends State<_DayViewTransitionShell>
    with SingleTickerProviderStateMixin {
  static const Duration _overlayFallback = Duration(milliseconds: 1800);
  static const Duration _overlayFadeOutDelay = Duration(milliseconds: 220);
  static const Duration _overlayFadeOutDuration = Duration(milliseconds: 480);

  late final AnimationController _overlayController;
  late final Animation<double> _overlayOpacity;
  Timer? _overlayFallbackTimer;
  bool _overlayVisible = true;
  bool _dayViewReady = false;

  @override
  void initState() {
    super.initState();
    _overlayController = AnimationController(
      vsync: this,
      duration: _overlayFadeOutDuration,
      value: 1,
    );
    _overlayOpacity = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOutCubic,
    );
    _armOverlayFallback();
  }

  @override
  void dispose() {
    _overlayFallbackTimer?.cancel();
    _overlayController.dispose();
    super.dispose();
  }

  void _armOverlayFallback() {
    _overlayFallbackTimer?.cancel();
    _overlayFallbackTimer = Timer(_overlayFallback, () {
      unawaited(_fadeOutOverlay());
    });
  }

  void _onDayViewInitialReady() {
    if (_dayViewReady) return;
    _dayViewReady = true;
    _overlayFallbackTimer?.cancel();
    Future.delayed(_overlayFadeOutDelay, () {
      if (!mounted) return;
      unawaited(_fadeOutOverlay());
    });
  }

  Future<void> _fadeOutOverlay() async {
    if (!_overlayVisible) return;
    if (_overlayController.status == AnimationStatus.reverse ||
        _overlayController.status == AnimationStatus.dismissed) {
      return;
    }

    await _overlayController.reverse();
    if (!mounted) return;
    setState(() {
      _overlayVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CalendarDayViewScreen(
            onSignOut: () {
              unawaited(widget.onSignOut());
            },
            onInitialReady: _onDayViewInitialReady,
          ),
        ),
        if (_overlayVisible)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: FadeTransition(
                  opacity: _overlayOpacity,
                  child: const ModernSplashScreen(
                    embedded: true,
                    animateIntro: false,
                    showLoading: true,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
