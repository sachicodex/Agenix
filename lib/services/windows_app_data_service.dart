import 'dart:io';

class WindowsAppDataService {
  WindowsAppDataService._internal();
  static final WindowsAppDataService instance =
      WindowsAppDataService._internal();

  /// Returns a writable file path under a per-user application folder.
  /// On Windows this uses %LOCALAPPDATA%/Nuvex Flow, otherwise it falls back
  /// to the current working directory.
  Future<String> getLocalStateFilePath(String filename) async {
    final base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.current.path)
        : Directory.current.path;

    final dir = Directory('$base${Platform.pathSeparator}Nuvex Flow');
    if (!await dir.exists()) await dir.create(recursive: true);
    return '${dir.path}${Platform.pathSeparator}$filename';
  }
}
