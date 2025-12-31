import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:intl/intl.dart';
import '../widgets/rounded_card.dart';
import '../widgets/form_fields.dart';
import '../services/google_calendar_service.dart';
import '../services/gemini_service.dart';
import '../theme/app_colors.dart';
import 'sign_in_screen.dart';

class DateTimeField extends StatelessWidget {
  final String label;
  final DateTime dateTime;
  final VoidCallback onTap;

  const DateTimeField({
    super.key,
    required this.label,
    required this.dateTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTextStyles.bodyText1.copyWith(
            color: AppColors.onSurface.withOpacity(0.7),
          ),
        ),
        child: Text(
          DateFormat('EEE - h:mm a').format(dateTime.toLocal()),
          style: AppTextStyles.bodyText1,
        ),
      ),
    );
  }
}

class CreateEventScreenV2 extends StatefulWidget {
  static const routeName = '/create';
  final VoidCallback? onSignOut;

  const CreateEventScreenV2({super.key, this.onSignOut});

  @override
  State<CreateEventScreenV2> createState() => _CreateEventScreenV2State();
}

class _CreateEventScreenV2State extends State<CreateEventScreenV2> {
  Future<void> _refreshUserInfo() async {
    debugPrint('Calling _refreshUserInfo...');
    final acc = await GoogleCalendarService.instance.getAccountDetails();
    debugPrint(
      'getAccountDetails returned: email = \\${acc['email']}, photoUrl = \\${acc['photoUrl']}',
    );
    if (mounted) {
      setState(() {
        _userEmail = acc['email'];
        _userPhotoUrl = acc['photoUrl'];
        debugPrint('_userEmail set to: \\$_userEmail');
        debugPrint('_userPhotoUrl set to: \\$_userPhotoUrl');
      });
    } else {
      debugPrint('Widget not mounted, skipping setState');
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

  final _titleController = TextEditingController();
  // Removed location field
  String? _selectedCalendarId;
  List<Map<String, String>> _availableCalendars = [];

  Future<void> _fetchCalendars() async {
    try {
      final calendars = await GoogleCalendarService.instance.getUserCalendars();
      // Filter out calendars with name "Calendar" (this is the default primary calendar
      // that Google creates automatically, but it's confusing to show it as just "Calendar")
      final filteredCalendars = calendars.where((cal) {
        final name = cal['name'] ?? '';
        return name.isNotEmpty && name.toLowerCase() != 'calendar';
      }).toList();

      setState(() {
        _availableCalendars = filteredCalendars;
        if (_availableCalendars.isNotEmpty) {
          _selectedCalendarId ??= _availableCalendars.first['id'];
        }
      });
    } catch (e) {
      // fallback to primary if error
      setState(() {
        _availableCalendars = [
          {'id': 'primary', 'name': 'Primary Calendar'},
        ];
        _selectedCalendarId = 'primary';
      });
    }
  }

  final _descController = TextEditingController();
  bool reminderOn = true;
  String reminderValue = '10 minutes';

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
  final GeminiService _geminiService = GeminiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // User is already signed in (AuthWrapper handles routing)
      // Just load user info and calendars
      final signedIn = await GoogleCalendarService.instance.isSignedIn();
      if (mounted) setState(() => _signedIn = signedIn);
      await _refreshUserInfo();
      if (signedIn) {
        await _fetchCalendars();
        // Load default calendar if set
        await _loadDefaultCalendar();
      }
    });
  }

  Future<void> _loadDefaultCalendar() async {
    try {
      final storage = GoogleCalendarService.instance.storage;
      final defaultCalendarId = await storage.getDefaultCalendarId();
      if (defaultCalendarId != null && defaultCalendarId.isNotEmpty) {
        // Check if the default calendar is in the available calendars list
        final calendarExists = _availableCalendars.any(
          (cal) => cal['id'] == defaultCalendarId,
        );
        if (calendarExists && mounted) {
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

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LargeTextField(
          controller: _titleController,
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
        else ...[
          DateTimeField(
            label: 'Start',
            dateTime: _startDateTime,
            onTap: () => _pickDateTime(true),
          ),
          const SizedBox(height: 8),
          DateTimeField(
            label: 'End',
            dateTime: _endDateTime,
            onTap: () => _pickDateTime(false),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value:
              _selectedCalendarId ??
              (_availableCalendars.isNotEmpty
                  ? _availableCalendars.first['id']
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
          items: _availableCalendars
              .map(
                (cal) => DropdownMenuItem(
                  value: cal['id'],
                  child: Text(
                    cal['name'] ?? '',
                    style: AppTextStyles.bodyText1,
                  ),
                ),
              )
              .toList(),
          onChanged: (val) => setState(() => _selectedCalendarId = val),
        ),
        const SizedBox(height: 12),
        ExpandableDescription(
          controller: _descController,
          hint: 'Description ( Optional )',
          onAIClick: _optimizeOrGenerateDescription,
          aiLoading: _descriptionAILoading,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Switch(
                  value: reminderOn,
                  onChanged: (v) => setState(() => reminderOn = v),
                  activeColor: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text('Reminder', style: AppTextStyles.bodyText1),
              ],
            ),
            if (reminderOn)
              DropdownButton<String>(
                value: reminderValue,
                items: const ['10 minutes', '30 minutes', '1 hour', '1 day']
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e, style: AppTextStyles.bodyText1),
                      ),
                    )
                    .toList(),
                onChanged: (v) =>
                    setState(() => reminderValue = v ?? reminderValue),
                style: AppTextStyles.bodyText1,
                dropdownColor: AppColors.surface,
              ),
          ],
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _saving ? null : _onSavePressed,
          icon: const Icon(Icons.event_available),
          label: _saving
              ? const Text('Saving...')
              : const Text('Save to Google Calendar'),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Event'),
        actions: [
          IconButton(
            icon: _userPhotoUrl != null
                ? CircleAvatar(
                    backgroundImage: NetworkImage(_userPhotoUrl!),
                    radius: 16,
                  )
                : const Icon(Icons.account_circle, size: 32),
            tooltip: _signedIn
                ? (_userEmail ?? 'Google Account')
                : 'Not connected',
            onPressed: () async {
              await _refreshUserInfo();
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Google Account'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_signedIn && _userEmail != null)
                        Text(_userEmail!, style: AppTextStyles.bodyText1),
                      if (!_signedIn)
                        Text('Not connected', style: AppTextStyles.bodyText1),
                    ],
                  ),
                  actions: [
                    if (_signedIn)
                      TextButton(
                        onPressed: () async {
                          await GoogleCalendarService.instance.signOut();
                          if (mounted)
                            setState(() {
                              _signedIn = false;
                              _userEmail = null;
                              _userPhotoUrl = null;
                            });
                          Navigator.of(ctx).pop();
                          // Notify parent (AuthWrapper) that user signed out
                          widget.onSignOut?.call();
                        },
                        child: const Text('Sign out'),
                      )
                    else
                      TextButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          final res = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (c) => const SignInScreen(),
                            ),
                          );
                          final recheck = await GoogleCalendarService.instance
                              .isSignedIn();
                          if (mounted) setState(() => _signedIn = recheck);
                          await _refreshUserInfo();
                        },
                        child: const Text('Sign in'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: KeyboardListener(
        focusNode: FocusNode(),
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

  String _formatDateTime(DateTime dt) {
    try {
      return DateFormat('EEE, MMM d • h:mm a').format(dt.toLocal());
    } catch (_) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }

  /// Optimize title using AI
  Future<void> _optimizeTitle() async {
    final currentTitle = _titleController.text.trim();
    if (currentTitle.isEmpty) {
      _showErrorDialog('Please enter a title first');
      return;
    }

    setState(() {
      _titleAILoading = true;
    });

    try {
      final optimizedTitle = await _geminiService.optimizeTitle(currentTitle);
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
    final currentTitle = _titleController.text.trim();
    if (currentTitle.isEmpty) {
      _showErrorDialog('Please enter a title first');
      return;
    }

    setState(() {
      _descriptionAILoading = true;
    });

    try {
      final currentDescription = _descController.text.trim();
      String result;

      if (currentDescription.isEmpty) {
        // Generate description from title
        result = await _geminiService.generateDescription(currentTitle);
      } else {
        // Optimize existing description
        result = await _geminiService.optimizeDescription(
          currentTitle,
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
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Event title is required.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      if (_selectedCalendarId == null || _selectedCalendarId!.isEmpty) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Failed to save to Google Calendar'),
            content: const Text('Please choose a calendar.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      if (!_endDateTime.isAfter(_startDateTime)) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: const Text('End time must be after start time.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // Ensure signed in
      try {
        await GoogleCalendarService.instance.ensureSignedIn(context);
      } catch (_) {
        // Fallback: open explicit SignInScreen to let user retry and see errors
        final res = await Navigator.of(
          context,
        ).push<bool>(MaterialPageRoute(builder: (c) => const SignInScreen()));
        if (res != true) {
          // User cancelled sign-in
          return;
        }
      }

      // Try to save event to Google Calendar
      final title = _titleController.text;
      try {
        // Prepare reminders if enabled
        List<Map<String, dynamic>>? reminders;
        if (reminderOn) {
          int minutes = 10;
          if (reminderValue == '10 minutes')
            minutes = 10;
          else if (reminderValue == '30 minutes')
            minutes = 30;
          else if (reminderValue == '1 hour')
            minutes = 60;
          else if (reminderValue == '1 day')
            minutes = 24 * 60;
          reminders = [
            {'method': 'popup', 'minutes': minutes},
          ];
        }

        await GoogleCalendarService.instance.insertEvent(
          summary: title,
          description: _descController.text,
          start: _startDateTime,
          end: _endDateTime,
          calendarId: _selectedCalendarId ?? 'primary',
          reminders: reminders,
        );
        // Only on success, go to feedback screen
        _goToFeedbackScreen('success');
        // Clear form fields after sync completes
        if (mounted) {
          setState(() {
            _titleController.clear();
            _descController.clear();
            _startDateTime = DateTime.now();
            _endDateTime = DateTime.now().add(const Duration(hours: 1));
            reminderOn = true;
            reminderValue = '10 minutes';
          });
        }
      } catch (err) {
        // On error, show user-friendly error dialog only, do NOT go to feedback screen
        String errMsg = err.toString();
        String userMsg;
        if (errMsg.contains('writer access')) {
          userMsg = 'You need to have writer access to this calendar.';
        } else {
          userMsg =
              'Failed to save to Google Calendar. Please try again or check your permissions.';
        }
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Failed to save to Google Calendar'),
            content: Text(userMsg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        // Do NOT clear form fields or go to feedback screen
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // _saveToGoogleCalendar is now inlined in _onSavePressed

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

    setState(() {
      if (isStart) {
        _startDateTime = combined;
      } else {
        _endDateTime = combined;
      }
    });
  }
}
