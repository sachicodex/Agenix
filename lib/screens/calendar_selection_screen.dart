import 'package:flutter/material.dart';
import '../services/google_calendar_service.dart';
import '../theme/app_colors.dart';

/// Screen for selecting default calendar on first login
class CalendarSelectionScreen extends StatefulWidget {
  final VoidCallback? onCalendarSelected;
  final VoidCallback? onReAuthenticationNeeded;

  const CalendarSelectionScreen({
    super.key,
    this.onCalendarSelected,
    this.onReAuthenticationNeeded,
  });

  @override
  State<CalendarSelectionScreen> createState() =>
      _CalendarSelectionScreenState();
}

class _CalendarSelectionScreenState extends State<CalendarSelectionScreen> {
  List<Map<String, String>> _calendars = [];
  String? _selectedCalendarId;
  bool _loading = true;
  String? _error;
  bool _isPermissionError =
      false; // Track if error is due to missing permissions

  @override
  void initState() {
    super.initState();
    _loadCalendars();
  }

  Future<void> _loadCalendars() async {
    setState(() {
      _loading = true;
      _error = null;
      _isPermissionError = false;
    });

    try {
      final calendars = await GoogleCalendarService.instance.getUserCalendars();
      if (mounted) {
        // Filter out calendars with name "Calendar" (not a real calendar)
        final filteredCalendars = calendars.where((cal) {
          final name = cal['name'] ?? '';
          return name.isNotEmpty && name.toLowerCase() != 'calendar';
        }).toList();

        if (mounted) {
          setState(() {
            _calendars = filteredCalendars;
            if (_calendars.isNotEmpty && _selectedCalendarId == null) {
              _selectedCalendarId = _calendars.first['id'];
            }
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final errorString = e.toString().toLowerCase();
        final isPermissionError =
            errorString.contains('insufficient_scope') ||
            errorString.contains('access was denied') ||
            errorString.contains('permission denied');

        setState(() {
          _error = isPermissionError
              ? 'Calendar permissions not granted'
              : e.toString();
          _isPermissionError = isPermissionError;
          _loading = false;
        });
      }
    }
  }

  Future<void> _reAuthenticate() async {
    // Notify parent (AuthWrapper) that re-authentication is needed
    // This will sign out and show the sign-in screen
    widget.onReAuthenticationNeeded?.call();
  }

  Future<void> _saveAndContinue() async {
    if (_selectedCalendarId == null) {
      _showErrorDialog('Please select a calendar');
      return;
    }

    final selectedCalendar = _calendars.firstWhere(
      (cal) => cal['id'] == _selectedCalendarId,
      orElse: () => {'id': '', 'name': ''},
    );

    if (selectedCalendar['id']!.isEmpty) {
      _showErrorDialog('Invalid calendar selection');
      return;
    }

    try {
      // Save default calendar to storage
      final storage = GoogleCalendarService.instance.storage;
      await storage.saveDefaultCalendar(
        selectedCalendar['id']!,
        selectedCalendar['name'] ?? 'Unknown',
      );

      // Call callback to navigate to main app
      widget.onCalendarSelected?.call();
    } catch (e) {
      _showErrorDialog('Failed to save calendar selection: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // Remove back button
        title: Text('Select Default Calendar', style: AppTextStyles.headline2),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isPermissionError
                            ? Icons.lock_outline
                            : Icons.error_outline,
                        size: 64,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _isPermissionError
                            ? 'Calendar Access Required'
                            : 'Error loading calendars',
                        style: AppTextStyles.headline2,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isPermissionError
                            ? 'You need to grant calendar permissions to use this app.\n\n'
                                  'During sign-in, please make sure to check the box that allows '
                                  'access to your Google Calendar data.\n\n'
                                  'Click "Sign In Again" to restart the sign-in process and grant the required permissions.'
                            : _error!,
                        style: AppTextStyles.bodyText1,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      if (_isPermissionError)
                        ElevatedButton.icon(
                          onPressed: _reAuthenticate,
                          icon: const Icon(Icons.login),
                          label: Text(
                            'Sign In Again',
                            style: AppTextStyles.button,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                          ),
                        )
                      else
                        ElevatedButton(
                          onPressed: _loadCalendars,
                          child: Text('Retry', style: AppTextStyles.button),
                        ),
                    ],
                  ),
                ),
              )
            : _calendars.isEmpty
            ? Center(
                child: Text(
                  'No calendars found',
                  style: AppTextStyles.bodyText1,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose your default calendar for creating events:',
                    style: AppTextStyles.bodyText1,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _calendars.length,
                      itemBuilder: (context, index) {
                        final calendar = _calendars[index];
                        final isSelected =
                            calendar['id'] == _selectedCalendarId;
                        return Card(
                          color: isSelected
                              ? AppColors.primary.withOpacity(0.2)
                              : AppColors.surface,
                          child: ListTile(
                            title: Text(
                              calendar['name'] ?? 'Unknown',
                              style: AppTextStyles.bodyText1.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            leading: Radio<String>(
                              value: calendar['id'] ?? '',
                              groupValue: _selectedCalendarId,
                              onChanged: (value) {
                                if (value != null &&
                                    value != _selectedCalendarId) {
                                  setState(() {
                                    _selectedCalendarId = value;
                                  });
                                }
                              },
                            ),
                            onTap: () {
                              if (calendar['id'] != _selectedCalendarId) {
                                setState(() {
                                  _selectedCalendarId = calendar['id'];
                                });
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _saveAndContinue,
                    icon: const Icon(Icons.check),
                    label: Text('Continue', style: AppTextStyles.button),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
