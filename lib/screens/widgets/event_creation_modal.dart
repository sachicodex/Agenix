import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../models/calendar_event.dart';
import '../../services/google_calendar_service.dart';
import '../../services/groq_service.dart';
import '../../services/api_key_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/date_time_field.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/app_select_field.dart';
import '../../widgets/app_popup.dart';
import '../../widgets/calendar_color_picker.dart';
import '../../widgets/delete_event_dialog.dart';
import '../settings_screen.dart';
import '../../providers/event_providers.dart';
import '../../services/debug_perf_logger.dart';

class EventCreationModal extends ConsumerStatefulWidget {
  final DateTime? startTime;
  final DateTime? endTime;
  final CalendarEvent? existingEvent;
  final VoidCallback onEventCreated;
  final bool renderAsBottomSheetContent;

  const EventCreationModal({
    super.key,
    this.startTime,
    this.endTime,
    this.existingEvent,
    required this.onEventCreated,
    this.renderAsBottomSheetContent = false,
  });

  @override
  ConsumerState<EventCreationModal> createState() => _EventCreationModalState();
}

class _EventCreationModalState extends ConsumerState<EventCreationModal> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _titleFocusNode = FocusNode();
  late DateTime _startTime;
  late DateTime _endTime;
  String? _selectedCalendarId;
  List<Map<String, dynamic>> _availableCalendars = [];
  bool _userHasSelectedCalendar = false;

  bool _titleAILoading = false;
  bool _descriptionAILoading = false;
  bool _deleting = false;
  bool _saving = false;
  bool _creatingCalendar = false;
  bool _showTitleError = false;
  bool _showCalendarError = false;
  Timer? _requiredFieldErrorTimer;
  String? _originalUserTitle;
  final GroqService _groqService = GroqService();
  final ApiKeyStorageService _apiKeyStorage = ApiKeyStorageService();
  late final _EventFormSnapshot _initialSnapshot;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEvent;
    _startTime = existing?.startDateTime ?? widget.startTime ?? DateTime.now();
    _endTime =
        existing?.endDateTime ??
        widget.endTime ??
        _startTime.add(const Duration(hours: 1));
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description;
      _selectedCalendarId = existing.calendarId;
    }
    _initialSnapshot = _buildSnapshot();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _fetchCalendars();
      if (widget.existingEvent == null) {
        await _loadDefaultCalendar();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocusNode.dispose();
    _requiredFieldErrorTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchCalendars() async {
    String? defaultCalendarId;
    try {
      defaultCalendarId = await GoogleCalendarService.instance.storage
          .getDefaultCalendarId();
    } catch (_) {}

    void applyCalendars(List<Map<String, dynamic>> calendars) {
      final filteredCalendars = calendars.where((cal) {
        final name = (cal['name'] as String?) ?? '';
        return name.isNotEmpty && name.toLowerCase() != 'calendar';
      }).toList();

      if (mounted) {
        setState(() {
          _availableCalendars = _mergeCalendars(
            _availableCalendars,
            filteredCalendars,
          );
          if (widget.existingEvent != null) {
            return;
          }
          if (_userHasSelectedCalendar) {
            return;
          }

          final defaultExists =
              defaultCalendarId != null &&
              defaultCalendarId.isNotEmpty &&
              _availableCalendars.any(
                (cal) => (cal['id'] as String?) == defaultCalendarId,
              );

          if (defaultExists) {
            _selectedCalendarId = defaultCalendarId;
            return;
          }

          final currentExists =
              _selectedCalendarId != null &&
              _availableCalendars.any(
                (cal) => (cal['id'] as String?) == _selectedCalendarId,
              );
          if (!currentExists) {
            _selectedCalendarId = null;
          }
        });
      }
    }

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
                'name': 'Default Calendar',
                'color': 0xFF039BE5,
              },
            ];
            if (widget.existingEvent == null && !_userHasSelectedCalendar) {
              _selectedCalendarId = 'primary';
            }
          }
        });
      }
    }
  }

  List<Map<String, dynamic>> _mergeCalendars(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> incoming,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final calendar in current) {
      final id = calendar['id'] as String?;
      if (id != null && id.isNotEmpty) byId[id] = calendar;
    }
    for (final calendar in incoming) {
      final id = calendar['id'] as String?;
      if (id != null && id.isNotEmpty) byId[id] = calendar;
    }
    return byId.values.toList();
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
    showAppDialog(
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

  void _flashRequiredFieldErrors({bool title = false, bool calendar = false}) {
    _requiredFieldErrorTimer?.cancel();
    setState(() {
      _showTitleError = _showTitleError || title;
      _showCalendarError = _showCalendarError || calendar;
    });
    _requiredFieldErrorTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showTitleError = false;
          _showCalendarError = false;
        });
      }
    });
  }

  Future<void> _createCalendar() async {
    final draft = await showAppDialog<_CalendarDraft>(
      context: context,
      // The parent event popup becomes transparent while this is shown.
      barrierColor: Colors.transparent,
      builder: (context) => const _CreateCalendarDialog(),
    );
    if (draft == null || _creatingCalendar) return;

    final temporaryId =
        'pending-calendar-${DateTime.now().microsecondsSinceEpoch}';
    final optimisticCalendar = <String, dynamic>{
      'id': temporaryId,
      'name': draft.name,
      'color': draft.color.toARGB32(),
    };
    setState(() {
      _creatingCalendar = true;
      _availableCalendars = [..._availableCalendars, optimisticCalendar];
      _selectedCalendarId = temporaryId;
      _userHasSelectedCalendar = true;
    });
    try {
      final calendar = await GoogleCalendarService.instance.createCalendar(
        name: draft.name,
        color: draft.color.toARGB32(),
      );
      final calendarId = calendar['id'] as String?;
      if (calendarId == null || calendarId.isEmpty) {
        throw StateError('Created calendar is missing its ID');
      }
      if (!mounted) return;
      setState(() {
        _availableCalendars = [
          ..._availableCalendars.where((item) => item['id'] != temporaryId),
          calendar,
        ];
        _selectedCalendarId = calendarId;
        _userHasSelectedCalendar = true;
      });
      showAppSnackBar(
        context,
        'Calendar "${draft.name}" was created in Google Calendar.',
        type: AppSnackBarType.success,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _availableCalendars = _availableCalendars
              .where((item) => item['id'] != temporaryId)
              .toList();
          _selectedCalendarId = widget.existingEvent?.calendarId;
        });
        showAppSnackBar(
          context,
          'Could not create Google Calendar: $error',
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _creatingCalendar = false);
    }
  }

  Future<bool> _deleteCalendar(String calendarId) async {
    if (calendarId == 'primary') {
      showAppSnackBar(
        context,
        'Default Calendar cannot be deleted.',
        type: AppSnackBarType.error,
      );
      return false;
    }
    try {
      await GoogleCalendarService.instance.deleteCalendar(calendarId);
      if (!mounted) return false;
      setState(() {
        _availableCalendars = _availableCalendars
            .where((calendar) => calendar['id'] != calendarId)
            .toList();
        if (_selectedCalendarId == calendarId) {
          _selectedCalendarId =
              _availableCalendars.firstOrNull?['id'] as String?;
        }
      });
      return true;
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Could not delete calendar: $error',
          type: AppSnackBarType.error,
        );
      }
      return false;
    }
  }

  void _showAISetupPopup() {
    showAppDialog(
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
      _flashRequiredFieldErrors(title: true);
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
      _flashRequiredFieldErrors(title: true);
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
    if (!mounted) return;

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
        _startTime = combined;
        if (!_endTime.isAfter(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      } else {
        _endTime = combined;
        if (!_endTime.isAfter(_startTime)) {
          _startTime = _endTime.subtract(const Duration(hours: 1));
        }
      }
    });
  }

  Future<void> _saveEvent() async {
    if (_saving) return;
    final existing = widget.existingEvent;
    if (existing != null && !_hasChanges()) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }
    final titleMissing = _titleController.text.trim().isEmpty;
    final calendarMissing =
        _selectedCalendarId == null || _selectedCalendarId!.isEmpty;
    if (titleMissing || calendarMissing) {
      _flashRequiredFieldErrors(title: titleMissing, calendar: calendarMissing);
      return;
    }
    if (!_endTime.isAfter(_startTime)) {
      _showErrorDialog('End time must be after start time.');
      return;
    }

    setState(() {
      _saving = true;
    });
    final watch = DebugPerfLogger.start('EventCreationModal', 'saveEvent');
    try {
      final calendarId = _selectedCalendarId ?? 'primary';
      final selected = _availableCalendars
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['id'] == calendarId, orElse: () => {});
      final colorValue = selected['color'] as int?;
      if (existing != null) {
        final updatedEvent = existing.copyWith(
          calendarId: calendarId,
          title: _titleController.text.trim(),
          startDateTime: _startTime,
          endDateTime: _endTime,
          allDay: false,
          color: Color(colorValue ?? AppColors.primary.toARGB32()),
          description: _descriptionController.text.trim(),
          timezone: DateTime.now().timeZoneName,
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
          color: Color(colorValue ?? AppColors.primary.toARGB32()),
          description: _descriptionController.text.trim(),
          location: '',
          timezone: DateTime.now().timeZoneName,
        );
        await ref.read(eventRepositoryProvider).createEvent(event);
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onEventCreated();
      }
      DebugPerfLogger.end(
        'EventCreationModal',
        watch,
        'saveEvent',
        data: {
          'mode': existing != null ? 'update' : 'create',
          'calendarId': calendarId,
        },
      );
    } catch (e) {
      DebugPerfLogger.error('EventCreationModal', 'saveEvent', error: e);
      if (mounted) {
        showAppSnackBar(
          context,
          'Error saving event: $e',
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deleteEvent() async {
    final existing = widget.existingEvent;
    if (existing == null || _deleting) return;

    final confirm = await showDeleteEventDialog(context);
    if (!confirm) return;

    setState(() {
      _deleting = true;
    });
    final watch = DebugPerfLogger.start('EventCreationModal', 'deleteEvent');

    try {
      await ref.read(eventRepositoryProvider).deleteEvent(existing.id);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onEventCreated();
      DebugPerfLogger.end(
        'EventCreationModal',
        watch,
        'deleteEvent',
        data: {'id': existing.id},
      );
    } catch (e) {
      DebugPerfLogger.error(
        'EventCreationModal',
        'deleteEvent',
        error: e,
        data: {'id': existing.id},
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Error deleting event: $e',
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  _EventFormSnapshot _buildSnapshot() {
    return _EventFormSnapshot(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      startTime: _startTime,
      endTime: _endTime,
      calendarId: _selectedCalendarId ?? '',
    );
  }

  bool _hasChanges() => _buildSnapshot() != _initialSnapshot;

  Widget _buildFormContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: 15),
                  Text(
                    widget.existingEvent == null
                        ? 'Create Event'
                        : 'Edit Event',
                    style: AppTextStyles.headline2,
                  ),
                ],
              ),
            ),
            if (widget.existingEvent != null)
              IconButton(
                onPressed: _deleting ? null : _deleteEvent,
                iconSize: 22,
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.error,
                  disabledForegroundColor: AppColors.error.withValues(
                    alpha: 0.45,
                  ),
                  minimumSize: const Size(44, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const HugeIcon(
                        icon: HugeIcons.strokeRoundedDelete03,
                        size: 20,
                        strokeWidth: 2.2,
                      ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        LargeTextField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          autofocus: false,
          hint: 'Event title',
          label: 'Title',
          minLines: 1,
          maxLines: 3,
          requiredField: true,
          hasError: _showTitleError,
          onChanged: (_) {
            if (_showTitleError) setState(() => _showTitleError = false);
          },
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
        AppSelectField<String>(
          label: 'Select calendar',
          value: _selectedCalendarId,
          hint: _availableCalendars.isEmpty
              ? 'Loading calendars...'
              : 'Select calendar',
          options: [
            ..._availableCalendars.map(
              (calendar) => AppSelectOption(
                value: calendar['id'] as String,
                label: calendar['name'] as String? ?? '',
                color: calendar['color'] is int
                    ? Color(calendar['color'] as int)
                    : null,
              ),
            ),
          ],
          onAddPressed: _creatingCalendar ? null : _createCalendar,
          showAddInField: false,
          onDelete: _deleteCalendar,
          hasError: _showCalendarError,
          onColorChanged: _changeCalendarColor,
          onNameChanged: _changeCalendarName,

          onChanged: (value) {
            setState(() {
              _selectedCalendarId = value;
              _userHasSelectedCalendar = true;
              _showCalendarError = false;
            });
          },
        ),
        const SizedBox(height: 12),
        ExpandableDescription(
          controller: _descriptionController,
          hint: 'Description ( Optional )',
          minLines: 1,
          maxLines: 5,
          onAIClick: _optimizeOrGenerateDescription,
          aiLoading: _descriptionAILoading,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: PrimaryActionButton(
                onPressed: _saving || _creatingCalendar ? null : _saveEvent,
                minimumSize: const Size.fromHeight(44),
                label: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<Color?> _changeCalendarColor(String calendarId, Color color) async {
    try {
      await GoogleCalendarService.instance.updateCalendarColor(
        calendarId: calendarId,
        color: color.toARGB32(),
      );
      if (!mounted) return null;
      setState(() {
        _availableCalendars = _availableCalendars
            .map(
              (calendar) => calendar['id'] == calendarId
                  ? {...calendar, 'color': color.toARGB32()}
                  : calendar,
            )
            .toList();
      });
      return color;
    } catch (error) {
      if (mounted) _showErrorDialog('Could not update calendar color: $error');
      return null;
    }
  }

  Future<void> _changeCalendarName(String calendarId, String name) async {
    await GoogleCalendarService.instance.updateCalendarName(
      calendarId: calendarId,
      name: name,
    );
    if (!mounted) return;
    setState(() {
      _availableCalendars = _availableCalendars
          .map(
            (calendar) => calendar['id'] == calendarId
                ? {...calendar, 'name': name}
                : calendar,
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < 700;

    Widget mobilePanel({required bool includeHandle}) {
      final keyboardInset = media.viewInsets.bottom;
      final maxHeight = media.size.height * 0.94;
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Material(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: media.size.width,
                maxWidth: media.size.width,
                maxHeight: maxHeight,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (includeHandle) ...[
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.onSurface.withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildFormContent(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final popup = widget.renderAsBottomSheetContent
        ? mobilePanel(includeHandle: true)
        : isMobile
        ? Align(
            alignment: Alignment.bottomCenter,
            child: mobilePanel(includeHandle: true),
          )
        : Dialog(
            backgroundColor: AppColors.surface,
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(24),
              child: _buildFormContent(context),
            ),
          );

    return popup;
  }
}

class _CalendarDraft {
  const _CalendarDraft({required this.name, required this.color});

  final String name;
  final Color color;
}

class _CreateCalendarDialog extends StatefulWidget {
  const _CreateCalendarDialog();

  @override
  State<_CreateCalendarDialog> createState() => _CreateCalendarDialogState();
}

class _CreateCalendarDialogState extends State<_CreateCalendarDialog> {
  final _nameController = TextEditingController();
  Color _selectedColor = const Color(0xFF5D9ED5);
  Timer? _nameErrorTimer;
  bool _showNameError = false;

  @override
  void dispose() {
    _nameErrorTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyText1,
              decoration: InputDecoration(
                labelText: 'Calendar name',
                labelStyle: AppTextStyles.bodyText1.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.7),
                ),
                hintStyle: AppTextStyles.bodyText1.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: _nameBorder,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: _nameBorder,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: _nameBorder,
                ),
              ),
              onChanged: (_) {
                if (_showNameError) setState(() => _showNameError = false);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            CalendarColorPalette(
              selectedColor: _selectedColor,
              onChanged: (color) => setState(() => _selectedColor = color),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _nameErrorTimer?.cancel();
      setState(() => _showNameError = true);
      _nameErrorTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showNameError = false);
      });
      return;
    }
    Navigator.pop(context, _CalendarDraft(name: name, color: _selectedColor));
  }

  BorderSide get _nameBorder => _showNameError
      ? const BorderSide(color: Colors.red, width: 1)
      : const BorderSide(color: AppColors.borderColor);
}

class _EventFormSnapshot {
  const _EventFormSnapshot({
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.calendarId,
  });

  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String calendarId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _EventFormSnapshot &&
        other.title == title &&
        other.description == description &&
        other.startTime == startTime &&
        other.endTime == endTime &&
        other.calendarId == calendarId;
  }

  @override
  int get hashCode =>
      Object.hash(title, description, startTime, endTime, calendarId);
}
