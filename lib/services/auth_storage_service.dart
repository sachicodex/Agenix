import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

/// Service for securely storing and retrieving authentication credentials.
/// Uses flutter_secure_storage which provides encrypted storage on both
/// Windows and Android.
class AuthStorageService {
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
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyAccessToken = 'access_token';
  static const String _keyTokenExpiry = 'token_expiry';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserPhotoUrl = 'user_photo_url';
  static const String _keyUserDisplayName = 'user_display_name';
  static const String _keyScopes = 'scopes';
  static const String _keyDefaultCalendarId = 'default_calendar_id';
  static const String _keyDefaultCalendarName = 'default_calendar_name';

  /// Save authentication credentials securely
  Future<void> saveCredentials({
    required String? refreshToken,
    required String? accessToken,
    required DateTime? tokenExpiry,
    required List<String> scopes,
    String? userEmail,
    String? userPhotoUrl,
    String? userDisplayName,
  }) async {
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _storage.write(key: _keyRefreshToken, value: refreshToken);
      }
      if (accessToken != null && accessToken.isNotEmpty) {
        await _storage.write(key: _keyAccessToken, value: accessToken);
      }
      if (tokenExpiry != null) {
        await _storage.write(
          key: _keyTokenExpiry,
          value: tokenExpiry.toIso8601String(),
        );
      }
      if (scopes.isNotEmpty) {
        await _storage.write(key: _keyScopes, value: jsonEncode(scopes));
      }
      if (userEmail != null) {
        await _storage.write(key: _keyUserEmail, value: userEmail);
      }
      if (userPhotoUrl != null) {
        await _storage.write(key: _keyUserPhotoUrl, value: userPhotoUrl);
      }
      if (userDisplayName != null) {
        await _storage.write(key: _keyUserDisplayName, value: userDisplayName);
      }
    } catch (e) {
      // Log error but don't throw - storage failures shouldn't break the app
      print('Error saving credentials: $e');
    }
  }

  /// Retrieve stored refresh token
  Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _keyRefreshToken);
    } catch (e) {
      print('Error reading refresh token: $e');
      return null;
    }
  }

  /// Retrieve stored access token
  Future<String?> getAccessToken() async {
    try {
      return await _storage.read(key: _keyAccessToken);
    } catch (e) {
      print('Error reading access token: $e');
      return null;
    }
  }

  /// Retrieve stored token expiry
  Future<DateTime?> getTokenExpiry() async {
    try {
      final expiryStr = await _storage.read(key: _keyTokenExpiry);
      if (expiryStr != null) {
        return DateTime.parse(expiryStr);
      }
      return null;
    } catch (e) {
      print('Error reading token expiry: $e');
      return null;
    }
  }

  /// Retrieve stored scopes
  Future<List<String>> getScopes() async {
    try {
      final scopesStr = await _storage.read(key: _keyScopes);
      if (scopesStr != null) {
        final decoded = jsonDecode(scopesStr) as List;
        return decoded.cast<String>();
      }
      return [];
    } catch (e) {
      print('Error reading scopes: $e');
      return [];
    }
  }

  /// Retrieve stored user email
  Future<String?> getUserEmail() async {
    try {
      return await _storage.read(key: _keyUserEmail);
    } catch (e) {
      print('Error reading user email: $e');
      return null;
    }
  }

  /// Retrieve stored user photo URL
  Future<String?> getUserPhotoUrl() async {
    try {
      return await _storage.read(key: _keyUserPhotoUrl);
    } catch (e) {
      print('Error reading user photo URL: $e');
      return null;
    }
  }

  /// Retrieve stored user display name
  Future<String?> getUserDisplayName() async {
    try {
      return await _storage.read(key: _keyUserDisplayName);
    } catch (e) {
      print('Error reading user display name: $e');
      return null;
    }
  }

  /// Check if access token is still valid (not expired)
  Future<bool> isAccessTokenValid() async {
    final expiry = await getTokenExpiry();
    if (expiry == null) return false;
    // Consider token valid if it expires in more than 5 minutes
    return expiry.isAfter(DateTime.now().add(const Duration(minutes: 5)));
  }

  /// Clear all stored authentication credentials
  Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: _keyRefreshToken);
      await _storage.delete(key: _keyAccessToken);
      await _storage.delete(key: _keyTokenExpiry);
      await _storage.delete(key: _keyUserEmail);
      await _storage.delete(key: _keyUserPhotoUrl);
      await _storage.delete(key: _keyUserDisplayName);
      await _storage.delete(key: _keyScopes);
    } catch (e) {
      print('Error clearing credentials: $e');
    }
  }

  /// Check if any credentials are stored
  Future<bool> hasStoredCredentials() async {
    final refreshToken = await getRefreshToken();
    return refreshToken != null && refreshToken.isNotEmpty;
  }

  /// Save default calendar selection
  Future<void> saveDefaultCalendar(
    String calendarId,
    String calendarName,
  ) async {
    try {
      await _storage.write(key: _keyDefaultCalendarId, value: calendarId);
      await _storage.write(key: _keyDefaultCalendarName, value: calendarName);
    } catch (e) {
      print('Error saving default calendar: $e');
    }
  }

  /// Get default calendar ID
  Future<String?> getDefaultCalendarId() async {
    try {
      return await _storage.read(key: _keyDefaultCalendarId);
    } catch (e) {
      print('Error reading default calendar ID: $e');
      return null;
    }
  }

  /// Get default calendar name
  Future<String?> getDefaultCalendarName() async {
    try {
      return await _storage.read(key: _keyDefaultCalendarName);
    } catch (e) {
      print('Error reading default calendar name: $e');
      return null;
    }
  }

  /// Check if default calendar is set
  Future<bool> hasDefaultCalendar() async {
    final calendarId = await getDefaultCalendarId();
    return calendarId != null && calendarId.isNotEmpty;
  }

  /// Clear default calendar (called on sign out)
  Future<void> clearDefaultCalendar() async {
    try {
      await _storage.delete(key: _keyDefaultCalendarId);
      await _storage.delete(key: _keyDefaultCalendarName);
    } catch (e) {
      print('Error clearing default calendar: $e');
    }
  }
}
