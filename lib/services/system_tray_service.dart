import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class SystemTrayService with TrayListener, WindowListener {
  SystemTrayService._();

  static final SystemTrayService instance = SystemTrayService._();

  bool _initialized = false;
  bool _allowClose = false;
  bool _pendingExitAfterSync = false;
  Future<bool> Function()? _exitGuard;
  Future<void>? _exitAfterSyncInFlight;
  Timer? _exitRetryTimer;
  bool _quitting = false;

  static const Duration _exitRetryDelay = Duration(seconds: 2);

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
      _cancelExitRetryTimer();
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
    try {
      await windowManager.hide();
    } catch (error) {
      // A hide failure must not prevent the final sync/exit workflow.
      _log('window hide failed: $error');
    } finally {
      unawaited(_exitAfterPendingSync());
    }
  }

  Future<void> _showWindow() async {
    _log('show window and cancel pending exit');
    _pendingExitAfterSync = false;
    _cancelExitRetryTimer();
    await windowManager.show();
    await windowManager.focus();
  }

  void setExitGuard(Future<bool> Function() guard) {
    _exitGuard = guard;
  }

  Future<void> _quitApp() async {
    if (_quitting) return;
    _quitting = true;
    _log('quit app start');
    _allowClose = true;
    _pendingExitAfterSync = false;
    _cancelExitRetryTimer();

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

  Future<void> _exitAfterPendingSync() async {
    if (_exitAfterSyncInFlight != null) return _exitAfterSyncInFlight;

    final workflow = _runExitAfterPendingSync();
    _exitAfterSyncInFlight = workflow;
    try {
      await workflow;
    } finally {
      if (identical(_exitAfterSyncInFlight, workflow)) {
        _exitAfterSyncInFlight = null;
      }
    }
  }

  Future<void> _runExitAfterPendingSync() async {
    if (!_pendingExitAfterSync) return;

    // The guard performs and awaits the last local sync. A false result means
    // there is no remaining work, so it is now safe to remove the tray icon
    // and terminate the Windows process.
    bool shouldBlockExit;
    try {
      shouldBlockExit = await _exitGuard?.call() ?? false;
    } catch (error) {
      // A failed guard must not strand the process permanently. Keep the
      // window hidden and retry on the next pass, just like background sync.
      _log('final sync check failed: $error');
      _scheduleExitRetry();
      return;
    }
    _log('final sync completed shouldBlockExit=$shouldBlockExit');
    if (!_pendingExitAfterSync) return;
    if (shouldBlockExit) {
      _scheduleExitRetry();
      return;
    }

    await _quitApp();
  }

  void _scheduleExitRetry() {
    if (!_pendingExitAfterSync || _quitting || _exitRetryTimer != null) {
      return;
    }
    _log(
      'final sync still has pending work -> retry in ${_exitRetryDelay.inSeconds}s',
    );
    _exitRetryTimer = Timer(_exitRetryDelay, () {
      _exitRetryTimer = null;
      unawaited(_exitAfterPendingSync());
    });
  }

  void _cancelExitRetryTimer() {
    _exitRetryTimer?.cancel();
    _exitRetryTimer = null;
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
