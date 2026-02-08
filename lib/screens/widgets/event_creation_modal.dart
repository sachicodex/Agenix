import 'package:flutter/material.dart';
import '../../models/calendar_event.dart';
import '../../services/event_storage_service.dart';
import '../../services/google_calendar_service.dart';
import '../../services/groq_service.dart';
import '../../services/api_key_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/date_time_field.dart';
import '../../widgets/reminder_field.dart';
import '../settings_screen.dart';

class EventCreationModal extends StatefulWidget {
  final DateTime? startTime;
  final DateTime? endTime;
  final VoidCallback onEventCreated;

  const EventCreationModal({
    super.key,
    this.startTime,
    this.endTime,
    required this.onEventCreated,
  });

  @override
  State<EventCreationModal> createState() => _EventCreationModalState();
}

class _EventCreationModalState extends State<EventCreationModal> {
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
    _startTime = widget.startTime ?? DateTime.now();
    _endTime = widget.endTime ?? _startTime.add(const Duration(hours: 1));
    // Snap to 15 minutes
    _startTime = _snapToQuarterHour(_startTime);
    _endTime = _snapToQuarterHour(_endTime);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _fetchCalendars();
      await _loadDefaultCalendar();
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
    try {
      final calendars = await GoogleCalendarService.instance.getUserCalendars();
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _availableCalendars = [
            {'id': 'primary', 'name': 'Primary Calendar', 'color': 0xFF039BE5},
          ];
          _selectedCalendarId ??= 'primary';
        });
      }
    }
  }

  Future<void> _loadDefaultCalendar() async {
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
      // Check if signed in to Google Calendar
      final signedIn = await GoogleCalendarService.instance.isSignedIn();
      final calendarId =
          await GoogleCalendarService.instance.storage.getDefaultCalendarId() ??
          'primary';

      if (signedIn) {
        List<Map<String, dynamic>>? reminders;
        if (reminderOn) {
          final minutes = _parseReminderMinutes(reminderValue);
          reminders = [
            {'method': 'popup', 'minutes': minutes},
          ];
        }

        await GoogleCalendarService.instance.insertEvent(
          summary: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          start: _startTime,
          end: _endTime,
          calendarId: _selectedCalendarId ?? calendarId,
          reminders: reminders,
        );
      } else {
        // Save locally if not signed in
        final event = CalendarEvent(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: _titleController.text.trim(),
          startDateTime: _startTime,
          endDateTime: _endTime,
          allDay: false,
          color: AppColors.primary,
          description: _descriptionController.text.trim(),
          reminders: reminderOn ? [_parseReminderMinutes(reminderValue)] : const [],
        );
        await EventStorageService.instance.addEvent(event);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onEventCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving event: $e')),
        );
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
              'Create Event',
              style: AppTextStyles.headline2,
            ),
            const SizedBox(height: 24),
            LargeTextField(
              controller: _titleController,
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

