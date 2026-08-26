import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';

class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({
    super.key,
    required this.onPressed,
    this.icon,
    this.appIcon,
    required this.label,
    this.iconBuilder,
    this.borderRadius = AppButtonStyles.secondaryActionRadius,
    this.padding = AppButtonStyles.secondaryActionPadding,
    this.gradient,
    this.disabledGradient,
    this.labelStyle,
  }) : assert(icon != null || appIcon != null, 'Provide icon or appIcon.');

  final VoidCallback? onPressed;

  /// Legacy Material icon input. Prefer [appIcon] in new reusable UI.
  final IconData? icon;
  final AppIconData? appIcon;
  final String label;
  final Widget Function(BuildContext context, IconData icon)? iconBuilder;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Gradient? disabledGradient;

  /// Overrides the default bold label style for this button only.
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled
            ? (gradient ?? AppGradients.secondaryActionButton)
            : (disabledGradient ??
                  gradient ??
                  LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF2A2A2A).withValues(alpha: 0.6),
                      const Color(0xFF1E1E1E).withValues(alpha: 0.6),
                    ],
                  )),
        borderRadius: borderRadius,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppColors.onSurface.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.hovered)) {
              return AppColors.onSurface.withValues(alpha: 0.06);
            }
            return null;
          }),
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                if (appIcon != null)
                  AppIcon(
                    icon: appIcon!,
                    size: AppButtonStyles.secondaryActionIconSize,
                    color: AppColors.onSurface,
                  )
                else
                  iconBuilder?.call(context, icon!) ??
                      Icon(
                        icon!,
                        size: AppButtonStyles.secondaryActionIconSize,
                        color: AppColors.onSurface,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: AppButtonStyles.secondaryActionLabel.merge(
                      labelStyle,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
