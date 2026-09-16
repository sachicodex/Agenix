import 'package:flutter/material.dart';

/// Reusable dark surface container with independently configurable styling.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.backgroundColor = const Color(0xFF161616),
    this.borderColor = const Color(0xFF2A2A2A),
    this.borderWidth = 1,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.alignment,
    this.clipBehavior = Clip.none,
    this.onTap,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final BorderRadius borderRadius;
  final AlignmentGeometry? alignment;
  final Clip clipBehavior;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: width,
      height: height,
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      clipBehavior: clipBehavior,
      child: child,
    );
    return Padding(
      padding: margin,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, borderRadius: borderRadius, child: content),
    );
  }
}
