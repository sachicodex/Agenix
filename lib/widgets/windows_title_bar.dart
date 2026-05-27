import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../navigation/app_navigator.dart';
import '../screens/settings_screen.dart';
import '../services/google_calendar_service.dart';
import 'app_animations.dart';
import '../theme/app_colors.dart';

class WindowsAppFrame extends StatelessWidget {
  const WindowsAppFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return child;
    }

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          const _WindowsTitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WindowsTitleBar extends StatefulWidget {
  const _WindowsTitleBar();

  @override
  State<_WindowsTitleBar> createState() => _WindowsTitleBarState();
}

class _WindowsTitleBarState extends State<_WindowsTitleBar>
    with WindowListener {
  bool _isMaximized = false;
  bool _isFocused = true;
  String? _userPhotoUrl;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadWindowState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserProfile();
    });
  }

  Future<void> _loadWindowState() async {
    final maximized = await windowManager.isMaximized();
    final focused = await windowManager.isFocused();
    if (!mounted) return;
    setState(() {
      _isMaximized = maximized;
      _isFocused = focused;
    });
  }

  Future<void> _loadUserProfile() async {
    final details = await GoogleCalendarService.instance.getAccountDetails();
    if (!mounted) return;
    setState(() {
      _userPhotoUrl = details['photoUrl'];
    });

    if ((_userPhotoUrl == null || _userPhotoUrl!.isEmpty) && mounted) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        _loadUserProfile();
      });
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (!mounted) return;
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (!mounted) return;
    setState(() => _isMaximized = false);
  }

  @override
  void onWindowFocus() {
    if (!mounted) return;
    setState(() => _isFocused = true);
    _loadUserProfile();
  }

  @override
  void onWindowBlur() {
    if (!mounted) return;
    setState(() => _isFocused = false);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> _openSettings() async {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    await navigator.pushNamed(SettingsScreen.routeName);
    if (!mounted) return;
    await _loadUserProfile();
  }

  Widget _buildProfileButton() {
    ImageProvider<Object>? imageProvider;
    final photoUrl = _userPhotoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
        imageProvider = NetworkImage(
          photoUrl,
          headers: const {'Cache-Control': 'max-age=3600'},
        );
      } else {
        try {
          final file = File(photoUrl);
          if (file.existsSync()) {
            imageProvider = FileImage(file);
          }
        } catch (_) {}
      }
    }

    return AppPressFeedback(
      child: IconButton(
        icon: SizedBox(
          width: 32,
          height: 32,
          child: imageProvider == null
              ? const Icon(Icons.account_circle, size: 32)
              : CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.transparent,
                  child: ClipOval(
                    child: Image(
                      image: imageProvider,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) {
                        return const Icon(Icons.account_circle, size: 32);
                      },
                    ),
                  ),
                ),
        ),
        tooltip: '',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        splashRadius: 18,
        onPressed: _openSettings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = _isFocused
        ? AppColors.surface
        : const Color(0xFF131313);
    final shellColor = _isFocused
        ? AppColors.background
        : const Color(0xFF101010);
    final borderColor = _isFocused
        ? AppColors.borderColor
        : AppColors.onSurface.withValues(alpha: 0.08);
    final titleColor = _isFocused
        ? AppColors.onBackground
        : AppColors.onSurface.withValues(alpha: 0.75);

    return Container(
      color: shellColor,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _toggleMaximize,
                      child: DragToMoveArea(
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/logo/agenix.png',
                              width: 20,
                              height: 20,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Agenix',
                              style: AppTextStyles.headline2.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                                color: titleColor,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildProfileButton(),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _TitleBarButton(
            icon: Icons.remove_rounded,
            onPressed: windowManager.minimize,
          ),
          const SizedBox(width: 8),
          _TitleBarButton(
            icon: _isMaximized
                ? Icons.filter_none_rounded
                : Icons.check_box_outline_blank_rounded,
            onPressed: _toggleMaximize,
          ),
          const SizedBox(width: 8),
          _TitleBarButton(
            icon: Icons.close_rounded,
            onPressed: windowManager.close,
            isClose: true,
          ),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final Future<void> Function() onPressed;
  final bool isClose;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final normalBackground = widget.isClose
        ? const Color(0xFF2B120B).withValues(alpha: 0.6)
        : AppColors.surface;
    final hoveredBackground = widget.isClose
        ? const Color(0xFF4A1F12)
        : const Color(0xFF24130D);
    final pressedBackground = widget.isClose
        ? const Color(0xFF5A2414)
        : const Color(0xFF31180F);
    final background = widget.isClose
        ? (_pressed
              ? pressedBackground
              : _hovered
              ? hoveredBackground
              : normalBackground)
        : (_pressed
              ? pressedBackground
              : _hovered
              ? hoveredBackground
              : normalBackground);
    final borderColor = widget.isClose
        ? Colors.transparent
        : _hovered
        ? AppColors.primary.withValues(alpha: 0.2)
        : AppColors.borderColor;
    final iconColor = _hovered
        ? AppColors.onBackground
        : AppColors.onSurface.withValues(alpha: 0.8);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () => widget.onPressed(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 46,
          height: 42,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Center(child: Icon(widget.icon, size: 16, color: iconColor)),
        ),
      ),
    );
  }
}
