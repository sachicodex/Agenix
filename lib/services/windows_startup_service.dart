import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'windows_app_data_service.dart';

/// Simple Windows startup manager using a per-user config file.
///
/// Notes:
/// - For MSIX-installed apps, the system exposes its own startup task controls.
///   This helper is mainly intended for non-MSIX installs, where the app can
///   simulate "launch on startup" by being started via a small helper, script,
///   or by asking the user to add it manually and just tracking the preference.
class WindowsStartupService {
  WindowsStartupService._internal();

  static final WindowsStartupService instance =
      WindowsStartupService._internal();

  static const _configFileName = 'startup_config.json';
  static const _runRegistryPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runValueName = 'Agenix';

  bool _cachedEnabled = false;
  bool _loaded = false;

  bool get isSupported => defaultTargetPlatform == TargetPlatform.windows;

  bool get cachedEnabled => _cachedEnabled;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    if (!isSupported) {
      _cachedEnabled = false;
      return;
    }

    try {
      final path = await WindowsAppDataService.instance
          .getLocalStateFilePath(_configFileName);
      final file = File(path);
      if (!await file.exists()) {
        _cachedEnabled = false;
        return;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cachedEnabled = false;
        return;
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _cachedEnabled = json['launchOnStartup'] == true;
    } catch (_) {
      _cachedEnabled = false;
    }

    // Keep UI state aligned with actual Windows startup registration.
    try {
      _cachedEnabled = await _isStartupRegistered();
    } catch (_) {}
  }

  Future<bool> getLaunchOnStartupEnabled() async {
    await _ensureLoaded();
    return _cachedEnabled;
  }

  Future<void> setLaunchOnStartupEnabled(bool enabled) async {
    await _ensureLoaded();
    _cachedEnabled = enabled;

    if (!isSupported) return;

    try {
      await _setStartupRegistration(enabled);
      try {
        _cachedEnabled = await _isStartupRegistered();
      } catch (_) {}

      final path = await WindowsAppDataService.instance
          .getLocalStateFilePath(_configFileName);
      final file = File(path);
      final json = <String, dynamic>{
        'launchOnStartup': enabled,
      };
      await file.writeAsString(
        jsonEncode(json),
        flush: true,
      );
    } catch (_) {
      // Ignore failures; preference will fall back to false next run.
    }
  }

  Future<void> _setStartupRegistration(bool enabled) async {
    if (enabled) {
      final startupCommand = _buildStartupCommand();
      final result = await Process.run('reg', <String>[
        'add',
        _runRegistryPath,
        '/v',
        _runValueName,
        '/t',
        'REG_SZ',
        '/d',
        startupCommand,
        '/f',
      ]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'reg',
          <String>[
            'add',
            _runRegistryPath,
            '/v',
            _runValueName,
            '/t',
            'REG_SZ',
            '/d',
            startupCommand,
            '/f',
          ],
          '${result.stderr}',
          result.exitCode,
        );
      }
      return;
    }

    final result = await Process.run('reg', <String>[
      'delete',
      _runRegistryPath,
      '/v',
      _runValueName,
      '/f',
    ]);
    if (result.exitCode != 0) {
      final stderr = '${result.stderr}'.toLowerCase();
      // Already removed or missing value is acceptable.
      if (stderr.contains('unable to find')) {
        return;
      }
      throw ProcessException(
        'reg',
        <String>['delete', _runRegistryPath, '/v', _runValueName, '/f'],
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  Future<bool> _isStartupRegistered() async {
    final result = await Process.run('reg', <String>[
      'query',
      _runRegistryPath,
      '/v',
      _runValueName,
    ]);
    return result.exitCode == 0;
  }

  String _buildStartupCommand() {
    final executablePath = File(Platform.resolvedExecutable).absolute.path;
    return '"$executablePath" --from-startup';
  }
}

