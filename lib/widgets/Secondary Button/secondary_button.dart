import 'dart:async';
import 'package:agenix/widgets/Custom%20Text/custom_text.dart';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class SecondaryButton extends StatefulWidget {
  const SecondaryButton({
    super.key,
    this.label = 'Secondary',
    this.child,
    required this.onPressed,
    this.icon,
    this.iconSize = 17,
    this.iconStrokeWidth = 2,
    this.loading = false,
    this.width,
    this.height,
    this.padding,
    this.backgroundColor = const Color(0xFF161616),
    this.foregroundColor = const Color(0xFFF4F4F5),
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.borderSide = const BorderSide(color: Color(0xFF2A2A2A)),
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.textStyle,
    this.minimumSize,
    this.maximumSize,
    this.elevation,
    this.style,
  }) : assert(
         label != null || child != null || icon != null,
         'Provide label, child, or icon.',
       ),
       assert(label == null || child == null, 'Use label or child, not both.');

  final String? label;
  final Widget? child;
  final FutureOr<void> Function()? onPressed;
  final Widget? icon;
  final double iconSize;
  final double iconStrokeWidth;
  final bool loading;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? disabledBackgroundColor;
  final Color? disabledForegroundColor;
  final BorderSide? borderSide;
  final BorderRadiusGeometry borderRadius;
  final TextStyle? textStyle;
  final Size? minimumSize;
  final Size? maximumSize;
  final double? elevation;
  final ButtonStyle? style;

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton> {
  static const _actionDelay = Duration(seconds: 2);
  static const _blankDelay = Duration(milliseconds: 500);

  Timer? _contentRevealTimer;
  Timer? _spinnerTimer;
  Animation<double>? _routeAnimation;
  Animation<double>? _secondaryAnimation;
  bool _internalLoading = false;
  bool _resetImmediately = false;
  bool _contentVisible = true;
  bool _showSpinner = false;
  bool _wasTickerEnabled = true;
  bool _routeWasCovered = false;
  bool _returnedFromRoute = false;

  bool get _isLoading => _internalLoading;
  bool get _isBusy => _internalLoading || !_contentVisible;

  Widget? _configuredIcon(Widget? icon) {
    if (icon is! HugeIcon) return icon;
    return HugeIcon(
      icon: icon.icon,
      color: icon.color ?? widget.foregroundColor,
      secondaryColor: icon.secondaryColor,
      disableSecondaryOpacity: icon.disableSecondaryOpacity,
      size: icon.size ?? widget.iconSize,
      strokeWidth: icon.strokeWidth ?? widget.iconStrokeWidth,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeAnimation = ModalRoute.of(context)?.animation;
    final secondaryAnimation = ModalRoute.of(context)?.secondaryAnimation;
    if (routeAnimation == _routeAnimation &&
        secondaryAnimation == _secondaryAnimation) {
      return;
    }
    _routeAnimation?.removeListener(_handleRouteAnimation);
    _secondaryAnimation?.removeListener(_handleRouteAnimation);
    _routeAnimation = routeAnimation;
    _secondaryAnimation = secondaryAnimation;
    _routeAnimation?.addListener(_handleRouteAnimation);
    _secondaryAnimation?.addListener(_handleRouteAnimation);
  }

  void _handleRouteAnimation() {
    final status = _routeAnimation?.status;
    final secondaryStatus = _secondaryAnimation?.status;
    if (secondaryStatus == AnimationStatus.forward ||
        secondaryStatus == AnimationStatus.completed) {
      _routeWasCovered = true;
    }
    if (_routeWasCovered &&
        (secondaryStatus == AnimationStatus.reverse ||
            secondaryStatus == AnimationStatus.dismissed)) {
      _routeWasCovered = false;
      _returnedFromRoute = true;
      _resetLoadingState();
    }
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _resetLoadingState();
    }
  }

  void _resetLoadingState() {
    _contentRevealTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _internalLoading = false;
      _resetImmediately = true;
      _contentVisible = true;
      _showSpinner = false;
    });
  }

  void _resetForAction() {
    _contentRevealTimer?.cancel();
    setState(() {
      _internalLoading = false;
      _resetImmediately = false;
      _contentVisible = false;
      _showSpinner = false;
    });
    _contentRevealTimer = Timer(_blankDelay, () {
      if (!mounted) return;
      setState(() {
        _resetImmediately = false;
        _contentVisible = true;
      });
    });
  }

  void _startLoading() {
    _resetImmediately = false;
    _contentVisible = false;
    _showSpinner = false;
    _spinnerTimer?.cancel();
    _spinnerTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _showSpinner = true);
    });
    setState(() {});
  }

  Future<void> _handlePressed() async {
    if (_isBusy || widget.onPressed == null) return;
    if (!widget.loading) {
      await widget.onPressed!();
      return;
    }

    _internalLoading = true;
    _startLoading();
    try {
      await Future<void>.delayed(_actionDelay);
      if (!mounted) return;
      await widget.onPressed!();
    } finally {
      if (mounted) {
        if (_returnedFromRoute) {
          _returnedFromRoute = false;
          _resetLoadingState();
        } else {
          _resetForAction();
        }
      }
    }
  }

  @override
  void dispose() {
    _contentRevealTimer?.cancel();
    _spinnerTimer?.cancel();
    _routeAnimation?.removeListener(_handleRouteAnimation);
    _secondaryAnimation?.removeListener(_handleRouteAnimation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (!_wasTickerEnabled && tickerEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetLoadingState();
      });
    }
    _wasTickerEnabled = tickerEnabled;
    final isDisabled = widget.onPressed == null || _isBusy;
    final isIconOnly =
        widget.icon != null && widget.label == null && widget.child == null;
    final icon = _configuredIcon(widget.icon);

    final buttonStyle = OutlinedButton.styleFrom(
      backgroundColor: widget.backgroundColor,
      foregroundColor: widget.foregroundColor,
      disabledBackgroundColor:
          widget.disabledBackgroundColor ?? widget.backgroundColor,
      disabledForegroundColor:
          widget.disabledForegroundColor ?? widget.foregroundColor,
      padding:
          widget.padding ??
          (isIconOnly
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 25, vertical: 17)),
      alignment: Alignment.center,
      minimumSize: widget.minimumSize ?? (isIconOnly ? Size.zero : null),
      maximumSize: widget.maximumSize,
      elevation: widget.elevation,
      side: widget.borderSide,
      shape: RoundedRectangleBorder(borderRadius: widget.borderRadius),
    ).merge(widget.style);

    final content =
        widget.child ??
        (widget.label != null
            ? CustomTextBody(
                widget.label!,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: widget.foregroundColor,
                ).merge(widget.textStyle),
              )
            : icon!);
    final hasIconAndContent =
        widget.icon != null && (widget.label != null || widget.child != null);
    final normalContent = hasIconAndContent
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon!,
              const SizedBox(width: 8),
              Flexible(child: content),
            ],
          )
        : content;
    final buttonContent = Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          excluding: _isLoading,
          child: AnimatedOpacity(
            opacity: _contentVisible ? 1 : 0,
            duration: _resetImmediately
                ? Duration.zero
                : const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            child: normalContent,
          ),
        ),
        AnimatedSwitcher(
          duration: _resetImmediately
              ? Duration.zero
              : const Duration(milliseconds: 500),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _showSpinner
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color:
                        widget.disabledForegroundColor ??
                        widget.foregroundColor,
                    semanticsLabel: 'Loading',
                  ),
                )
              : const SizedBox(key: ValueKey('content-placeholder')),
        ),
      ],
    );

    final button = OutlinedButton(
      onPressed: isDisabled ? null : _handlePressed,
      style: buttonStyle,
      child: buttonContent,
    );

    return SizedBox(width: widget.width, height: widget.height, child: button);
  }
}
