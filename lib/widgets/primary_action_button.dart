import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class PrimaryActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final EdgeInsetsGeometry? padding;
  final Size? minimumSize;
  final BorderRadius borderRadius;
  final Gradient? gradient;
  final Gradient? disabledGradient;
  final ButtonStyle? style;

  const PrimaryActionButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.padding,
    this.minimumSize,
    this.borderRadius = AppButtonStyles.radius,
    this.gradient,
    this.disabledGradient,
    this.style,
  }) : icon = null;

  const PrimaryActionButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.padding,
    this.minimumSize,
    this.borderRadius = AppButtonStyles.radius,
    this.gradient,
    this.disabledGradient,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    final baseStyle =
        ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.onPrimary,
          disabledForegroundColor: AppColors.onPrimary.withValues(alpha: 0.7),
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          padding: padding,
          minimumSize: minimumSize ?? const Size(120, 44),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ).copyWith(
          elevation: WidgetStateProperty.all(0),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppColors.onPrimary.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.hovered)) {
              return AppColors.onPrimary.withValues(alpha: 0.06);
            }
            return null;
          }),
        );

    final resolvedStyle = style == null ? baseStyle : baseStyle.merge(style);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled
            ? (gradient ?? AppColors.primaryActionGradient)
            : (disabledGradient ??
                  gradient ??
                  AppColors.primaryActionGradientDisabled),
        borderRadius: borderRadius,
      ),
      child: icon == null
          ? ElevatedButton(
              onPressed: onPressed,
              style: resolvedStyle,
              child: label,
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              style: resolvedStyle,
              icon: icon!,
              label: label,
            ),
    );
  }
}
