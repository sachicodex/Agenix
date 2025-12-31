import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF1976D2);
  static const Color primaryVariant = Color(0xFF1565C0);
  static const Color secondary = Color(0xFFFFA000);
  static const Color secondaryVariant = Color(0xFFFF8F00);
  static const Color background = Color(0xFF181A20); // dark background
  static const Color surface = Color(0xFF23262F); // dark card/surface
  static const Color error = Color(0xFFD32F2F);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFF181A20);
  static const Color onBackground = Color(0xFFF5F5F5); // light text on dark
  static const Color onSurface = Color(0xFFD1D5DB); // light text on surface
  static const Color onError = Color(0xFFFFFFFF);
  // Add more custom colors as needed
}

class AppTextStyles {
  static const TextStyle headline1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: AppColors.onBackground,
  );
  static const TextStyle headline2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
  );
  static const TextStyle bodyText1 = TextStyle(
    fontSize: 16,
    color: AppColors.onBackground,
  );
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onPrimary,
  );
  // Add more text styles as needed
}
