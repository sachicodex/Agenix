import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.constraints,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.alignment,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blurSigma = 18,
    this.tintColor = Colors.white,
    this.tintOpacity = 0.055,
    this.borderColor = Colors.white,
    this.borderOpacity = 0.12,
    this.borderWidth = 1,
    this.boxShadow,
    this.decoration,
    this.foregroundDecoration,
    this.clipBehavior = Clip.antiAlias,
    this.transform,
    this.transformAlignment,
    this.onTap,
    this.materialColor = Colors.transparent,
    this.splashColor,
    this.highlightColor,
  });

  final Widget child;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final AlignmentGeometry? alignment;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color tintColor;
  final double tintOpacity;
  final Color borderColor;
  final double borderOpacity;
  final double borderWidth;
  final List<BoxShadow>? boxShadow;
  final Decoration? decoration;
  final Decoration? foregroundDecoration;
  final Clip clipBehavior;
  final Matrix4? transform;
  final AlignmentGeometry? transformAlignment;
  final VoidCallback? onTap;
  final Color materialColor;
  final Color? splashColor;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final cardDecoration =
        decoration ??
        BoxDecoration(
          color: tintColor.withValues(alpha: tintOpacity),
          borderRadius: borderRadius,
          border: Border.all(
            color: borderColor.withValues(alpha: borderOpacity),
            width: borderWidth,
          ),
          boxShadow:
              boxShadow ??
              [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
        );

    final content = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: clipBehavior,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: width,
          height: height,
          constraints: constraints,
          alignment: alignment,
          padding: padding,
          decoration: cardDecoration,
          foregroundDecoration: foregroundDecoration,
          transform: transform,
          transformAlignment: transformAlignment,
          child: Material(
            color: materialColor,
            child: InkWell(
              onTap: onTap,
              splashColor: splashColor,
              highlightColor: highlightColor,
              borderRadius: borderRadius,
              child: child,
            ),
          ),
        ),
      ),
    );

    return Padding(padding: margin, child: content);
  }
}
