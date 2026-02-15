import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/calendar_event.dart';
import '../../theme/app_colors.dart';
import '../../providers/event_providers.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/primary_action_button.dart';
import 'event_creation_modal.dart';

class EventDetailsPopover extends ConsumerWidget {
  final CalendarEvent event;
  final VoidCallback onEventUpdated;
  final VoidCallback onEventDeleted;

  const EventDetailsPopover({
    super.key,
    required this.event,
    required this.onEventUpdated,
    required this.onEventDeleted,
  });

  Future<void> _deleteEvent(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: const Text('Are you sure you want to delete this event?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(eventRepositoryProvider).deleteEvent(event.id);
        await ref.read(syncServiceProvider).pushLocalChanges();

        if (context.mounted) {
          Navigator.pop(context);
          onEventDeleted();
        }
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(
            context,
            'Error deleting event: $e',
            type: AppSnackBarType.error,
          );
        }
      }
    }
  }

  Future<void> _editEvent(BuildContext context) async {
    Navigator.pop(context);
    final isMobile = MediaQuery.of(context).size.width < 700;
    if (isMobile) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: true,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        builder: (context) => EventCreationModal(
          existingEvent: event,
          onEventCreated: onEventUpdated,
          renderAsBottomSheetContent: true,
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (context) => EventCreationModal(
          existingEvent: event,
          onEventCreated: onEventUpdated,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: AppColors.surface,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                Expanded(
                  child: Text(event.title, style: AppTextStyles.headline2),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Time
            if (event.allDay)
              Text(
                DateFormat('EEEE, MMMM d, y').format(event.startDateTime),
                style: AppTextStyles.bodyText1,
              )
            else
              Text(
                '${DateFormat('EEEE, MMMM d, y').format(event.startDateTime)} • ${DateFormat('h:mm a').format(event.startDateTime)} - ${DateFormat('h:mm a').format(event.endDateTime)}',
                style: AppTextStyles.bodyText1,
              ),
            const SizedBox(height: 16),
            // Description
            if (event.description.isNotEmpty) ...[
              Text(event.description, style: AppTextStyles.bodyText1),
              const SizedBox(height: 16),
            ],
            // Color indicator
            Container(
              width: double.infinity,
              height: 4,
              decoration: BoxDecoration(
                color: event.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _editEvent(context),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteEvent(context, ref),
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EventEditModal extends ConsumerStatefulWidget {
  final CalendarEvent event;
  final VoidCallback onEventUpdated;
  final String? calendarId;

  const EventEditModal({
    required this.event,
    required this.onEventUpdated,
    this.calendarId,
  });

  @override
  ConsumerState<EventEditModal> createState() => _EventEditModalState();
}

class _EventEditModalState extends ConsumerState<EventEditModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late DateTime _startTime;
  late DateTime _endTime;
  late bool _allDay;
  late Color _selectedColor;
  final List<int> _reminders = [];

  final List<Color> _colorOptions = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.event.title);
    _descriptionController = TextEditingController(
      text: widget.event.description,
    );
    _startTime = widget.event.startDateTime;
    _endTime = widget.event.endDateTime;
    _allDay = widget.event.allDay;
    _selectedColor = widget.event.color;
    _reminders.addAll(widget.event.reminders);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  DateTime _snapToQuarterHour(DateTime dateTime) {
    final minute = dateTime.minute;
    final snappedMinute = (minute / 15).floor() * 15;
    return DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
      dateTime.hour,
      snappedMinute,
    );
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (picked != null) {
      setState(() {
        _startTime = DateTime(
          _startTime.year,
          _startTime.month,
          _startTime.day,
          picked.hour,
          picked.minute,
        );
        _startTime = _snapToQuarterHour(_startTime);
        if (_endTime.isBefore(_startTime) ||
            _endTime.isAtSameMomentAs(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      });
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime),
    );
    if (picked != null) {
      setState(() {
        _endTime = DateTime(
          _endTime.year,
          _endTime.month,
          _endTime.day,
          picked.hour,
          picked.minute,
        );
        _endTime = _snapToQuarterHour(_endTime);
        if (_endTime.isBefore(_startTime) ||
            _endTime.isAtSameMomentAs(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _startTime.hour,
          _startTime.minute,
        );
        _endTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _endTime.hour,
          _endTime.minute,
        );
      });
    }
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    final updatedEvent = widget.event.copyWith(
      title: _titleController.text.trim(),
      startDateTime: _startTime,
      endDateTime: _endTime,
      allDay: _allDay,
      color: _selectedColor,
      description: _descriptionController.text.trim(),
      reminders: _reminders,
    );

    try {
      await ref.read(eventRepositoryProvider).updateEvent(updatedEvent);
      if (mounted) {
        Navigator.pop(context);
        widget.onEventUpdated();
      }

      unawaited(
        ref.read(syncServiceProvider).pushLocalChanges().catchError((e) {
          debugPrint('Background sync failed after update: $e');
        }),
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Error updating event: $e',
          type: AppSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit Event', style: AppTextStyles.headline2),
              const SizedBox(height: 24),
              // Title
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Add title',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Date
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(DateFormat('MMM d, y').format(_startTime)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _allDay,
                    onChanged: (value) {
                      setState(() {
                        _allDay = value;
                      });
                    },
                  ),
                  const Text('All day'),
                ],
              ),
              const SizedBox(height: 16),
              // Time
              if (!_allDay) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectStartTime,
                        icon: const Icon(Icons.access_time),
                        label: Text(DateFormat('h:mm a').format(_startTime)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('-'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectEndTime,
                        icon: const Icon(Icons.access_time),
                        label: Text(DateFormat('h:mm a').format(_endTime)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Add description',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              // Color picker
              const Text('Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _colorOptions.map((color) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColor = color;
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColor == color
                              ? AppColors.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  PrimaryActionButton(
                    onPressed: _saveEvent,
                    label: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
