import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFD99A00);
  static const Color secondary = Color(0xFFFFA000);
  static const Color background = Color(0xFF030303); // dark background
  static const Color surface = Color(0xFF161616); // dark card/surface
  static const Color error = Color(0xFFD32F2F);
  static const Color onPrimary = Color(0xFF0F172A);
  static const Color onBackground = Color(0xFFF5F5F5); // light text on dark
  static const Color onSurface = Color(0xFFD1D5DB); // light text on surface
  static const Color onError = Color(0xFFFFFFFF);
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
