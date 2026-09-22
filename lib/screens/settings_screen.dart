import 'dart:async';
import 'dart:io';

import 'package:agenix/widgets/Custom%20App%20Bar/custom_app_bar.dart';
import 'package:agenix/widgets/Custom%20Card/custom_card.dart';
import 'package:agenix/widgets/Custom%20Dialog/reusable_dialog.dart';
import 'package:agenix/widgets/Custom%20Text/custom_text.dart';
import 'package:agenix/widgets/Glass%20Card/glass_carrd.dart';
import 'package:agenix/widgets/Primary%20Button/primary_button.dart';
import 'package:agenix/widgets/Secondary%20Button/secondary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:hugeicons/hugeicons.dart';
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
import '../widgets/app_icon.dart';
import '../widgets/modern_splash_screen.dart';
import '../widgets/app_select_field.dart';
import '../widgets/app_popup.dart';
import '../widgets/calendar_color_picker.dart';
import '../widgets/app_bar_widget/app_bar.dart';
import '../widgets/app_input/input.dart';
import '../navigation/app_route_observer.dart';
import '../utils/platform_focus.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  static const routeName = '/settings';
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsCalendarDraft {
  const _SettingsCalendarDraft({required this.name, required this.color});

  final String name;
  final Color color;
}

class _SettingsCreateCalendarDialog extends StatefulWidget {
  const _SettingsCreateCalendarDialog();

  @override
  State<_SettingsCreateCalendarDialog> createState() =>
      _SettingsCreateCalendarDialogState();
}

class _SettingsCreateCalendarDialogState
    extends State<_SettingsCreateCalendarDialog> {
  final _nameController = TextEditingController();
  Color _selectedColor = AppColors.royalBlue;
  bool _saving = false;
  Timer? _nameErrorTimer;
  bool _showNameError = false;

  @override
  void dispose() {
    _nameErrorTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _nameErrorTimer?.cancel();
      setState(() => _showNameError = true);
      _nameErrorTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showNameError = false);
      });
      return;
    }
    setState(() => _saving = true);
    Navigator.pop(
      context,
      _SettingsCalendarDraft(name: name, color: _selectedColor),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: appPopupInsetPadding(context),
    child: GlassCard(
      width: appPopupWidth(context, 360),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            autofocus: shouldAutofocusTextInput,
            textCapitalization: TextCapitalization.sentences,
            style: AppTextStyles.bodyText1,
            decoration: InputDecoration(
              labelText: 'Calendar name',
              labelStyle: AppTextStyles.bodyText1.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
              filled: true,
              fillColor: Colors.transparent,
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
                borderSide: _focusedNameBorder,
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
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SecondaryButton(
                    width: double.infinity,
                    onPressed: () => Navigator.pop(context),
                    label: 'Cancel',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    width: double.infinity,
                    onPressed: _saving ? null : _save,
                    label: 'Save',
                    loading: _saving,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  BorderSide get _nameBorder => _showNameError
      ? const BorderSide(color: Colors.red, width: 1)
      : const BorderSide(color: AppColors.borderColor);

  BorderSide get _focusedNameBorder => _showNameError
      ? const BorderSide(color: Colors.red, width: 1)
      : const BorderSide(color: AppColors.glassBorderFocus, width: 1.2);
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
          builder: (context) => CustomTwoActionDialog(
            title: 'Do you Remove?',
            description:
                'Are you sure you want to remove your API key? AI features will be disabled until you add a new API key.',

            secondaryButton: (SecondaryButton(
              onPressed: () => Navigator.of(context).pop(false),
              label: 'Cancel',
            )),
            primaryButton: PrimaryButton(
              onPressed: () => Navigator.of(context).pop(true),
              label: 'Yes, Remove',
            ),
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
          // A successful remote response is authoritative. Do not keep
          // calendars that were deleted or removed from Google Calendar.
          _availableCalendars = calendars;
          // If the selected calendar was deleted, select a valid replacement.
          final selectedStillExists =
              _selectedCalendarId != null &&
              calendars.any(
                (calendar) => calendar['id'] == _selectedCalendarId,
              );
          if (!selectedStillExists && calendars.isNotEmpty) {
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
    final draft = await showAppDialog<_SettingsCalendarDraft>(
      context: context,
      builder: (_) => const _SettingsCreateCalendarDialog(),
    );
    if (draft == null || _creatingCalendar) return;

    final temporaryId =
        'pending-calendar-${DateTime.now().microsecondsSinceEpoch}';
    final previousId = _selectedCalendarId;
    final optimisticCalendar = <String, dynamic>{
      'id': temporaryId,
      'name': draft.name,
      'color': draft.color.toARGB32(),
    };
    setState(() {
      _creatingCalendar = true;
      _availableCalendars = [..._availableCalendars, optimisticCalendar];
      _selectedCalendarId = temporaryId;
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
      if (mounted) _showErrorPopup('Could not update calendar color: $error');
      return null;
    }
  }

  Future<void> _changeCalendarName(String calendarId, String name) async {
    try {
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
        if (_selectedCalendarId == calendarId) {
          _defaultCalendarName = name;
        }
      });
      if (_selectedCalendarId == calendarId) {
        await _saveDefaultCalendar();
      }
    } catch (error) {
      if (mounted) _showErrorPopup('Could not update calendar name: $error');
    }
  }

  Future<bool> _deleteCalendar(String calendarId) async {
    if (calendarId == 'primary') {
      _showErrorPopup('Default Calendar cannot be deleted.');
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
      await _saveDefaultCalendar();
      return true;
    } catch (error) {
      if (mounted) _showErrorPopup('Could not delete calendar: $error');
      return false;
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
      builder: (context) => CustomOneActionDialog(
        centerContent: true,
        centerTitle: true,
        cancelAsText: true,
        titleDescriptionSpacing: 5,
        cancelTextColor: AppColors.primary,
        title: 'Error',
        description: message,
      ),
    );
  }

  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final shouldLogout = await showAppDialog<bool>(
      context: context,
      builder: (context) => CustomTwoActionDialog(
        centerContent: true,
        centerTitle: true,
        title: 'Logout',
        showCancelButton: false,
        description: 'Are you sure you want to logout?',
        secondaryButton: SecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        primaryButton: PrimaryButton(
          label: 'Yes, Log out',
          onPressed: () => Navigator.of(context).pop(true),
        ),
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
        _buildAccountAndServicesSection(),
        const SizedBox(height: 32),
        if (_signedIn || Platform.isWindows) ...[
          _buildAppPreferencesSection(),
          const SizedBox(height: 32),
        ],
        _buildAboutSection(),
        const SizedBox(height: 32),
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
    required AppIconData icon,
    required List<Widget> children,
  }) {
    return CustomCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.onSurface.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: AppIcon(
                  icon: icon,
                  color: AppColors.onBackground,
                  size: 5,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [CustomTextHeading(title)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
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
              CustomTextBody(title),
              const SizedBox(height: 4),
              CustomTextMuted(subtitle),
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

  Widget _buildAccountAndServicesSection() {
    return _buildSectionCard(
      title: 'Account & Services',
      icon: AppIconData.huge(HugeIcons.strokeRoundedDatabase),
      children: [
        _buildAccountContent(),
        const SizedBox(height: 18),
        _buildAiContent(),
      ],
    );
  }

  Widget _buildAppPreferencesSection() {
    final children = <Widget>[];
    if (_signedIn) {
      children.add(_buildCalendarContent());
    }
    if (_signedIn && Platform.isWindows) {
      children.add(const SizedBox(height: 18));
    }
    if (Platform.isWindows) {
      children.add(_buildStartupContent());
    }

    return _buildSectionCard(
      title: 'App Preferences',
      icon: AppIconData.huge(HugeIcons.strokeRoundedSettings01),
      children: children,
    );
  }

  Widget _buildCalendarContent() {
    if (_loadingCalendars) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_availableCalendars.isEmpty) {
      return CustomTextBody('No calendars available right now.');
    }

    return AppSelectField<String>(
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
      onDelete: _deleteCalendar,
      onColorChanged: _changeCalendarColor,
      onNameChanged: _changeCalendarName,
      onChanged: (value) {
        if (value == _selectedCalendarId) return;
        setState(() => _selectedCalendarId = value);
        _saveDefaultCalendar();
      },
    );
  }

  Widget _buildStartupContent() {
    return _buildSwitchRow(
      title: 'Launch on Windows startup',
      subtitle: _windowsHasPackageIdentity
          ? 'Start Agenix automatically when Windows starts.'
          : 'May require MSIX install or manual startup registration.',
      value: _launchOnStartup,
      onChanged: (value) => _toggleLaunchOnStartup(value),
    );
  }

  Widget _buildAiContent() {
    return AppInput(
      controller: _apiKeyController,
      autofocus: shouldAutofocusTextInput,
      hintText: 'Enter your API key',
      hintStyle: AppTextStyles.bodyText1.copyWith(
        color: AppColors.onSurface.withValues(alpha: 0.5),
      ),
      borderRadius: const BorderRadius.all(Radius.circular(14)),
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
      textStyle: AppTextStyles.bodyText1,
      obscureText: true,
      enabled: !_isSavingApiKey,
      onChanged: (value) {
        if (_apiKeyValid) {
          setState(() {
            _apiKeyValid = false;
          });
        }
      },
    );
  }

  Widget _buildAccountContent() {
    final accountTitle = _signedIn
        ? ((_userDisplayName != null && _userDisplayName!.trim().isNotEmpty)
              ? _userDisplayName!.trim()
              : (_userEmail ?? 'Google account'))
        : 'Account not connected';
    final accountSubtitle = _signedIn && _userEmail != null
        ? _userEmail!
        : 'Sign in from the welcome screen to sync your account.';

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.onBackground.withValues(alpha: 0.35),
              ),
            ),
            child: _buildUserAvatar(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTextBody(
                  accountTitle,
                  style: TextStyle(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                CustomTextMuted(
                  accountSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return _buildSectionCard(
      title: 'About',
      icon: AppIconData.huge(HugeIcons.strokeRoundedInformationCircle),
      children: [
        Row(
          children: [
            Expanded(
              child: GlassCard(
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextDescription(
                      'Developer',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    CustomTextBody(
                      'Sachicodex',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassCard(
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextDescription(
                      'App Version',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    CustomTextBody('v6.3.25', style: TextStyle(fontSize: 16)),
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
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: double.infinity,
        child: SecondaryButton(
          onPressed: _signedIn ? _handleLogout : null,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedLogout02),
          iconSize: 20,
          label: 'Logout',
          padding: EdgeInsets.symmetric(vertical: 20),
          backgroundColor: AppColors.error,
          foregroundColor: AppColors.card,
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
      appBar: CustomAppBar(
        leading: AppPressFeedback(
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
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
        title: CustomTextHeading('Settings', style: TextStyle(fontSize: 24)),
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
