import 'package:flutter/material.dart';

/// A reusable outlined button for secondary actions.
///
/// Use [label] for text, [icon] for an icon-only button, or both together.
/// [icon] accepts any widget, including Flutter's [Icon] and package icons
/// such as `HugeIcon`.
/// Copy the `secondary_button` folder into another Flutter project and use it
/// as:
///
/// ```dart
/// SecondaryButton(
///   label: 'Folder',
///   icon: const Icon(Icons.add),
///   onPressed: () {},
/// )
/// ```
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    this.label,
    this.child,
    required this.onPressed,
    this.icon,
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

    final buttonStyle = OutlinedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      disabledForegroundColor: disabledForegroundColor,
      padding: padding ?? (isIconOnly ? EdgeInsets.zero : null),
      alignment: Alignment.center,
      minimumSize: minimumSize ?? (isIconOnly ? Size.zero : null),
      maximumSize: maximumSize,
      elevation: elevation,
      side: borderSide,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
    ).merge(style);

    final hasIconAndContent = icon != null && (label != null || child != null);
    final button = !hasIconAndContent
        ? OutlinedButton(
            onPressed: isDisabled ? null : onPressed,
            style: buttonStyle,
            child: content,
          )
        : OutlinedButton.icon(
            onPressed: isDisabled ? null : onPressed,
            style: buttonStyle,
            icon: icon!,
            label: content,
          );

    return SizedBox(width: width, height: height, child: button);
  }
}
