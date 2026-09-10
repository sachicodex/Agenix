import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/calendar_event.dart';
import '../../theme/app_colors.dart';
import '../../providers/event_providers.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_popup.dart';
import '../../widgets/primary_action_button.dart';
import 'event_creation_modal.dart';
import '../../utils/platform_focus.dart';

class EventDetailsPopover extends StatelessWidget {
  final CalendarEvent event;
  final VoidCallback onEventUpdated;

  const EventDetailsPopover({
    super.key,
    required this.event,
    required this.onEventUpdated,
  });

  Future<void> _editEvent(BuildContext context) async {
    Navigator.pop(context);
    final isMobile = MediaQuery.of(context).size.width < 700;
    if (isMobile) {
      await showAppModalBottomSheet<void>(
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
      await showAppDialog(
        context: context,
        builder: (context) => EventCreationModal(
          existingEvent: event,
          onEventCreated: onEventUpdated,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            _editEvent(context),
      },
      child: Dialog(
        backgroundColor: AppColors.surface,
        child: Container(
          width: appPopupWidth(context, 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(event.title, style: AppTextStyles.headline2),
              const SizedBox(height: 16),
              // Description
              if (event.description.isNotEmpty) ...[
                _ReadOnlyDescription(value: event.description),
                const SizedBox(height: 24),
              ],
              // Actions
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _editEvent(context),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyDescription extends StatefulWidget {
  const _ReadOnlyDescription({required this.value});

  final String value;

  @override
  State<_ReadOnlyDescription> createState() => _ReadOnlyDescriptionState();
}

class _ReadOnlyDescriptionState extends State<_ReadOnlyDescription> {
  late final QuillController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QuillController(
      document: _documentFromValue(widget.value),
      selection: const TextSelection.collapsed(offset: 0),
    )..readOnly = true;
  }

  Document _documentFromValue(String value) {
    if (value.startsWith('quill:')) {
      try {
        return Document.fromJson(jsonDecode(value.substring(6)) as List);
      } catch (_) {
        // Fall back to plain text for older or invalid stored values.
      }
    }
    final document = Document();
    if (value.isNotEmpty) document.insert(0, value);
    return document;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyles = DefaultStyles.getInstance(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: QuillEditor.basic(
        controller: _controller,
        config: QuillEditorConfig(
          autoFocus: false,
          showCursor: false,
          padding: EdgeInsets.zero,
          scrollable: true,
          customStyles: defaultStyles.merge(
            DefaultStyles(
              link: defaultStyles.link?.copyWith(
                decoration: TextDecoration.none,
              ),
            ),
          ),
          // ignore: experimental_member_use
          customLeadingBlockBuilder: (node, config) {
            if (config.attribute != Attribute.ol || node is! Line) {
              return null;
            }
            final textChildren = node.children
                .where((child) => child.toPlainText().isNotEmpty)
                .toList();
            final isEntireLineBold =
                textChildren.isNotEmpty &&
                textChildren.every(
                  (child) => child.style.containsKey(Attribute.bold.key),
                );
            if (!isEntireLineBold) return null;

            return QuillNumberPoint(
              index: config.getIndexNumberByIndent!,
              indentLevelCounts: config.indentLevelCounts,
              count: config.count,
              style: config.style!.copyWith(fontWeight: FontWeight.bold),
              attrs: config.attrs,
              width: config.width!,
              padding: config.padding!,
            );
          },
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
    super.key,
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
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
    );

    try {
      await ref.read(eventRepositoryProvider).updateEvent(updatedEvent);
      if (mounted) {
        Navigator.pop(context);
        widget.onEventUpdated();
      }
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
        width: appPopupWidth(context, 500),
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
                autofocus: shouldAutofocusTextInput,
                minLines: 1,
                maxLines: 3,
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
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Add description',
                ),
                maxLines: 5,
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
