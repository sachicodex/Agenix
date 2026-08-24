import 'package:flutter/services.dart';

/// Converts platform sign-in failures into messages a user can act on.
String googleSignInErrorMessage(Object error) {
  if (error is PlatformException) {
    final details = '${error.code} ${error.message ?? ''} ${error.details ?? ''}'
        .toLowerCase();
    final isAndroidConfigurationError =
        error.code == 'sign_in_failed' &&
        (details.contains('apiexcption: 10') ||
            details.contains('apiexception: 10') ||
            details.contains('developer_error'));

    if (isAndroidConfigurationError) {
      return 'Google Sign-In is not configured for this Android app yet. '
          'Add this app\'s signing certificate SHA-1 to the Android app in '
          'Firebase Console, then download the updated google-services.json and '
          'replace android/app/google-services.json. Rebuild and reinstall the app.';
    }

    if (error.code == 'network_error') {
      return 'Google Sign-In needs an internet connection. Check your connection and try again.';
    }
  }

  return 'Google Sign-In could not be completed. Please try again.';
}
