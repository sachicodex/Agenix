import 'package:flutter/material.dart';

class AppColors {
  // Google Calendar color scheme
  static const Color primary = Color(0xFF1A73E8); // Google Blue
  static const Color secondary = Color(0xFF34A853); // Google Green
  static const Color background = Color(0xFFFFFFFF); // White background (light mode)
  static const Color surface = Color(0xFFFAFAFA); // Light gray surface
  static const Color error = Color(0xFFEA4335); // Google Red
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onBackground = Color(0xFF202124); // Dark text on light
  static const Color onSurface = Color(0xFF5F6368); // Gray text
  static const Color onError = Color(0xFFFFFFFF);
  
  // Google Calendar specific colors
  static const Color borderColor = Color(0xFFDADCE0); // Light gray border
  static const Color dividerColor = Color(0xFFE8EAED); // Divider color
  static const Color hoverColor = Color(0xFFF1F3F4); // Hover state
  static const Color selectedColor = Color(0xFFE8F0FE); // Selected state (light blue)
  static const Color timeTextColor = Color(0xFF5F6368); // Time label color
  
  // Google Calendar event colors (matching Google's palette)
  static const List<Color> eventColors = [
    Color(0xFF7986CB), // Lavender
    Color(0xFF33B679), // Green
    Color(0xFF8E24AA), // Purple
    Color(0xFFE67C73), // Red
    Color(0xFFF6BF26), // Yellow
    Color(0xFFF4511E), // Orange
    Color(0xFF039BE5), // Blue
    Color(0xFF0097A7), // Teal
    Color(0xFFAD1457), // Pink
    Color(0xFF616161), // Grey
    Color(0xFF795548), // Brown
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
