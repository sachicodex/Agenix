import 'package:agenix/theme/app_colors.dart';
import 'package:agenix/theme/app_theme.dart';
import 'package:agenix/services/google_sign_in_error.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application theme exposes the expected visual defaults', () {
    final theme = AppTheme.build();

    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.textTheme.bodyLarge?.fontFamily, 'Montserrat');
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.iOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.windows],
      isA<FadeUpwardsPageTransitionsBuilder>(),
    );
  });

  test('explains Android Google Sign-In configuration errors', () {
    final error = PlatformException(
      code: 'sign_in_failed',
      message: 'com.google.android.gms.common.api.ApiException: 10',
    );

    expect(
      googleSignInErrorMessage(error),
      contains('Firebase Console'),
    );
  });
}
