import 'package:flutter/material.dart';

class AppColors {
  // Calendar palette
  static const Color crimsonRed = Color(0xFFE63946);
  static const Color coralPink = Color(0xFFFF6B6B);
  static const Color deepRose = Color(0xFFD62828);
  static const Color hotMagenta = Color(0xFFE01E5A);
  static const Color softPink = Color(0xFFF472B6);
  static const Color vibrantPurple = Color(0xFF9D4EDD);
  static const Color electricViolet = Color(0xFF7209B7);
  static const Color deepLavender = Color(0xFF8B5CF6);
  static const Color royalBlue = Color(0xFF2563EB);
  static const Color skyBlue = Color(0xFF00B4D8);
  static const Color cyanTeal = Color(0xFF06B6D4);
  static const Color darkTeal = Color(0xFF0077B6);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color mintGreen = Color(0xFF2EC4B6);
  static const Color limeGreen = Color(0xFF84CC16);
  static const Color oliveGreen = Color(0xFF65A30D);
  static const Color brightYellow = Color(0xFFEAB308);
  static const Color warmAmber = Color(0xFFF59E0B);
  static const Color deepOrange = Color(0xFFF97316);
  static const Color burntOrange = Color(0xFFE65100);
  static const Color terracotta = Color(0xFFC05621);
  static const Color warmBrown = Color(0xFFA16207);
  static const Color slateBlue = Color(0xFF64748B);
  static const Color coolGray = Color(0xFF94A3B8);

  static const List<Color> calendarPalette = [
    crimsonRed,
    coralPink,
    deepRose,
    hotMagenta,
    softPink,
    vibrantPurple,
    electricViolet,
    deepLavender,
    royalBlue,
    skyBlue,
    cyanTeal,
    darkTeal,
    emeraldGreen,
    mintGreen,
    limeGreen,
    oliveGreen,
    brightYellow,
    warmAmber,
    deepOrange,
    burntOrange,
    terracotta,
    warmBrown,
    slateBlue,
    coolGray,
  ];

  // Brand dark-mode palette
  static const Color primary = Color(0xFFC8F902); // Brand
  static const Color secondary = Color(0xFFA0C702); // Highlight - still not use
  static const Color background = Color(0XFF020202); // Dark background
  static const Color card = Color(0XFF101010); // Dark surface
  static const Color surface = Color(0XFF161616); // Dark surface
  static const Color gradientMix = Color(0xFFA0C702); // Border and divider
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444); // Emphasis
  static const Color onPrimary = Color(
    0xFF1A1614,
  ); // Dark text on the brand button
  static const Color onBackground = Color(0xFFf4f4f5); // Light text on dark
  static const Color onSurface = Color(0xFFd4d4d8); // Secondary light text
  static const Color onTertiary = Color(0xFFa1a1aa);

  // Supporting UI colors
  static const Color borderColor = Color(0XFF2a2a2a);
  static const Color borderFocusColor = Color(0XFF3a3a3a);
  static const Color dividerColor = Color(0xFF222222);
  static const Color selectedColor = Color(
    0x55789501,
  ); // Brand with low opacity
  /// Background used for keyboard-highlighted options in selectors.
  static const Color optionHighlightColor = Color.fromARGB(20, 255, 255, 255);

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
    colors: [Color(0x99C8F902), Color(0x99A0C702)],
  );
}

class AppTextStyles {
  static const TextStyle headline1 = TextStyle(
    fontFamily: 'GoogleSans',
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: AppColors.onBackground,
  );
  static const TextStyle headline2 = TextStyle(
    fontFamily: 'GoogleSans',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
  );
  static const TextStyle headline3 = TextStyle(
    fontFamily: 'GoogleSans',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
  );
  static const TextStyle bodyText1 = TextStyle(
    fontFamily: 'GoogleSans',
    fontSize: 16,
    color: AppColors.onBackground,
  );
  static const TextStyle button = TextStyle(
    fontFamily: 'GoogleSans',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onPrimary,
  );
  // Add more text styles as needed
}
