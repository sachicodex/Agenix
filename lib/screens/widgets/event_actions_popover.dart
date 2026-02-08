import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';

class EventActionsPopover extends StatefulWidget {
  final Offset anchor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDismiss;

  const EventActionsPopover({
    super.key,
    required this.anchor,
    required this.onEdit,
    required this.onDelete,
    required this.onDismiss,
  });

  @override
  State<EventActionsPopover> createState() => _EventActionsPopoverState();
}

class _EventActionsPopoverState extends State<EventActionsPopover> {
  final FocusNode _popoverFocusNode = FocusNode();
  final FocusNode _editButtonFocusNode = FocusNode();

  static const double _popoverWidth = 160;
  static const double _popoverHeight = 92;
  static const double _edgeMargin = 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_editButtonFocusNode);
      }
    });
  }

  @override
  void dispose() {
    _popoverFocusNode.dispose();
    _editButtonFocusNode.dispose();
    super.dispose();
  }

  Offset _clampToViewport(Size size, EdgeInsets padding) {
    final minX = _edgeMargin + padding.left;
    final minY = _edgeMargin + padding.top;
    var maxX = size.width - _popoverWidth - _edgeMargin - padding.right;
    var maxY = size.height - _popoverHeight - _edgeMargin - padding.bottom;
    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;

    final desiredX = widget.anchor.dx + 8;
    final desiredY = widget.anchor.dy + 8;

    return Offset(desiredX.clamp(minX, maxX), desiredY.clamp(minY, maxY));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final clampedPosition = _clampToViewport(
      mediaQuery.size,
      mediaQuery.padding,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: const SizedBox.shrink(),
          ),
        ),
        Positioned(
          left: clampedPosition.dx,
          top: clampedPosition.dy,
          child: Focus(
            focusNode: _popoverFocusNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                widget.onDismiss();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Material(
              elevation: 8,
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: _popoverWidth,
                height: _popoverHeight,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderColor),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      focusNode: _editButtonFocusNode,
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onSurface,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
