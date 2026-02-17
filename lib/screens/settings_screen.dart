import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../services/api_key_storage_service.dart';
import '../services/google_calendar_service.dart';
import '../services/groq_service.dart';
import '../notifications/notification_models.dart';
import '../notifications/notification_settings_repository.dart';
import '../providers/notification_providers.dart';
import 'auth_wrapper.dart';
import '../widgets/app_animations.dart';
import '../widgets/modern_splash_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  static const routeName = '/settings';
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _apiKeyStorageService = ApiKeyStorageService();
  bool _isLoading = true;
  bool _isSavingApiKey = false;
  bool _apiKeyValid = false;
  String? _userEmail;
  String? _userPhotoUrl;
  bool _signedIn = false;
  String?
  _previousApiKey; // Store previous key to restore on validation failure
  List<Map<String, dynamic>> _availableCalendars = [];
  String? _selectedCalendarId;
  String? _defaultCalendarName;
  bool _loadingCalendars = false;
  late final NotificationSettingsRepository _notificationSettingsRepository;
  bool _dailyAgendaEnabled = true;
  bool _eventRemindersEnabled = true;
  int _defaultReminderMinutes = 15;
  bool _isSavingNotificationSettings = false;
  bool _isSendingTestNotification = false;
  bool _windowsHasPackageIdentity = true;

  @override
  void initState() {
    super.initState();
    _windowsHasPackageIdentity = _detectWindowsPackageIdentity();
    _notificationSettingsRepository = ref.read(
      notificationSettingsRepositoryProvider,
    );
    _loadSettings();
  }

  bool _detectWindowsPackageIdentity() {
    if (!Platform.isWindows) {
      return true;
    }
    try {
      return MsixUtils.hasPackageIdentity();
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    // Load API key
    final apiKey = await _apiKeyStorageService.getApiKey();
    if (apiKey != null) {
      _apiKeyController.text = apiKey;
      _previousApiKey = apiKey; // Store for restoration
      // Validate existing API key
      final isValid = await _validateApiKey(apiKey);
      if (mounted) {
        setState(() {
          _apiKeyValid = isValid;
        });
      }
    }

    // Load user info
    final signedIn = await GoogleCalendarService.instance.isSignedIn();
    if (signedIn) {
      final acc = await GoogleCalendarService.instance.getAccountDetails();
      if (mounted) {
        setState(() {
          _signedIn = true;
          _userEmail = acc['email'];
          _userPhotoUrl = acc['photoUrl'];
        });
      }

      // Load default calendar
      await _loadDefaultCalendar();
      // Load available calendars
      await _loadCalendars();
    }

    await _loadNotificationSettings();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final settings = await _notificationSettingsRepository.getSettings();
      if (!mounted) {
        return;
      }
      setState(() {
        _dailyAgendaEnabled = settings.dailyAgendaEnabled;
        _eventRemindersEnabled = settings.eventRemindersEnabled;
        _defaultReminderMinutes = settings.defaultReminderMinutes;
      });
    } catch (e) {
      debugPrint('Error loading notification settings: $e');
    }
  }

  Future<void> _saveNotificationSettings() async {
    setState(() => _isSavingNotificationSettings = true);
    try {
      await _notificationSettingsRepository.saveSettings(
        NotificationUserSettings(
          defaultReminderMinutes: _defaultReminderMinutes,
          dailyAgendaEnabled: _dailyAgendaEnabled,
          eventRemindersEnabled: _eventRemindersEnabled,
        ),
      );
    } catch (e) {
      if (mounted) {
        _showErrorPopup(
          'Failed to save notification settings: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingNotificationSettings = false);
      }
    }
  }

  Future<void> _sendTestNotification() async {
    setState(() => _isSendingTestNotification = true);
    try {
      await ref.read(notificationServiceProvider).scheduleTestNotification();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Test notification scheduled for ~10 seconds from now.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showErrorPopup('Failed to schedule test notification: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSendingTestNotification = false);
      }
    }
  }

  Future<void> _saveApiKey() async {
    final apiKey = _apiKeyController.text.trim();

    // Allow removing API key if field is empty
    if (apiKey.isEmpty) {
      // Only show confirmation popup if there was an API key before
      if (_previousApiKey != null && _previousApiKey!.isNotEmpty) {
        // Show confirmation popup before removing
        final shouldRemove = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove API Key'),
            content: const Text(
              'Are you sure you want to remove your API key? AI features will be disabled until you add a new API key.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );

        if (shouldRemove != true) return;
      } else {
        // No API key existed before, just return without doing anything
        return;
      }

      setState(() => _isSavingApiKey = true);
      try {
        await _apiKeyStorageService.clearApiKey();
        if (mounted) {
          setState(() {
            _apiKeyValid = false;
            _isSavingApiKey = false;
          });
          // Hide keyboard
          FocusScope.of(context).unfocus();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSavingApiKey = false);
          _showErrorPopup('Failed to remove API key: ${e.toString()}');
        }
      }
      return;
    }

    setState(() => _isSavingApiKey = true);

    // Store current key before testing new one
    final oldApiKey = _previousApiKey;
    _previousApiKey = apiKey;

    try {
      // Temporarily save the new API key to test it
      await _apiKeyStorageService.saveApiKey(apiKey);

      // Test the API key by making a simple request
      final isValid = await _validateApiKey(apiKey);

      if (isValid) {
        // API key is valid - already saved, just update UI
        if (mounted) {
          setState(() {
            _apiKeyValid = true;
            _isSavingApiKey = false;
          });
          // Hide keyboard
          FocusScope.of(context).unfocus();
        }
      } else {
        // Invalid API key - restore old key and show popup
        if (oldApiKey != null && oldApiKey.isNotEmpty) {
          await _apiKeyStorageService.saveApiKey(oldApiKey);
          _previousApiKey = oldApiKey;
        } else {
          await _apiKeyStorageService.clearApiKey();
          _previousApiKey = null;
        }

        if (mounted) {
          setState(() {
            _apiKeyValid = false;
            _isSavingApiKey = false;
          });
          _showErrorPopup(
            'Invalid API key. Please check your API key and try again.',
          );
        }
      }
    } catch (e) {
      // Restore old key on error
      if (oldApiKey != null && oldApiKey.isNotEmpty) {
        await _apiKeyStorageService.saveApiKey(oldApiKey);
        _previousApiKey = oldApiKey;
      } else {
        await _apiKeyStorageService.clearApiKey();
        _previousApiKey = null;
      }

      if (mounted) {
        setState(() {
          _apiKeyValid = false;
          _isSavingApiKey = false;
        });
        _showErrorPopup('Failed to validate API key: ${e.toString()}');
      }
    }
  }

  Future<bool> _validateApiKey(String apiKey) async {
    try {
      // Create a GroqService instance to test the key
      final groqService = GroqService();

      // Try a simple test request with a minimal prompt
      await groqService.optimizeTitle('test');
      return true;
    } catch (e) {
      // Check if it's an authentication error
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('unauthorized') ||
          errorMsg.contains('invalid') ||
          errorMsg.contains('api key') ||
          errorMsg.contains('401') ||
          errorMsg.contains('403') ||
          errorMsg.contains('authentication')) {
        return false;
      }
      // For other errors (network, etc.), assume key might be valid
      // but we'll save it anyway and let user test it
      return true;
    }
  }

  Future<void> _loadDefaultCalendar() async {
    try {
      final storage = GoogleCalendarService.instance.storage;
      final calendarId = await storage.getDefaultCalendarId();
      final calendarName = await storage.getDefaultCalendarName();
      if (mounted) {
        setState(() {
          _selectedCalendarId = calendarId;
          _defaultCalendarName = calendarName;
        });
      }
    } catch (e) {
      debugPrint('Error loading default calendar: $e');
    }
  }

  Future<void> _loadCalendars() async {
    if (!_signedIn) return;

    setState(() => _loadingCalendars = true);

    try {
      final cached = await GoogleCalendarService.instance.getCachedCalendars();
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _availableCalendars = cached;
          if (_selectedCalendarId == null && cached.isNotEmpty) {
            _selectedCalendarId = cached.first['id'] as String?;
          }
          _loadingCalendars = false;
        });
      }

      final calendars = await GoogleCalendarService.instance.getUserCalendars();
      if (mounted) {
        setState(() {
          _availableCalendars = calendars;
          // If no calendar is selected, select the first one
          if (_selectedCalendarId == null && calendars.isNotEmpty) {
            _selectedCalendarId = calendars.first['id'];
          }
          _loadingCalendars = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCalendars = false);
        _showErrorPopup('Failed to load calendars: ${e.toString()}');
      }
    }
  }

  Future<void> _saveDefaultCalendar() async {
    if (_selectedCalendarId == null || _selectedCalendarId!.isEmpty) {
      _showErrorPopup('Please select a calendar');
      return;
    }

    try {
      final selectedCalendar = _availableCalendars.firstWhere(
        (cal) => (cal['id'] as String?) == _selectedCalendarId,
        orElse: () => {'id': '', 'name': '', 'color': 0xFF039BE5},
      );

      if ((selectedCalendar['id'] as String?)?.isEmpty ?? true) {
        _showErrorPopup('Invalid calendar selection');
        return;
      }

      final storage = GoogleCalendarService.instance.storage;
      await storage.saveDefaultCalendar(
        selectedCalendar['id'] as String,
        (selectedCalendar['name'] as String?) ?? 'Unknown',
      );

      if (mounted) {
        setState(() {
          _defaultCalendarName = selectedCalendar['name'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorPopup('Failed to save calendar selection: ${e.toString()}');
      }
    }
  }

  void _showErrorPopup(String message) {
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

  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    // Clear authentication data
    await GoogleCalendarService.instance.signOut();

    // Navigate back to AuthWrapper (which will check auth and show login screen)
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
        (route) => false,
      );
    }
  }

  Widget _animatedSection(int index, Widget child) {
    return AppFadeSlideIn(
      delay: Duration(milliseconds: 50 * index),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 720;

    if (_isLoading) {
      return const Scaffold(
        body: ModernSplashScreen(
          embedded: true,
          animateIntro: false,
          showLoading: true,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: AppPressFeedback(
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '',
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            splashRadius: 14,
            visualDensity: VisualDensity.compact,
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              splashFactory: NoSplash.splashFactory,
              overlayColor: MaterialStateProperty.all(Colors.transparent),
              backgroundColor: MaterialStateProperty.all(Colors.transparent),
            ),
            onPressed: () {
              Navigator.maybePop(context);
            },
          ),
        ),
        title: Text('Settings', style: AppTextStyles.headline2),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = ListView(
            padding: EdgeInsets.all(isWide ? 24 : 16),
            children: [
              // AI API Key Section
              _animatedSection(
                0,
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI API Key',
                          style: AppTextStyles.headline2.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter your AI API key to enable AI features',
                          style: AppTextStyles.bodyText1.copyWith(
                            color: AppColors.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _apiKeyController,
                          decoration: InputDecoration(
                            hintText: 'Enter your AI API key',
                            hintStyle: AppTextStyles.bodyText1.copyWith(
                              color: AppColors.onSurface.withOpacity(0.5),
                            ),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: _isSavingApiKey
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : AppPressFeedback(
                                    child: IconButton(
                                      icon: Icon(
                                        _apiKeyValid
                                            ? Icons.check_circle
                                            : Icons.check_circle_outline,
                                      ),
                                      color: _apiKeyValid
                                          ? Colors.green
                                          : AppColors.primary,
                                      onPressed: _saveApiKey,
                                    ),
                                  ),
                          ),
                          style: AppTextStyles.bodyText1,
                          obscureText: true,
                          enabled: !_isSavingApiKey,
                          onChanged: (value) {
                            // Reset validation state when user types
                            if (_apiKeyValid) {
                              setState(() {
                                _apiKeyValid = false;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Default Calendar Section
              if (_signedIn)
                _animatedSection(
                  1,
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Default Calendar',
                            style: AppTextStyles.headline2.copyWith(
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose your default calendar for creating events',
                            style: AppTextStyles.bodyText1.copyWith(
                              color: AppColors.onSurface.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_loadingCalendars)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else if (_availableCalendars.isEmpty)
                            Text(
                              'No calendars available',
                              style: AppTextStyles.bodyText1.copyWith(
                                color: AppColors.onSurface.withOpacity(0.6),
                              ),
                            )
                          else
                            DropdownButtonFormField<String>(
                              value: _selectedCalendarId,
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
                                    (cal) => DropdownMenuItem(
                                      value: cal['id'] as String?,
                                      child: Text(
                                        (cal['name'] as String?) ?? '',
                                        style: AppTextStyles.bodyText1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null &&
                                    value != _selectedCalendarId) {
                                  setState(() {
                                    _selectedCalendarId = value;
                                  });
                                  _saveDefaultCalendar();
                                }
                              },
                            ),
                          if (_defaultCalendarName != null &&
                              !_loadingCalendars)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Current: $_defaultCalendarName',
                                style: AppTextStyles.bodyText1.copyWith(
                                  color: AppColors.onSurface.withOpacity(0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_signedIn) const SizedBox(height: 16),

              _animatedSection(
                2,
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: AppTextStyles.headline2.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Daily agenda (6:00 AM)',
                            style: AppTextStyles.bodyText1,
                          ),
                          value: _dailyAgendaEnabled,
                          onChanged: _isSavingNotificationSettings
                              ? null
                              : (value) {
                                  setState(() {
                                    _dailyAgendaEnabled = value;
                                  });
                                  _saveNotificationSettings();
                                },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Event reminders',
                            style: AppTextStyles.bodyText1,
                          ),
                          value: _eventRemindersEnabled,
                          onChanged: _isSavingNotificationSettings
                              ? null
                              : (value) {
                                  setState(() {
                                    _eventRemindersEnabled = value;
                                  });
                                  _saveNotificationSettings();
                                },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          value: _defaultReminderMinutes,
                          decoration: InputDecoration(
                            labelText: 'Default reminder',
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
                          items: const [
                            DropdownMenuItem(
                              value: 5,
                              child: Text('5 minutes'),
                            ),
                            DropdownMenuItem(
                              value: 10,
                              child: Text('10 minutes'),
                            ),
                            DropdownMenuItem(
                              value: 15,
                              child: Text('15 minutes'),
                            ),
                            DropdownMenuItem(
                              value: 30,
                              child: Text('30 minutes'),
                            ),
                            DropdownMenuItem(value: 60, child: Text('1 hour')),
                          ],
                          onChanged: _isSavingNotificationSettings
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    _defaultReminderMinutes = value;
                                  });
                                  _saveNotificationSettings();
                                },
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSendingTestNotification
                                ? null
                                : _sendTestNotification,
                            icon: _isSendingTestNotification
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.notifications_active),
                            label: Text(
                              _isSendingTestNotification
                                  ? 'Scheduling...'
                                  : 'Send test notification (10s)',
                            ),
                          ),
                        ),
                        if (!_windowsHasPackageIdentity)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              'Windows background notifications while app is closed require MSIX install.',
                              style: AppTextStyles.bodyText1.copyWith(
                                color: AppColors.onSurface.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Account Section
              _animatedSection(
                3,
                Card(
                  child: ListTile(
                    leading: _userPhotoUrl != null
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(
                              _userPhotoUrl!,
                              headers: const {'Cache-Control': 'max-age=3600'},
                            ),
                          )
                        : CircleAvatar(
                            child: Icon(
                              Icons.person,
                              color: AppColors.onPrimary,
                            ),
                            backgroundColor: AppColors.primary,
                          ),
                    title: Text(
                      _signedIn ? 'Google Account' : 'Not connected',
                      style: AppTextStyles.bodyText1,
                    ),
                    subtitle: _signedIn && _userEmail != null
                        ? Text(
                            _userEmail!,
                            style: AppTextStyles.bodyText1.copyWith(
                              color: AppColors.onSurface.withOpacity(0.6),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Logout Button
              _animatedSection(
                4,
                Card(
                  child: ListTile(
                    leading: Icon(Icons.logout, color: AppColors.error),
                    title: Text(
                      'Logout',
                      style: AppTextStyles.bodyText1.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                    onTap: _signedIn ? _handleLogout : null,
                    enabled: _signedIn,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // About Section
              _animatedSection(
                5,
                Card(
                  child: ListTile(
                    title: Text('About', style: AppTextStyles.bodyText1),
                    subtitle: Text(
                      'Agenix • v1.0.17.5',
                      style: AppTextStyles.bodyText1.copyWith(
                        color: AppColors.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );

          if (isWide) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: content,
              ),
            );
          }

          return content;
        },
      ),
    );
  }
}
