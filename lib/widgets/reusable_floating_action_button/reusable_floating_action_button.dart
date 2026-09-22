import 'dart:async';

import 'package:flutter/material.dart';

/// A floating action button that hides with the keyboard and reappears after
/// [keyboardCloseDelay] when the keyboard closes.
///
/// [child] accepts any widget, including Flutter [Icon], `HugeIcon`, SVG, or
/// a custom widget.
class ReusableFloatingActionButton extends StatefulWidget {
  const ReusableFloatingActionButton({
    super.key,
    required this.onPressed,
    this.child,
    this.icon = Icons.add,
    this.visible = true,
    this.keyboardCloseDelay = const Duration(seconds: 1),
    this.backgroundColor,
    this.foregroundColor,
    this.focusColor,
    this.hoverColor,
    this.splashColor,
    this.elevation,
    this.focusElevation,
    this.hoverElevation,
    this.highlightElevation,
    this.disabledElevation,
    this.shape,
    this.mini = false,
    this.heroTag,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.enableFeedback,
    this.materialTapTargetSize,
  }) : assert(child != null || icon != null, 'Provide child or icon.');

  final VoidCallback? onPressed;
  final Widget? child;
  final IconData? icon;
  final bool visible;
  final Duration keyboardCloseDelay;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? focusColor;
  final Color? hoverColor;
  final Color? splashColor;
  final double? elevation;
  final double? focusElevation;
  final double? hoverElevation;
  final double? highlightElevation;
  final double? disabledElevation;
  final ShapeBorder? shape;
  final bool mini;
  final Object? heroTag;
  final bool autofocus;
  final Clip clipBehavior;
  final bool? enableFeedback;
  final MaterialTapTargetSize? materialTapTargetSize;

  @override
  State<ReusableFloatingActionButton> createState() =>
      _ReusableFloatingActionButtonState();
}

class _ReusableFloatingActionButtonState
    extends State<ReusableFloatingActionButton> {
  Timer? _showTimer;
  bool _keyboardVisible = false;
  bool _hiddenForKeyboard = false;

  void _syncKeyboardState(bool keyboardVisible) {
    if (keyboardVisible == _keyboardVisible) return;
    _keyboardVisible = keyboardVisible;
    _showTimer?.cancel();
    if (keyboardVisible) {
      _hiddenForKeyboard = true;
    } else {
      _showTimer = Timer(widget.keyboardCloseDelay, () {
        if (mounted) setState(() => _hiddenForKeyboard = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncKeyboardState(MediaQuery.viewInsetsOf(context).bottom > 0);
    if (!widget.visible || _hiddenForKeyboard) return const SizedBox.shrink();

    return FloatingActionButton(
      onPressed: widget.onPressed,
      backgroundColor: widget.backgroundColor,
      foregroundColor: widget.foregroundColor,
      focusColor: widget.focusColor,
      hoverColor: widget.hoverColor,
      splashColor: widget.splashColor,
      elevation: widget.elevation,
      focusElevation: widget.focusElevation,
      hoverElevation: widget.hoverElevation,
      highlightElevation: widget.highlightElevation,
      disabledElevation: widget.disabledElevation,
      shape: widget.shape,
      mini: widget.mini,
      heroTag: widget.heroTag,
      autofocus: widget.autofocus,
      clipBehavior: widget.clipBehavior,
      enableFeedback: widget.enableFeedback,
      materialTapTargetSize: widget.materialTapTargetSize,
      child: widget.child ?? Icon(widget.icon),
    );
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }
}
