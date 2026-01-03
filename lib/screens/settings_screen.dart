import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/api_key_storage_service.dart';
import '../services/google_calendar_service.dart';
import '../services/groq_service.dart';
import 'auth_wrapper.dart';

class SettingsScreen extends StatefulWidget {
  static const routeName = '/settings';
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
  List<Map<String, String>> _availableCalendars = [];
  String? _selectedCalendarId;
  String? _defaultCalendarName;
  bool _loadingCalendars = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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

    if (mounted) {
      setState(() => _isLoading = false);
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
        (cal) => cal['id'] == _selectedCalendarId,
        orElse: () => {'id': '', 'name': ''},
      );

      if (selectedCalendar['id']!.isEmpty) {
        _showErrorPopup('Invalid calendar selection');
        return;
      }

      final storage = GoogleCalendarService.instance.storage;
      await storage.saveDefaultCalendar(
        selectedCalendar['id']!,
        selectedCalendar['name'] ?? 'Unknown',
      );

      if (mounted) {
        setState(() {
          _defaultCalendarName = selectedCalendar['name'];
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

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 720;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Settings', style: AppTextStyles.headline2)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: AppTextStyles.headline2)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = ListView(
            padding: EdgeInsets.all(isWide ? 24 : 16),
            children: [
              // AI API Key Section
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
                              : IconButton(
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
              const SizedBox(height: 16),

              // Default Calendar Section
              if (_signedIn)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Default Calendar',
                          style: AppTextStyles.headline2.copyWith(fontSize: 18),
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
                                    value: cal['id'],
                                    child: Text(
                                      cal['name'] ?? '',
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
                        if (_defaultCalendarName != null && !_loadingCalendars)
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
              if (_signedIn) const SizedBox(height: 16),

              // Account Section
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
                          child: Icon(Icons.person, color: AppColors.onPrimary),
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
              const SizedBox(height: 16),

              // Logout Button
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
              const SizedBox(height: 16),

              // About Section
              Card(
                child: ListTile(
                  title: Text('About', style: AppTextStyles.bodyText1),
                  subtitle: Text(
                    'Agenix • v1.0.17.4',
                    style: AppTextStyles.bodyText1.copyWith(
                      color: AppColors.onSurface.withOpacity(0.6),
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
