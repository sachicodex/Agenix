import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppRadius {
  static const card = 16.0;
  static const control = 12.0;
}

class AppMotion {
  static const short = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const long = Duration(milliseconds: 400);
}

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        background: AppColors.background,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.onPrimary,
        onBackground: AppColors.onBackground,
        onSurface: AppColors.onSurface,
        onError: AppColors.onError,
        brightness: Brightness.light, // Google Calendar uses light mode
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Montserrat',
      textTheme: TextTheme(
        displayLarge: AppTextStyles.headline1,
        displayMedium: AppTextStyles.headline2,
        bodyLarge: AppTextStyles.bodyText1,
        labelLarge: AppTextStyles.button,
      ),
    );

    return base.copyWith(
      cardTheme: base.cardTheme.copyWith(
        color: AppColors.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: AppColors.onSurface.withOpacity(0.6)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          minimumSize: const Size(120, 44),
        ),
      ),
      dividerColor: AppColors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.headline2,
        toolbarTextStyle: AppTextStyles.bodyText1,
      ),
    );
  }
}
