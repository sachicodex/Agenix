import 'package:flutter/material.dart';

class AppColors {
  // Brand dark-mode palette
  static const Color primary = Color(0xFFF97015); // Brand
  static const Color secondary = Color(0xFFFFA04D); // Highlight
  static const Color background = Color(0xFF1A1614); // Dark background
  static const Color surface = Color(0xFF252220); // Dark surface
  static const Color error = Color(0xFFCB4B0B); // Emphasis
  static const Color onPrimary = Color(
    0xFF1A1614,
  ); // Dark text on orange button
  static const Color onBackground = Color(0xFFFAF9F7); // Light text on dark
  static const Color onSurface = Color(0xFFE7E1DC); // Secondary light text
  static const Color onError = Color(0xFFFFFFFF);

  // Supporting UI colors
  static const Color borderColor = Color(0xFF3B322E);
  static const Color dividerColor = Color(0xFF332C28);
  static const Color hoverColor = Color(0x33252220); // Surface with low opacity
  static const Color selectedColor = Color(
    0x33F97015,
  ); // Brand with low opacity
  static const Color timeTextColor = Color(0xFFC2B8B1);

  // Event colors (kept varied while aligned with warm dark UI)
  static const List<Color> eventColors = [
    Color(0xFFF97015), // Brand orange
    Color(0xFFFFA04D), // Highlight orange
    Color(0xFFCB4B0B), // Emphasis orange
    Color(0xFFFF7729), // Hover orange
    Color(0xFFE67E22), // Amber
    Color(0xFFD35400), // Deep orange
    Color(0xFF16A085), // Teal
    Color(0xFF2E86C1), // Blue
    Color(0xFF8E44AD), // Purple
    Color(0xFF27AE60), // Green
    Color(0xFFC0392B), // Red
  ];
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
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
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
