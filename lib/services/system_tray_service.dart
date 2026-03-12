import 'dart:async';
import 'dart:io';

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

  Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    _initialized = true;

    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    final iconPath = _resolveTrayIconPath();
    if (iconPath != null) {
      await trayManager.setIcon(iconPath);
    }

    final menu = Menu(items: [
      MenuItem(key: 'show', label: 'Show'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]);
    await trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == 'show') {
      _showWindow();
      return;
    }
    if (key == 'quit') {
      _pendingExitAfterSync = false;
      _cancelExitGuardTimer();
      _quitApp();
    }
  }

  @override
  void onWindowClose() async {
    if (_allowClose) {
      return;
    }
    _pendingExitAfterSync = true;
    await windowManager.hide();
    await _checkExitGuardOnce();
    _startExitGuardTimer();
  }

  Future<void> _showWindow() async {
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
    if (_pendingExitAfterSync && !_syncing) {
      _checkExitGuardOnce();
      _startExitGuardTimer();
    }
  }

  void _quitApp() {
    _allowClose = true;
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  void _startExitGuardTimer() {
    if (!_pendingExitAfterSync) return;
    if (_exitGuard == null) {
      _pendingExitAfterSync = false;
      _quitApp();
      return;
    }
    if (_exitGuardTimer != null) return;

    _exitGuardTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_pendingExitAfterSync) {
        _cancelExitGuardTimer();
        return;
      }
      if (_exitGuardCheckInFlight) return;
      _exitGuardCheckInFlight = true;
      try {
        final shouldBlockExit = await _exitGuard!.call();
        if (!shouldBlockExit) {
          _pendingExitAfterSync = false;
          _cancelExitGuardTimer();
          _quitApp();
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
      _pendingExitAfterSync = false;
      _quitApp();
      return;
    }
    if (_exitGuardCheckInFlight) return;
    _exitGuardCheckInFlight = true;
    try {
      final shouldBlockExit = await _exitGuard!.call();
      if (!shouldBlockExit) {
        _pendingExitAfterSync = false;
        _cancelExitGuardTimer();
        _quitApp();
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
