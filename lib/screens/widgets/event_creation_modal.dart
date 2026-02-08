import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/calendar_event.dart';
import '../../services/google_calendar_service.dart';
import '../../services/groq_service.dart';
import '../../services/api_key_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/date_time_field.dart';
import '../../widgets/reminder_field.dart';
import '../settings_screen.dart';
import '../../providers/event_providers.dart';

class EventCreationModal extends ConsumerStatefulWidget {
  final DateTime? startTime;
  final DateTime? endTime;
  final CalendarEvent? existingEvent;
  final VoidCallback onEventCreated;

  const EventCreationModal({
    super.key,
    this.startTime,
    this.endTime,
    this.existingEvent,
    required this.onEventCreated,
  });

  @override
  ConsumerState<EventCreationModal> createState() => _EventCreationModalState();
}

class _EventCreationModalState extends ConsumerState<EventCreationModal> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late DateTime _startTime;
  late DateTime _endTime;
  String? _selectedCalendarId;
  List<Map<String, dynamic>> _availableCalendars = [];
  bool _userHasSelectedCalendar = false;

  bool reminderOn = true;
  String reminderValue = ReminderOptions.values[0]; // '10 minutes'

  bool _titleAILoading = false;
  bool _descriptionAILoading = false;
  String? _originalUserTitle;
  final GroqService _groqService = GroqService();
  final ApiKeyStorageService _apiKeyStorage = ApiKeyStorageService();

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEvent;
    _startTime = existing?.startDateTime ?? widget.startTime ?? DateTime.now();
    _endTime =
        existing?.endDateTime ??
        widget.endTime ??
        _startTime.add(const Duration(hours: 1));
    // Snap to 15 minutes
    _startTime = _snapToQuarterHour(_startTime);
    _endTime = _snapToQuarterHour(_endTime);
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description;
      _selectedCalendarId = existing.calendarId;
      if (existing.reminders.isNotEmpty) {
        reminderOn = true;
        reminderValue = _reminderLabelFromMinutes(existing.reminders.first);
      } else {
        reminderOn = false;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _fetchCalendars();
      if (widget.existingEvent == null) {
        await _loadDefaultCalendar();
      }
    });
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

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _fetchCalendars() async {
    final applyCalendars = (List<Map<String, dynamic>> calendars) {
      final filteredCalendars = calendars.where((cal) {
        final name = (cal['name'] as String?) ?? '';
        return name.isNotEmpty && name.toLowerCase() != 'calendar';
      }).toList();

      if (mounted) {
        setState(() {
          _availableCalendars = filteredCalendars;
          if (_availableCalendars.isNotEmpty && _selectedCalendarId == null) {
            _selectedCalendarId = _availableCalendars.first['id'] as String?;
          }
        });
      }
    };

    try {
      final cached = await GoogleCalendarService.instance.getCachedCalendars();
      if (cached.isNotEmpty) {
        applyCalendars(cached);
      }

      final calendars = await GoogleCalendarService.instance.getUserCalendars();
      applyCalendars(calendars);
    } catch (e) {
      debugPrint('Error loading calendars: $e');
      if (mounted) {
        setState(() {
          if (_availableCalendars.isEmpty) {
            _availableCalendars = [
              {
                'id': 'primary',
                'name': 'Primary Calendar',
                'color': 0xFF039BE5,
              },
            ];
            _selectedCalendarId ??= 'primary';
          }
        });
      }
    }
  }

  Future<void> _loadDefaultCalendar() async {
    // In edit mode, keep the event's current calendar selection.
    if (widget.existingEvent != null) {
      return;
    }

    try {
      final storage = GoogleCalendarService.instance.storage;
      final defaultCalendarId = await storage.getDefaultCalendarId();
      if (defaultCalendarId != null && defaultCalendarId.isNotEmpty) {
        final calendarExists = _availableCalendars.any(
          (cal) => (cal['id'] as String?) == defaultCalendarId,
        );
        if (calendarExists &&
            mounted &&
            !_userHasSelectedCalendar &&
            _selectedCalendarId != defaultCalendarId) {
          setState(() {
            _selectedCalendarId = defaultCalendarId;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading default calendar: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAISetupPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Features Not Configured'),
        content: const Text(
          'AI features are not configured yet. Please set up your AI API key in Settings to use this feature.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushNamed(context, SettingsScreen.routeName);
            },
            child: const Text('Setup AI Features'),
          ),
        ],
      ),
    );
  }

  Future<void> _optimizeTitle() async {
    final hasApiKey = await _apiKeyStorage.hasApiKey();
    if (!hasApiKey) {
      _showAISetupPopup();
      return;
    }

    final currentTitle = _titleController.text.trim();
    if (currentTitle.isEmpty) {
      _showErrorDialog('Please enter a title first');
      return;
    }

    if (_originalUserTitle == null || _originalUserTitle!.isEmpty) {
      _originalUserTitle = currentTitle;
    }

    setState(() {
      _titleAILoading = true;
    });

    try {
      final optimizedTitle = await _groqService.optimizeTitle(currentTitle);
      if (mounted) {
        _titleController.text = optimizedTitle;
        _titleController.selection = TextSelection.fromPosition(
          TextPosition(offset: optimizedTitle.length),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Failed to optimize title: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _titleAILoading = false;
        });
      }
    }
  }

  Future<void> _optimizeOrGenerateDescription() async {
    final hasApiKey = await _apiKeyStorage.hasApiKey();
    if (!hasApiKey) {
      _showAISetupPopup();
      return;
    }

    final currentTitle = _titleController.text.trim();
    if (currentTitle.isEmpty) {
      _showErrorDialog('Please enter a title first');
      return;
    }

    if (_originalUserTitle == null || _originalUserTitle!.isEmpty) {
      _originalUserTitle = currentTitle;
    }

    setState(() {
      _descriptionAILoading = true;
    });

    try {
      final currentDescription = _descriptionController.text.trim();
      String result;

      final originalTitle = _originalUserTitle ?? currentTitle;
      final aiGeneratedTitle = currentTitle;

      if (currentDescription.isEmpty) {
        result = await _groqService.generateDescription(
          originalTitle,
          aiGeneratedTitle,
        );
      } else {
        result = await _groqService.optimizeDescription(
          originalTitle,
          aiGeneratedTitle,
          currentDescription,
        );
      }

      if (mounted) {
        _descriptionController.text = result;
        _descriptionController.selection = TextSelection.fromPosition(
          TextPosition(offset: result.length),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog(
          'Failed to ${_descriptionController.text.trim().isEmpty ? "generate" : "optimize"} description: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _descriptionAILoading = false;
        });
      }
    }
  }

  Future<void> _pickDateTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isStart) {
        _startTime = _snapToQuarterHour(combined);
        if (!_endTime.isAfter(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      } else {
        _endTime = _snapToQuarterHour(combined);
        if (!_endTime.isAfter(_startTime)) {
          _startTime = _endTime.subtract(const Duration(hours: 1));
        }
      }
    });
  }

  Future<void> _saveEvent() async {
    if (_titleController.text.trim().isEmpty) {
      _showErrorDialog('Event title is required.');
      return;
    }
    if (_selectedCalendarId == null || _selectedCalendarId!.isEmpty) {
      _showErrorDialog('Please choose a calendar.');
      return;
    }

    try {
      final minutes = reminderOn ? _parseReminderMinutes(reminderValue) : null;
      final calendarId = _selectedCalendarId ?? 'primary';
      final selected = _availableCalendars
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['id'] == calendarId, orElse: () => {});
      final colorValue = selected['color'] as int?;
      final existing = widget.existingEvent;
      if (existing != null) {
        final updatedEvent = existing.copyWith(
          calendarId: calendarId,
          title: _titleController.text.trim(),
          startDateTime: _startTime,
          endDateTime: _endTime,
          allDay: false,
          color: Color(colorValue ?? AppColors.primary.value),
          description: _descriptionController.text.trim(),
          timezone: DateTime.now().timeZoneName,
          reminders: minutes == null ? const [] : [minutes],
        );
        await ref.read(eventRepositoryProvider).updateEvent(updatedEvent);
      } else {
        final event = CalendarEvent(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          calendarId: calendarId,
          title: _titleController.text.trim(),
          startDateTime: _startTime,
          endDateTime: _endTime,
          allDay: false,
          color: Color(colorValue ?? AppColors.primary.value),
          description: _descriptionController.text.trim(),
          location: '',
          timezone: DateTime.now().timeZoneName,
          reminders: minutes == null ? const [] : [minutes],
        );
        await ref.read(eventRepositoryProvider).createEvent(event);
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onEventCreated();
      }

      unawaited(
        ref.read(syncServiceProvider).pushLocalChanges().catchError((e) {
          debugPrint('Background sync failed after save: $e');
        }),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving event: $e')));
      }
    }
  }

  int _parseReminderMinutes(String value) {
    switch (value) {
      case '30 minutes':
        return 30;
      case '1 hour':
        return 60;
      case '1 day':
        return 24 * 60;
      case '10 minutes':
      default:
        return 10;
    }
  }

  String _reminderLabelFromMinutes(int minutes) {
    if (minutes >= 24 * 60) return '1 day';
    if (minutes >= 60) return '1 hour';
    if (minutes >= 30) return '30 minutes';
    return '10 minutes';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existingEvent == null ? 'Create Event' : 'Edit Event',
              style: AppTextStyles.headline2,
            ),
            const SizedBox(height: 24),
            LargeTextField(
              controller: _titleController,
              autofocus: true,
              hint: 'Event title',
              label: 'Title',
              requiredField: true,
              onAIClick: _optimizeTitle,
              aiLoading: _titleAILoading,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DateTimeField(
                    label: 'Start',
                    dateTime: _startTime,
                    onTap: () => _pickDateTime(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DateTimeField(
                    label: 'End',
                    dateTime: _endTime,
                    onTap: () => _pickDateTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value:
                  _selectedCalendarId ??
                  (_availableCalendars.isNotEmpty
                      ? _availableCalendars.first['id'] as String?
                      : null),
              decoration: InputDecoration(
                labelText: 'Select Calendar',
                labelStyle: AppTextStyles.bodyText1.copyWith(
                  color: AppColors.onSurface.withOpacity(0.7),
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: AppTextStyles.bodyText1,
              dropdownColor: AppColors.surface,
              isExpanded: true,
              items: _availableCalendars
                  .map(
                    (cal) => DropdownMenuItem<String>(
                      value: cal['id'] as String?,
                      child: Text(
                        (cal['name'] as String?) ?? '',
                        style: AppTextStyles.bodyText1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              selectedItemBuilder: (BuildContext context) {
                return _availableCalendars
                    .map<Widget>(
                      (cal) => Text(
                        (cal['name'] as String?) ?? '',
                        style: AppTextStyles.bodyText1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                    .toList();
              },
              onChanged: (val) {
                if (val != null && val != _selectedCalendarId) {
                  setState(() {
                    _selectedCalendarId = val;
                    _userHasSelectedCalendar = true;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            ExpandableDescription(
              controller: _descriptionController,
              hint: 'Description ( Optional )',
              onAIClick: _optimizeOrGenerateDescription,
              aiLoading: _descriptionAILoading,
            ),
            const SizedBox(height: 24),
            ReminderField(
              reminderOn: reminderOn,
              reminderValue: reminderValue,
              onToggle: (v) {
                if (v != reminderOn) {
                  setState(() => reminderOn = v);
                }
              },
              onTimeSelected: (v) {
                if (v != reminderValue) {
                  setState(() => reminderValue = v);
                }
              },
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveEvent,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
