import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves writable app data locations under a dedicated per-user folder.
///
/// Desktop: `<Documents>/Agenix/` (not the Documents root).
/// Mobile: `<app documents>/Agenix/`.
class AppDataService {
  AppDataService._internal();
  static final AppDataService instance = AppDataService._internal();

  static const String folderName = 'Agenix';
  static const String profileSubdir = 'profile';
  static const String databaseFileName = 'agenix_events.db';
  static const String profilePhotoPrefix = 'user_profile_photo';

  bool _legacyMigrationDone = false;

  /// Root folder for databases, profile assets, and local config.
  Future<Directory> getAppDataDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Profile photos and related user media.
  Future<Directory> getProfileDirectory() async {
    final base = await getAppDataDirectory();
    final dir = Directory(p.join(base.path, profileSubdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> getDatabasePath() async {
    await migrateLegacyRootFilesIfNeeded();
    final dir = await getAppDataDirectory();
    return p.join(dir.path, databaseFileName);
  }

  /// Writable file path under the app data folder (e.g. startup config).
  Future<String> getLocalStateFilePath(String filename) async {
    await migrateLegacyRootFilesIfNeeded();
    final dir = await getAppDataDirectory();
    return p.join(dir.path, filename);
  }

  /// Moves files that older builds wrote directly into Documents root.
  Future<void> migrateLegacyRootFilesIfNeeded() async {
    if (_legacyMigrationDone) return;
    _legacyMigrationDone = true;

    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return;
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      final appDir = await getAppDataDirectory();
      final profileDir = await getProfileDirectory();

      final legacyDb = File(p.join(docs.path, databaseFileName));
      final newDb = File(p.join(appDir.path, databaseFileName));
      if (await legacyDb.exists() && !await newDb.exists()) {
        await legacyDb.rename(newDb.path);
      }

      await _migrateLegacyProfilePhotos(
        legacyRoot: Directory(docs.path),
        targetDir: profileDir,
      );

      // Older builds also stored startup config under %LOCALAPPDATA%/Agenix.
      if (Platform.isWindows) {
        await _migrateLegacyLocalAppDataConfig(appDir);
      }
    } catch (_) {
      // Best-effort migration only.
    }
  }

  Future<void> _migrateLegacyProfilePhotos({
    required Directory legacyRoot,
    required Directory targetDir,
  }) async {
    for (final entry in legacyRoot.listSync(followLinks: false)) {
      if (entry is! File) continue;
      final name = p.basename(entry.path).toLowerCase();
      if (!name.startsWith(profilePhotoPrefix)) continue;

      final target = File(p.join(targetDir.path, p.basename(entry.path)));
      if (await target.exists()) {
        try {
          await entry.delete();
        } catch (_) {}
        continue;
      }
      try {
        await entry.rename(target.path);
      } catch (_) {}
    }
  }

  Future<void> _migrateLegacyLocalAppDataConfig(Directory appDir) async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) return;

    final legacyDir = Directory(p.join(localAppData, folderName));
    if (!await legacyDir.exists()) return;

    for (final entry in legacyDir.listSync(followLinks: false)) {
      if (entry is! File) continue;
      final target = File(p.join(appDir.path, p.basename(entry.path)));
      if (await target.exists()) continue;
      try {
        await entry.rename(target.path);
      } catch (_) {}
    }
  }
}
