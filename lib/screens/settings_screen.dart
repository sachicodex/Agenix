import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import '../theme/app_colors.dart';
import '../services/api_key_storage_service.dart';
import '../services/google_calendar_service.dart';
import '../services/groq_service.dart';
import '../services/settings_sync_service.dart';
import '../services/settings_encryption_service.dart';
import '../services/settings_sync_state_store.dart';
import '../services/windows_startup_service.dart';
import 'auth_wrapper.dart';
import '../widgets/app_animations.dart';
import '../widgets/modern_splash_screen.dart';
import '../widgets/app_select_field.dart';
import '../widgets/app_popup.dart';
import '../navigation/app_route_observer.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  static const routeName = '/settings';
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with RouteAware, WidgetsBindingObserver {
  final _apiKeyController = TextEditingController();
  final _apiKeyStorageService = ApiKeyStorageService();
  final _settingsSyncService = SettingsSyncService();
  final _settingsEncryptionService = SettingsEncryptionService();
  final _syncStateStore = SettingsSyncStateStore();
  bool _isLoading = true;
  bool _isSavingApiKey = false;
  bool _apiKeyValid = false;
  String? _userDisplayName;
  String? _userEmail;
  String? _userPhotoUrl;
  bool _signedIn = false;
  String?
  _previousApiKey; // Store previous key to restore on validation failure
  List<Map<String, dynamic>> _availableCalendars = [];
  String? _selectedCalendarId;
  String? _defaultCalendarName;
  bool _loadingCalendars = false;
  bool _creatingCalendar = false;
  bool _windowsHasPackageIdentity = true;
  bool _launchOnStartup = false;
  bool _isOffline = false;
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _windowsHasPackageIdentity = Platform.isWindows;
    _loadSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeSubscribed && route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didPopNext() {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {}
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final online = await _hasInternetConnection();
    if (mounted) {
      setState(() {
        _isOffline = !online;
      });
    }

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
          _userDisplayName = acc['displayName'];
          _userEmail = acc['email'];
          _userPhotoUrl = acc['photoUrl'];
        });
      }

      // Load default calendar
      await _loadDefaultCalendar();
    }

    // Load Windows startup preference (Windows only)
    if (mounted && Platform.isWindows) {
      try {
        final startupEnabled = await WindowsStartupService.instance
            .getLaunchOnStartupEnabled();
        if (mounted) {
          setState(() {
            _launchOnStartup = startupEnabled;
          });
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (signedIn) {
      unawaited(_loadCalendars());
      if (online) {
        unawaited(_syncSettingsWithCloud());
      }
    }
  }

  Future<void> _toggleLaunchOnStartup(bool value) async {
    if (!Platform.isWindows) {
      return;
    }
    setState(() {
      _launchOnStartup = value;
    });
    await WindowsStartupService.instance.setLaunchOnStartupEnabled(value);
    await _markSettingsDirty();
    await _pushSettingsToCloud();
  }

  Future<void> _saveApiKey() async {
    final apiKey = _apiKeyController.text.trim();

    // Allow removing API key if field is empty
    if (apiKey.isEmpty) {
      // Only show confirmation popup if there was an API key before
      if (_previousApiKey != null && _previousApiKey!.isNotEmpty) {
        // Show confirmation popup before removing
        final shouldRemove = await showAppDialog<bool>(
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
        await _markSettingsDirty();
        await _pushSettingsToCloud();
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
        await _markSettingsDirty();
        await _pushSettingsToCloud();
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
          _availableCalendars = _mergeCalendars(_availableCalendars, cached);
          if (_selectedCalendarId == null && cached.isNotEmpty) {
            _selectedCalendarId = cached.first['id'] as String?;
          }
          _loadingCalendars = false;
        });
      }

      if (_isOffline) {
        if (mounted) {
          setState(() => _loadingCalendars = false);
        }
        return;
      }

      final calendars = await GoogleCalendarService.instance.getUserCalendars();
      if (mounted) {
        setState(() {
          _availableCalendars = _mergeCalendars(_availableCalendars, calendars);
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
        if (_isOfflineCalendarLoadError(e)) {
          debugPrint('Skipping calendar load popup while offline: $e');
          return;
        }
        _showErrorPopup('Failed to load calendars: ${e.toString()}');
      }
    }
  }

  /// Keeps an optimistic calendar visible while Google Calendar refreshes.
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

  Future<void> _createCalendar() async {
    final nameController = TextEditingController();
    final name = await showAppDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create calendar'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Calendar name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || _creatingCalendar) return;

    final temporaryId =
        'pending-calendar-${DateTime.now().microsecondsSinceEpoch}';
    final previousId = _selectedCalendarId;
    final optimisticCalendar = <String, dynamic>{
      'id': temporaryId,
      'name': name,
      'color': 0xFF5D9ED5,
    };
    setState(() {
      _creatingCalendar = true;
      _availableCalendars = [..._availableCalendars, optimisticCalendar];
      _selectedCalendarId = temporaryId;
    });

    try {
      final calendar = await GoogleCalendarService.instance.createCalendar(
        name: name,
        color: 0xFF5D9ED5,
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
      });
      await _saveDefaultCalendar();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _availableCalendars = _availableCalendars
            .where((item) => item['id'] != temporaryId)
            .toList();
        _selectedCalendarId = previousId;
      });
      _showErrorPopup('Could not create calendar: $error');
    } finally {
      if (mounted) setState(() => _creatingCalendar = false);
    }
  }

  bool _isOfflineCalendarLoadError(Object error) {
    if (error is SocketException) {
      return true;
    }
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (code.contains('network')) {
        return true;
      }
      final msg = (error.message ?? '').toLowerCase();
      if (msg.contains('apiexception: 7') ||
          msg.contains('network_error') ||
          msg.contains('network')) {
        return true;
      }
    }

    final message = error.toString().toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('socketexception') ||
        message.contains('errno = 11001') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('no address associated with hostname') ||
        message.contains('apiexception: 7') ||
        message.contains('network_error');
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
      await _markSettingsDirty();
      await _pushSettingsToCloud();
    } catch (e) {
      if (mounted) {
        _showErrorPopup('Failed to save calendar selection: ${e.toString()}');
      }
    }
  }

  Future<void> _syncSettingsWithCloud() async {
    final online = await _hasInternetConnection();
    if (mounted && _isOffline == online) {
      setState(() => _isOffline = !online);
    }
    if (!online) {
      return;
    }
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
      user ??= await GoogleCalendarService.instance
          .ensureFirebaseAuthSignedIn();
    } catch (e) {
      debugPrint('FirebaseAuth unavailable (settings sync skipped): $e');
      return;
    }
    if (!_signedIn || user == null) {
      return;
    }

    try {
      final state = await _syncStateStore.load(user.uid);
      final localMs = state.lastLocalUpdatedAtMs ?? 0;
      final data = await _settingsSyncService.fetchForUser(user.uid);
      if (data == null) {
        if (state.pendingPush) {
          await _pushSettingsToCloud();
        }
        return;
      }

      final cloudMs = _extractUpdatedAtMs(data) ?? 0;
      await _syncStateStore.updateCloudTimestamp(user.uid, cloudMs);

      if (state.pendingPush && localMs > cloudMs) {
        await _pushSettingsToCloud();
        return;
      }

      if (cloudMs > localMs) {
        await _applyCloudSettings(data, user);
        await _syncStateStore.markSynced(user.uid, cloudMs);
        return;
      }

      if (localMs > cloudMs) {
        await _pushSettingsToCloud();
      }
    } catch (e) {
      debugPrint('Failed to sync settings from cloud: $e');
    }
  }

  Future<bool> _pushSettingsToCloud() async {
    final online = await _hasInternetConnection();
    if (mounted && _isOffline == online) {
      setState(() => _isOffline = !online);
    }
    if (!online) {
      return false;
    }
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
      user ??= await GoogleCalendarService.instance
          .ensureFirebaseAuthSignedIn();
    } catch (e) {
      debugPrint('FirebaseAuth unavailable (settings sync skipped): $e');
      return false;
    }
    if (!_signedIn || user == null) {
      return false;
    }

    try {
      final storage = GoogleCalendarService.instance.storage;
      final calendarId =
          _selectedCalendarId ?? await storage.getDefaultCalendarId();
      final calendarName =
          _defaultCalendarName ?? await storage.getDefaultCalendarName();

      final ok = await _settingsSyncService.saveForUser(user.uid, {
        'userEmail': user.email ?? _userEmail,
        'defaultCalendarId': calendarId,
        'defaultCalendarName': calendarName,
        'aiApiKey': await _apiKeyStorageService.getApiKey(),
        'launchOnStartup': Platform.isWindows ? _launchOnStartup : null,
      });
      if (ok) {
        final state = await _syncStateStore.load(user.uid);
        final localMs =
            state.lastLocalUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
        await _syncStateStore.markSynced(user.uid, localMs);
      }
      return ok;
    } catch (e) {
      debugPrint('Failed to push settings to cloud: $e');
      return false;
    }
  }

  int? _extractUpdatedAtMs(Map<String, dynamic> data) {
    final raw = data['updatedAt'];
    if (raw is Timestamp) {
      return raw.millisecondsSinceEpoch;
    }
    if (raw is DateTime) {
      return raw.toUtc().millisecondsSinceEpoch;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return null;
  }

  Future<void> _applyCloudSettings(Map<String, dynamic> data, User user) async {
    final calendarId = data['defaultCalendarId'];
    final calendarName = data['defaultCalendarName'];
    if (calendarId is String && calendarId.isNotEmpty) {
      final name = calendarName is String && calendarName.isNotEmpty
          ? calendarName
          : (_defaultCalendarName ?? 'Unknown');
      await GoogleCalendarService.instance.storage.saveDefaultCalendar(
        calendarId,
        name,
      );
      if (mounted) {
        setState(() {
          _selectedCalendarId = calendarId;
          _defaultCalendarName = name;
        });
      }
    }

    final launchOnStartup = data['launchOnStartup'];
    if (launchOnStartup is bool && Platform.isWindows) {
      await WindowsStartupService.instance.setLaunchOnStartupEnabled(
        launchOnStartup,
      );
      if (mounted) {
        setState(() {
          _launchOnStartup = launchOnStartup;
        });
      }
    }

    final apiKey = data['aiApiKey'];
    if (apiKey is String && apiKey.trim().isNotEmpty) {
      final trimmed = apiKey.trim();
      await _apiKeyStorageService.saveApiKey(trimmed);
      if (mounted) {
        setState(() {
          _apiKeyController.text = trimmed;
          _previousApiKey = trimmed;
        });
      }
      final valid = await _validateApiKey(trimmed);
      if (mounted) {
        setState(() {
          _apiKeyValid = valid;
        });
      }
      return;
    }

    // Backward-compat: accept encrypted key if present from older builds.
    final encApiKey = data['aiApiKeyEnc'];
    if (encApiKey is String && encApiKey.isNotEmpty) {
      final clear = await _settingsEncryptionService.decryptApiKey(
        uid: user.uid,
        encoded: encApiKey,
      );
      if (clear != null && clear.trim().isNotEmpty) {
        final trimmed = clear.trim();
        await _apiKeyStorageService.saveApiKey(trimmed);
        if (mounted) {
          setState(() {
            _apiKeyController.text = trimmed;
            _previousApiKey = trimmed;
          });
        }
        final valid = await _validateApiKey(trimmed);
        if (mounted) {
          setState(() {
            _apiKeyValid = valid;
          });
        }
      }
    }
  }

  Future<void> _markSettingsDirty() async {
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        await _syncStateStore.markLocalDirty(current.uid);
        return;
      }
      if (_isOffline) {
        return;
      }
      final user = await GoogleCalendarService.instance
          .ensureFirebaseAuthSignedIn();
      if (user == null) return;
      await _syncStateStore.markLocalDirty(user.uid);
    } catch (_) {}
  }

  void _showErrorPopup(String message) {
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

  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final shouldLogout = await showAppDialog<bool>(
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
            child: const Text(
              'Logout',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
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

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Widget _buildSettingsBody(bool isWide) {
    final content = ListView(
      padding: EdgeInsets.all(isWide ? 24 : 16),
      children: [
        _buildAccountSection(),
        const SizedBox(height: 16),
        _buildAiSection(),
        if (Platform.isAndroid || Platform.isWindows) ...[
          const SizedBox(height: 16),
        ],
        if (_signedIn) ...[_buildCalendarSection(), const SizedBox(height: 16)],
        if (Platform.isAndroid || Platform.isWindows) ...[
          _buildPlatformSection(),
          const SizedBox(height: 16),
        ],
        _buildAboutSection(),
        const SizedBox(height: 16),
        _buildLogoutSection(),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (isWide) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: content,
            ),
          );
        }
        return content;
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.onSurface.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.headline2.copyWith(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(
        height: 1,
        color: AppColors.onSurface.withValues(alpha: 0.08),
      ),
    );
  }

  Widget _buildSettingRow({
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.bodyText1),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTextStyles.bodyText1.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.62),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Align(alignment: Alignment.center, child: trailing),
      ],
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return _buildSettingRow(
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
    );
  }

  Widget _buildCalendarSection() {
    return _buildSectionCard(
      title: 'Default Calendar',
      icon: Icons.calendar_today_outlined,
      children: [
        if (_loadingCalendars)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_availableCalendars.isEmpty)
          Text(
            'No calendars available right now.',
            style: AppTextStyles.bodyText1.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.62),
            ),
          )
        else
          AppSelectField<String>(
            label: 'Default calendar',
            value: _selectedCalendarId,
            options: _availableCalendars
                .map(
                  (calendar) => AppSelectOption(
                    value: calendar['id'] as String,
                    label: calendar['name'] as String? ?? '',
                    color: calendar['color'] is int
                        ? Color(calendar['color'] as int)
                        : null,
                  ),
                )
                .toList(),
            onAddPressed: _creatingCalendar ? null : _createCalendar,
            showAddInField: false,
            addTooltip: _creatingCalendar
                ? 'Creating calendar...'
                : 'Create calendar',
            onChanged: (value) {
              if (value == _selectedCalendarId) return;
              setState(() => _selectedCalendarId = value);
              _saveDefaultCalendar();
            },
          ),
      ],
    );
  }

  Widget _buildPlatformSection() {
    final children = <Widget>[];

    if (Platform.isWindows) {
      children.add(
        _buildSwitchRow(
          title: 'Launch on Windows startup',
          subtitle: _windowsHasPackageIdentity
              ? 'Start Agenix automatically when Windows starts.'
              : 'May require MSIX install or manual startup registration.',
          value: _launchOnStartup,
          onChanged: (value) => _toggleLaunchOnStartup(value),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildSectionCard(
      title: 'Startup',
      icon: Icons.rocket_launch_outlined,
      children: children,
    );
  }

  Widget _buildAiSection() {
    return _buildSectionCard(
      title: 'AI Tools',
      icon: Icons.auto_awesome_outlined,
      children: [
        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(
            hintText: 'Enter your AI API key',
            hintStyle: AppTextStyles.bodyText1.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            suffixIcon: _isSavingApiKey
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : AppPressFeedback(
                    child: IconButton(
                      icon: Icon(
                        _apiKeyValid
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                      ),
                      color: _apiKeyValid ? Colors.green : AppColors.primary,
                      onPressed: _saveApiKey,
                    ),
                  ),
          ),
          style: AppTextStyles.bodyText1,
          obscureText: true,
          enabled: !_isSavingApiKey,
          onChanged: (value) {
            if (_apiKeyValid) {
              setState(() {
                _apiKeyValid = false;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildAccountSection() {
    final accountTitle = _signedIn
        ? ((_userDisplayName != null && _userDisplayName!.trim().isNotEmpty)
              ? _userDisplayName!.trim()
              : (_userEmail ?? 'Google account'))
        : 'Account not connected';
    final accountSubtitle = _signedIn && _userEmail != null
        ? _userEmail!
        : 'Sign in from the welcome screen to sync your account.';

    return _buildSectionCard(
      title: 'Account',
      icon: Icons.account_circle_outlined,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.onSurface.withValues(alpha: 0.06),
                AppColors.onSurface.withValues(alpha: 0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: _buildUserAvatar(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accountTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyText1,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accountSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyText1.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.62),
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return _buildSectionCard(
      title: 'About',
      icon: Icons.info_outline_rounded,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.onSurface.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Developer',
                      style: AppTextStyles.bodyText1.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sachicodex',
                      style: AppTextStyles.headline2.copyWith(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.onSurface.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App version',
                      style: AppTextStyles.bodyText1.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'v6.3.25',
                      style: AppTextStyles.headline2.copyWith(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLogoutSection() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _signedIn ? _handleLogout : null,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Logout'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            backgroundColor: AppColors.error.withValues(alpha: 0.1),
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
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
            icon: const Icon(Icons.arrow_back_ios_rounded),
            tooltip: '',
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            splashRadius: 14,
            visualDensity: VisualDensity.compact,
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              backgroundColor: WidgetStateProperty.all(Colors.transparent),
            ),
            onPressed: () {
              Navigator.maybePop(context);
            },
          ),
        ),
        title: Text('Settings', style: AppTextStyles.headline2),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: _buildSettingsBody(isWide),
    );
  }

  Widget _buildUserAvatar() {
    if (_userPhotoUrl == null || _userPhotoUrl!.isEmpty) {
      return CircleAvatar(
        backgroundColor: AppColors.primary,
        child: Icon(Icons.person, color: AppColors.onPrimary),
      );
    }

    final path = _userPhotoUrl!;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return CircleAvatar(
        backgroundImage: NetworkImage(
          path,
          headers: const {'Cache-Control': 'max-age=3600'},
        ),
      );
    }

    try {
      final file = File(path);
      if (file.existsSync()) {
        return CircleAvatar(backgroundImage: FileImage(file));
      }
    } catch (_) {
      // Fall through to default avatar
    }

    return CircleAvatar(
      backgroundColor: AppColors.primary,
      child: Icon(Icons.person, color: AppColors.onPrimary),
    );
  }
}
