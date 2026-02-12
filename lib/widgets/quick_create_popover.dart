import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import 'primary_action_button.dart';

/// Quick create popover that appears when clicking on empty time slot
/// Matches Google Calendar's quick create behavior
class QuickCreatePopover extends StatefulWidget {
  final DateTime startTime;
  final DateTime? endTime;
  final Offset position;
  final Function(DateTime start, DateTime end, String title) onCreate;
  final VoidCallback onCancel;

  const QuickCreatePopover({
    super.key,
    required this.startTime,
    this.endTime,
    required this.position,
    required this.onCreate,
    required this.onCancel,
  });

  @override
  State<QuickCreatePopover> createState() => _QuickCreatePopoverState();
}

class _QuickCreatePopoverState extends State<QuickCreatePopover> {
  final _titleController = TextEditingController();
  late DateTime _startTime;
  late DateTime _endTime;

  @override
  void initState() {
    super.initState();
    _startTime = widget.startTime;
    _endTime = widget.endTime ?? _startTime.add(const Duration(minutes: 30));
    // Auto-focus title input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _handleCreate() {
    if (_titleController.text.trim().isNotEmpty) {
      widget.onCreate(_startTime, _endTime, _titleController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Click-away overlay
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onCancel,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Popover content
          Positioned(
            left: widget.position.dx,
            top: widget.position.dy,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: AppColors.surface,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderColor),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title input (auto-focused)
                    TextField(
                      controller: _titleController,
                      autofocus: false,
                      decoration: const InputDecoration(
                        hintText: 'Add title',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      onSubmitted: (_) => _handleCreate(),
                    ),
                    const SizedBox(height: 8),
                    // Time display
                    Text(
                      '${DateFormat('h:mm a').format(_startTime)} - ${DateFormat('h:mm a').format(_endTime)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: widget.onCancel,
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        PrimaryActionButton(
                          onPressed: _handleCreate,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
