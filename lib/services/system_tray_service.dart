import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'sync_service.dart';

class SystemTrayService with TrayListener, WindowListener {
  SystemTrayService._();

  static final SystemTrayService instance = SystemTrayService._();

  bool _initialized = false;
  bool _allowClose = false;
  bool _pendingExitAfterSync = false;
  bool _syncing = false;
  Future<bool> Function()? _exitGuard;
  Timer? _exitGuardTimer;
  bool _exitGuardCheckInFlight = false;
  bool _quitting = false;

  void _log(String message) {
    if (kDebugMode && Platform.isWindows) {
      debugPrint('[SystemTray] $message');
    }
  }

  Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    _initialized = true;
    _log('initialize');

    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    final iconPath = _resolveTrayIconPath();
    if (iconPath != null) {
      await trayManager.setIcon(iconPath);
    }

    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: 'Show'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit'),
      ],
    );
    await trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  @override
  void onTrayIconMouseDown() {
    _log('tray icon click -> show window');
    _showWindow();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == 'show') {
      _log('tray menu show');
      _showWindow();
      return;
    }
    if (key == 'quit') {
      _log('tray menu quit');
      _pendingExitAfterSync = false;
      _cancelExitGuardTimer();
      unawaited(_quitApp());
    }
  }

  @override
  void onWindowClose() async {
    if (_allowClose) {
      _log('window close allowed immediately');
      return;
    }
    _log('window close intercepted -> hide to tray and start exit guard');
    _pendingExitAfterSync = true;
    await windowManager.hide();
    await _checkExitGuardOnce();
    _startExitGuardTimer();
  }

  Future<void> _showWindow() async {
    _log('show window and cancel pending exit');
    _pendingExitAfterSync = false;
    _cancelExitGuardTimer();
    await windowManager.show();
    await windowManager.focus();
  }

  void setExitGuard(Future<bool> Function() guard) {
    _exitGuard = guard;
  }

  void updateSyncStatus(SyncStatus status) {
    if (!Platform.isWindows) return;
    _syncing = status.state == SyncState.syncing;
    _log(
      'sync status updated syncing=$_syncing pendingExit=$_pendingExitAfterSync',
    );
    if (_pendingExitAfterSync && !_syncing) {
      _checkExitGuardOnce();
      _startExitGuardTimer();
    }
  }

  Future<void> _quitApp() async {
    if (_quitting) return;
    _quitting = true;
    _log('quit app start');
    _allowClose = true;
    _pendingExitAfterSync = false;
    _cancelExitGuardTimer();

    try {
      trayManager.removeListener(this);
    } catch (_) {}
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    try {
      await trayManager.destroy();
    } catch (_) {}
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {}
    try {
      await windowManager.close();
    } catch (_) {}

    // Explicit exit avoids the process lingering in the system tray on Windows.
    _log('quit app -> exit(0)');
    exit(0);
  }

  void _startExitGuardTimer() {
    if (!_pendingExitAfterSync) return;
    if (_exitGuard == null) {
      _log('no exit guard -> quit immediately');
      _pendingExitAfterSync = false;
      unawaited(_quitApp());
      return;
    }
    if (_exitGuardTimer != null) return;

    _exitGuardTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_pendingExitAfterSync) {
        _cancelExitGuardTimer();
        return;
      }
      if (_exitGuardCheckInFlight) return;
      _log('periodic exit guard check');
      _exitGuardCheckInFlight = true;
      try {
        final shouldBlockExit = await _exitGuard!.call();
        _log('periodic exit guard result shouldBlockExit=$shouldBlockExit');
        if (!shouldBlockExit) {
          _pendingExitAfterSync = false;
          _cancelExitGuardTimer();
          unawaited(_quitApp());
        }
      } catch (_) {
        // Keep waiting if guard fails.
      } finally {
        _exitGuardCheckInFlight = false;
      }
    });
  }

  Future<void> _checkExitGuardOnce() async {
    if (!_pendingExitAfterSync) return;
    if (_exitGuard == null) {
      _log('single exit guard missing -> quit immediately');
      _pendingExitAfterSync = false;
      unawaited(_quitApp());
      return;
    }
    if (_exitGuardCheckInFlight) return;
    _log('single exit guard check');
    _exitGuardCheckInFlight = true;
    try {
      final shouldBlockExit = await _exitGuard!.call();
      _log('single exit guard result shouldBlockExit=$shouldBlockExit');
      if (!shouldBlockExit) {
        _pendingExitAfterSync = false;
        _cancelExitGuardTimer();
        unawaited(_quitApp());
      }
    } catch (_) {
      // Ignore and let periodic checks handle.
    } finally {
      _exitGuardCheckInFlight = false;
    }
  }

  void _cancelExitGuardTimer() {
    _exitGuardTimer?.cancel();
    _exitGuardTimer = null;
    _exitGuardCheckInFlight = false;
  }

  String? _resolveTrayIconPath() {
    final candidates = <String>[
      'assets/logo/agenix-windows.png',
      '${File(Platform.resolvedExecutable).parent.path}\\data\\flutter_assets\\assets\\logo\\agenix-windows.png',
    ];

    for (final path in candidates) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          return file.path;
        }
      } catch (_) {}
    }
    return null;
  }
}
