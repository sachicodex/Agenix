import 'package:flutter/cupertino.dart';
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
  static const emphasizedCurve = Curves.easeOutCubic;
}

class AppGradients {
  static const LinearGradient secondaryActionButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2A2A2A), Color(0xFF1E1E1E)],
  );
}

class AppButtonStyles {
  static const BorderRadius secondaryActionRadius = BorderRadius.all(
    Radius.circular(16),
  );
  static const EdgeInsets secondaryActionPadding = EdgeInsets.symmetric(
    horizontal: 16,
  );
  static const double secondaryActionIconSize = 23;
  static const TextStyle secondaryActionLabel = TextStyle(
    fontFamily: 'Montserrat',
    color: AppColors.onSurface,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.onPrimary,
        onSurface: AppColors.onSurface,
        onError: AppColors.onTertiary,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      fontFamily: 'Montserrat',
      textTheme: TextTheme(
        displayLarge: AppTextStyles.headline1,
        displayMedium: AppTextStyles.headline2,
        bodyLarge: AppTextStyles.bodyText1,
        labelLarge: AppTextStyles.button,
      ),
    );

    final appTextTheme = base.textTheme.apply(
      fontFamily: 'Montserrat',
      bodyColor: AppColors.onBackground,
      displayColor: AppColors.onBackground,
    );

    return base.copyWith(
      textTheme: appTextTheme,
      primaryTextTheme: appTextTheme,
      cardTheme: base.cardTheme.copyWith(
        color: AppColors.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.borderColor),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(fontFamily: 'Montserrat'),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(
            color: AppColors.borderFocusColor,
            width: 1.2,
          ),
        ),
        hintStyle: TextStyle(
          fontFamily: 'Montserrat',
          color: AppColors.onSurface.withValues(alpha: 0.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          animationDuration: AppMotion.short,
          textStyle: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          minimumSize: const Size(120, 44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onBackground,
          animationDuration: AppMotion.short,
          textStyle: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w600,
          ),
          side: const BorderSide(color: AppColors.borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          animationDuration: AppMotion.short,
          textStyle: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(animationDuration: AppMotion.short),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return AppColors.onSurface.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.onSurface.withValues(alpha: 0.45);
          }
          return AppColors.onSurface.withValues(alpha: 0.28);
        }),
        thickness: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) return 5.0;
          if (states.contains(WidgetState.hovered)) return 4.0;
          return 3.0;
        }),
        radius: const Radius.circular(999),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        minThumbLength: 36,
        trackVisibility: const WidgetStatePropertyAll(false),
      ),
      dividerColor: AppColors.dividerColor,
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontFamily: 'Montserrat',
          color: AppColors.onBackground,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Montserrat',
          color: AppColors.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: AppTextStyles.bodyText1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.fixed,
        backgroundColor: AppColors.surface,
        contentTextStyle: AppTextStyles.bodyText1.copyWith(
          color: AppColors.onBackground,
        ),

        actionTextColor: AppColors.primary,
        elevation: 6,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.headline2,
        toolbarTextStyle: AppTextStyles.bodyText1,
      ),
    );
  }
}
