import 'package:flutter/material.dart';


class CustomCard extends StatelessWidget {
  const CustomCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.backgroundColor = const Color(0xFF101010),
    this.borderColor = const Color(0xFF2A2A2A),
    this.borderWidth = 1,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.elevation = 0,
    this.clipBehavior = Clip.none,
    this.alignment,
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
  final double elevation;
  final Clip clipBehavior;
  final AlignmentGeometry? alignment;
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
        boxShadow: elevation <= 0
            ? null
            : [BoxShadow(color: Colors.black26, blurRadius: elevation)],
      ),
      clipBehavior: clipBehavior,
      child: child,
    );
    final interactive = onTap == null
        ? content
        : InkWell(onTap: onTap, borderRadius: borderRadius, child: content);
    return Padding(padding: margin, child: interactive);
  }
}
