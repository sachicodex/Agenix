import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/rounded_card.dart';
import '../widgets/form_fields.dart';
import '../widgets/date_time_field.dart';
import '../widgets/reminder_field.dart';
import '../services/google_calendar_service.dart';
import '../services/groq_service.dart';
import '../services/api_key_storage_service.dart';
import '../theme/app_colors.dart';
import 'settings_screen.dart';
import '../models/calendar_event.dart';
import '../providers/event_providers.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  static const routeName = '/create';
  final VoidCallback? onSignOut;

  const CreateEventScreen({super.key, this.onSignOut});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  Future<void> _refreshUserInfo() async {
    final acc = await GoogleCalendarService.instance.getAccountDetails();
    if (mounted) {
      final newEmail = acc['email'];
      final newPhotoUrl = acc['photoUrl'];
      if (_userEmail != newEmail || _userPhotoUrl != newPhotoUrl) {
        setState(() {
          _userEmail = newEmail;
          _userPhotoUrl = newPhotoUrl;
        });
      }
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

  Widget _buildErrorDialog(String title, String content) {
    return AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }

  final _titleController = TextEditingController();
  // Removed location field
  String? _selectedCalendarId;
  List<Map<String, dynamic>> _availableCalendars = [];
  bool _userHasSelectedCalendar =
      false; // Track if user manually selected a calendar

  Future<void> _fetchCalendars() async {
    void applyCalendars(List<Map<String, dynamic>> calendars) {
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
    }

    try {
      final cached = await GoogleCalendarService.instance.getCachedCalendars();
      if (cached.isNotEmpty) {
        applyCalendars(cached);
      }

      final calendars = await GoogleCalendarService.instance.getUserCalendars();
      applyCalendars(calendars);
    } catch (e) {
      // fallback to primary if error
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
            if (_selectedCalendarId == null) {
              _selectedCalendarId = 'primary';
            }
          }
        });
      }
    }
  }

  final _descController = TextEditingController();
  bool reminderOn = true;
  String reminderValue = ReminderOptions.values[0]; // '10 minutes'

  DateTime _startDateTime = DateTime.now();
  DateTime _endDateTime = DateTime.now().add(const Duration(hours: 1));

  void _goToFeedbackScreen(String state) {
    Navigator.pushNamed(context, '/sync', arguments: state);
  }

  bool _signedIn = false;
  String? _userEmail;
  String? _userPhotoUrl;
  bool _titleAILoading = false;
  bool _descriptionAILoading = false;
  String?
  _originalUserTitle; // Store original user input title before AI generation
  final GroqService _groqService = GroqService();
  final ApiKeyStorageService _apiKeyStorage = ApiKeyStorageService();
  late final FocusNode _keyboardFocusNode;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // User is already signed in (AuthWrapper handles routing)
      // Just load user info and calendars
      final signedIn = await GoogleCalendarService.instance.isSignedIn();
      if (mounted && _signedIn != signedIn) {
        setState(() => _signedIn = signedIn);
      }
      await _refreshUserInfo();
      if (signedIn) {
        await _fetchCalendars();
        // Load default calendar if set
        await _loadDefaultCalendar();
      } else if (mounted) {
        setState(() {
          _availableCalendars = [
            {'id': 'primary', 'name': 'Primary Calendar', 'color': 0xFF039BE5},
          ];
          _selectedCalendarId ??= 'primary';
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload default calendar when screen becomes visible again
    // This ensures changes from Settings are reflected immediately
    // Only reload if this route is currently active (user navigated back)
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && _signedIn) {
          await _loadDefaultCalendar();
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDefaultCalendar() async {
    try {
      final storage = GoogleCalendarService.instance.storage;
      final defaultCalendarId = await storage.getDefaultCalendarId();
      if (defaultCalendarId != null && defaultCalendarId.isNotEmpty) {
        // Check if the default calendar is in the available calendars list
        final calendarExists = _availableCalendars.any(
          (cal) => (cal['id'] as String?) == defaultCalendarId,
        );
        // Only set default calendar if user hasn't manually selected one
        // and the default calendar exists in the available calendars
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

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 720;
    // Memoize form widget to prevent unnecessary rebuilds
    final form = _buildForm(isWide);

    return Scaffold(
      appBar: _buildAppBar(),
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              _onSavePressed();
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.maybePop(context);
            }
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (isWide) {
              return Center(
                child: RoundedCard(
                  width: 720,
                  child: SingleChildScrollView(child: form),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(child: form),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LargeTextField(
          controller: _titleController,
          autofocus: false,
          hint: 'Event title',
          label: 'Title',
          requiredField: true,
          onAIClick: _optimizeTitle,
          aiLoading: _titleAILoading,
        ),
        const SizedBox(height: 12),
        if (isWide)
          Row(
            children: [
              Expanded(
                child: DateTimeField(
                  label: 'Start',
                  dateTime: _startDateTime,
                  onTap: () => _pickDateTime(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DateTimeField(
                  label: 'End',
                  dateTime: _endDateTime,
                  onTap: () => _pickDateTime(false),
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              DateTimeField(
                label: 'Start',
                dateTime: _startDateTime,
                onTap: () => _pickDateTime(true),
              ),
              const SizedBox(height: 16),
              DateTimeField(
                label: 'End',
                dateTime: _endDateTime,
                onTap: () => _pickDateTime(false),
              ),
            ],
          ),
        const SizedBox(height: 16),
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
                _userHasSelectedCalendar =
                    true; // Mark that user has selected a calendar
              });
            }
          },
        ),
        const SizedBox(height: 12),
        ExpandableDescription(
          controller: _descController,
          hint: 'Description ( Optional )',
          onAIClick: _optimizeOrGenerateDescription,
          aiLoading: _descriptionAILoading,
        ),
        const SizedBox(height: 12),
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
        ElevatedButton.icon(
          onPressed: _saving ? null : _onSavePressed,
          icon: const Icon(Icons.event_available),
          label: _saving ? const Text('Saving...') : const Text('Save'),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Text('Create Event', style: AppTextStyles.headline2),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.calendar_month),
          tooltip: 'View Calendar',
          onPressed: () {
            Navigator.pushNamed(context, '/calendar');
          },
        ),
        IconButton(
          icon: _userPhotoUrl != null
              ? CircleAvatar(
                  backgroundImage: NetworkImage(
                    _userPhotoUrl!,
                    headers: const {'Cache-Control': 'max-age=3600'},
                  ),
                  radius: 16,
                )
              : const Icon(Icons.account_circle, size: 32),

          onPressed: () {
            Navigator.pushNamed(context, SettingsScreen.routeName);
          },
        ),
        const SizedBox(width: 10),
      ],
    );
  }

  /// Show AI setup popup when API key is not configured
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

  /// Optimize title using AI
  Future<void> _optimizeTitle() async {
    // Check if API key is configured
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

    // Store original user input title before AI generation
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

  /// Optimize or generate description using AI
  Future<void> _optimizeOrGenerateDescription() async {
    // Check if API key is configured
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

    // Store original user input title if not already stored
    if (_originalUserTitle == null || _originalUserTitle!.isEmpty) {
      _originalUserTitle = currentTitle;
    }

    setState(() {
      _descriptionAILoading = true;
    });

    try {
      final currentDescription = _descController.text.trim();
      String result;

      // Get the original user title (if available) and current AI-generated title
      final originalTitle = _originalUserTitle ?? currentTitle;
      final aiGeneratedTitle = currentTitle;

      if (currentDescription.isEmpty) {
        // Generate description using both original user title and AI-generated title
        result = await _groqService.generateDescription(
          originalTitle,
          aiGeneratedTitle,
        );
      } else {
        // Optimize existing description using both titles
        result = await _groqService.optimizeDescription(
          originalTitle,
          aiGeneratedTitle,
          currentDescription,
        );
      }

      if (mounted) {
        _descController.text = result;
        _descController.selection = TextSelection.fromPosition(
          TextPosition(offset: result.length),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog(
          'Failed to ${_descController.text.trim().isEmpty ? "generate" : "optimize"} description: ${e.toString()}',
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

  bool _saving = false;

  Future<void> _onSavePressed() async {
    setState(() => _saving = true);
    try {
      // Validate required fields before any sync or sign-in
      if (_titleController.text.trim().isEmpty) {
        await showDialog(
          context: context,
          builder: (context) =>
              _buildErrorDialog('Error', 'Event title is required.'),
        );
        return;
      }
      if (_selectedCalendarId == null || _selectedCalendarId!.isEmpty) {
        await showDialog(
          context: context,
          builder: (context) => _buildErrorDialog(
            'Failed to save to Google Calendar',
            'Please choose a calendar.',
          ),
        );
        return;
      }

      if (!_endDateTime.isAfter(_startDateTime)) {
        await showDialog(
          context: context,
          builder: (context) =>
              _buildErrorDialog('Error', 'End time must be after start time.'),
        );
        return;
      }

      final calendarId = _selectedCalendarId ?? 'primary';
      final selected = _availableCalendars
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['id'] == calendarId, orElse: () => {});
      final colorValue = selected['color'] as int?;
      final minutes = reminderOn ? _parseReminderMinutes(reminderValue) : null;

      final event = CalendarEvent(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        calendarId: calendarId,
        title: _titleController.text.trim(),
        startDateTime: _startDateTime,
        endDateTime: _endDateTime,
        allDay: false,
        color: Color(colorValue ?? AppColors.primary.value),
        description: _descController.text.trim(),
        location: '',
        timezone: DateTime.now().timeZoneName,
        reminders: minutes == null ? const [] : [minutes],
      );

      await ref.read(eventRepositoryProvider).createEvent(event);
      await ref.read(syncServiceProvider).pushLocalChanges();
      _goToFeedbackScreen('success');

      if (mounted) {
        setState(() {
          _titleController.clear();
          _descController.clear();
          _originalUserTitle = null;
          _startDateTime = DateTime.now();
          _endDateTime = DateTime.now().add(const Duration(hours: 1));
          reminderOn = true;
          reminderValue = ReminderOptions.values[0];
          _userHasSelectedCalendar = false;
        });
        await _loadDefaultCalendar();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // _saveToGoogleCalendar is now inlined in _onSavePressed

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

  Future<void> _pickDateTime(bool isStart) async {
    DateTime initial = isStart ? _startDateTime : _endDateTime;

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) =>
          Theme(data: Theme.of(context), child: child!),
    );

    if (pickedDate == null) return;

    final TimeOfDay? pickedTime = await showTimePicker(
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

    if (isStart) {
      if (_startDateTime != combined) {
        setState(() => _startDateTime = combined);
      }
    } else {
      if (_endDateTime != combined) {
        setState(() => _endDateTime = combined);
      }
    }
  }
}
