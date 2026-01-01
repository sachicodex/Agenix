import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for securely storing and retrieving AI API keys.
/// Uses flutter_secure_storage which provides encrypted storage on both
/// Windows and Android.
class ApiKeyStorageService {
  static const _storage = FlutterSecureStorage(
    // Android options
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // Windows options
    wOptions: WindowsOptions(),
    // iOS options (for future use)
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Storage keys
  static const String _keyAiApiKey = 'ai_api_key';

  /// Save AI API key securely
  Future<void> saveApiKey(String apiKey) async {
    try {
      if (apiKey.trim().isNotEmpty) {
        await _storage.write(key: _keyAiApiKey, value: apiKey.trim());
      }
    } catch (e) {
      print('Error saving API key: $e');
      rethrow;
    }
  }

  /// Retrieve stored AI API key
  Future<String?> getApiKey() async {
    try {
      return await _storage.read(key: _keyAiApiKey);
    } catch (e) {
      print('Error reading API key: $e');
      return null;
    }
  }

  /// Check if API key is stored
  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.trim().isNotEmpty;
  }

  /// Clear stored API key
  Future<void> clearApiKey() async {
    try {
      await _storage.delete(key: _keyAiApiKey);
    } catch (e) {
      print('Error clearing API key: $e');
    }
  }
}
