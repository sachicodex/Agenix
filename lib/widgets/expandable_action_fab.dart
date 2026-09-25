import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'Glass Card/glass_carrd.dart';

class ExpandableFabAction {
  const ExpandableFabAction({
    required this.icon,
    this.tooltip,
    required this.onPressed,
  });

  final Widget icon;
  final String? tooltip;
  final VoidCallback onPressed;
}

class ExpandableActionFab extends StatelessWidget {
  const ExpandableActionFab({
    required this.expanded,
    required this.onToggle,
    required this.actions,
    this.size = 55,
    super.key,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final List<ExpandableFabAction> actions;
  final double size;

  @override
  Widget build(BuildContext context) {
    final height = size + (actions.length * (size + 12)) + 12;
    return SizedBox(
      width: size + 12,
      height: height,
      child: Stack(
        alignment: Alignment.bottomRight,
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < actions.length; index++)
            _buildAction(actions[index], index),
          GlassCard(
            width: size,
            height: size,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(18),
            tintColor: AppColors.primary,
            tintOpacity: 1,
            borderColor: AppColors.primary,
            borderOpacity: 1,
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
            onTap: onToggle,
            child: Center(
              child: AnimatedRotation(
                turns: expanded ? 0.125 : 0,
                duration: const Duration(milliseconds: 220),
                child: const Icon(
                  Icons.add_rounded,
                  size: 30,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAction(ExpandableFabAction action, int index) {
    final restingBottom = size + 12;
    final expandedBottom = restingBottom + (index * (size + 12));
    final child = GlassCard(
      width: size,
      height: size,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(15),
      blurSigma: 22,
      tintColor: AppColors.card,
      tintOpacity: 0.16,
      borderColor: AppColors.glassBorder,
      borderOpacity: 0.45,
      borderWidth: 2,
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 8)),
      ],
      onTap: action.onPressed,
      child: Center(
        child: action.tooltip == null
            ? action.icon
            : Tooltip(message: action.tooltip, child: action.icon),
      ),
    );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      right: 0,
      bottom: expanded ? expandedBottom : 4,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: expanded ? 1 : 0,
        child: IgnorePointer(ignoring: !expanded, child: child),
      ),
    );
  }
}
