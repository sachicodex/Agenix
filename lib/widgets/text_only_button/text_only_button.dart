import 'package:flutter/material.dart';

/// A reusable text-style button with no background or border by default.
///
/// Use [label] for text, [icon] for an icon-only button, or both together.
/// [icon] accepts any widget, including Flutter's [Icon] and package icons
/// such as `HugeIcon`.
///
/// This widget is intentionally not applied anywhere in the app yet. It can
/// be introduced one action at a time when a text-only action is needed.
class TextOnlyButton extends StatelessWidget {
  const TextOnlyButton({
    super.key,
    this.label,
    this.child,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.width,
    this.height,
    this.padding,
    this.backgroundColor,
    this.foregroundColor = const Color(0xFFF4F4F5),
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.overlayColor,
    this.borderSide,
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
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool loading;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? disabledBackgroundColor;
  final Color? disabledForegroundColor;
  final Color? overlayColor;
  final BorderSide? borderSide;
  final BorderRadiusGeometry borderRadius;
  final TextStyle? textStyle;
  final Size? minimumSize;
  final Size? maximumSize;
  final double? elevation;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || loading;
    final isIconOnly = icon != null && label == null && child == null;
    final content = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: disabledForegroundColor ?? foregroundColor,
            ),
          )
        : child ?? (label != null ? Text(label!, style: textStyle) : icon!);

    final buttonStyle = TextButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      disabledForegroundColor: disabledForegroundColor,
      overlayColor: overlayColor,
      padding: padding ?? (isIconOnly ? EdgeInsets.zero : null),
      minimumSize: minimumSize ?? (isIconOnly ? Size.zero : null),
      maximumSize: maximumSize,
      elevation: elevation,
      side: borderSide,
      alignment: Alignment.center,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
    ).merge(style);

    final hasIconAndContent = icon != null && (label != null || child != null);
    final button = !hasIconAndContent
        ? TextButton(
            onPressed: isDisabled ? null : onPressed,
            style: buttonStyle,
            child: content,
          )
        : TextButton.icon(
            onPressed: isDisabled ? null : onPressed,
            style: buttonStyle,
            icon: icon!,
            label: content,
          );

    return SizedBox(width: width, height: height, child: button);
  }
}
