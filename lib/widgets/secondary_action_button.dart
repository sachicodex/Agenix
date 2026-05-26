import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.iconBuilder,
    this.borderRadius = AppButtonStyles.secondaryActionRadius,
    this.padding = AppButtonStyles.secondaryActionPadding,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Widget Function(BuildContext context, IconData icon)? iconBuilder;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled
            ? AppGradients.secondaryActionButton
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF2A2A2A).withValues(alpha: 0.6),
                  const Color(0xFF1E1E1E).withValues(alpha: 0.6),
                ],
              ),
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
                iconBuilder?.call(context, icon) ??
                    Icon(
                      icon,
                      size: AppButtonStyles.secondaryActionIconSize,
                      color: AppColors.onSurface,
                    ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: AppButtonStyles.secondaryActionLabel,
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
