import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Context menu widget for right-click actions
/// Matches Google Calendar's context menu behavior
class ContextMenu extends StatelessWidget {
  final Offset position;
  final List<ContextMenuItem> items;
  final VoidCallback onDismiss;

  const ContextMenu({
    super.key,
    required this.position,
    required this.items,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Click-away overlay
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Menu content
        Positioned(
          left: position.dx,
          top: position.dy,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: AppColors.surface,
            child: Container(
              constraints: const BoxConstraints(minWidth: 200),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: items.map((item) {
                  return _ContextMenuItemWidget(
                    item: item,
                    onDismiss: onDismiss,
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ContextMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const ContextMenuItem({
    required this.label,
    this.icon,
    required this.onTap,
    this.isDestructive = false,
  });
}

class _ContextMenuItemWidget extends StatelessWidget {
  final ContextMenuItem item;
  final VoidCallback onDismiss;

  const _ContextMenuItemWidget({
    required this.item,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        item.onTap();
        onDismiss();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(
                item.icon,
                size: 18,
                color: item.isDestructive
                    ? AppColors.error
                    : AppColors.onSurface,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  color: item.isDestructive
                      ? AppColors.error
                      : AppColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

