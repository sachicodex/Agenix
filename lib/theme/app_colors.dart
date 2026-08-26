import 'package:flutter/material.dart';

class AppColors {
  // Brand dark-mode palette
  static const Color primary = Color(0xFFF97015); // Brand
  static const Color secondary = Color(0xFFFFA04D); // Highlight - still not use
  static const Color background = Color(0XFF020202); // Dark background
  static const Color surface = Color(0XFF161616); // Dark surface
  static const Color gradientMix = Color(0xFFFF9500); // Border and divider
  static const Color error = Color(0xFFCB4B0B); // Emphasis
  static const Color onPrimary = Color(
    0xFF1A1614,
  ); // Dark text on orange button
  static const Color onBackground = Color(0xFFf4f4f5); // Light text on dark
  static const Color onSurface = Color(0xFFd4d4d8); // Secondary light text
  static const Color onTertiary = Color(0xFFa1a1aa);

  // Supporting UI colors
  static const Color borderColor = Color(0XFF2a2a2a);
  static const Color borderFocusColor = Color(0XFF3a3a3a);
  static const Color dividerColor = Color(0xFF1F242C);
  static const Color selectedColor = Color(
    0x33F97015,
  ); // Brand with low opacity
  /// Primary time-axis labels (hour marks).
  static const Color timeTextColor = onSurface;

  /// Secondary time-axis labels (15/30/5-minute marks).
  static const Color timeTextSecondaryColor = onTertiary;

  // Primary action button gradient (135deg-like diagonal)
  static const LinearGradient primaryActionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, gradientMix],
  );

  static const LinearGradient primaryActionGradientDisabled = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x99F97015), Color(0x99FF9500)],
  );
}

class AppTextStyles {
  static const TextStyle headline1 = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: AppColors.onBackground,
  );
  static const TextStyle headline2 = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
    letterSpacing: 1.1,
  );
    static const TextStyle headline3 = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
    letterSpacing: 1.1,
  );
  static const TextStyle bodyText1 = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 16,
    color: AppColors.onBackground,
  );
  static const TextStyle button = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onPrimary,
  );
  // Add more text styles as needed
}
