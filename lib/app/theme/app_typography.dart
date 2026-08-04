import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static TextTheme textTheme(Brightness brightness) {
    final primary =
        brightness == Brightness.light
            ? AppColors.darkGray
            : AppColors.darkTextPrimary;
    final secondary =
        brightness == Brightness.light
            ? AppColors.mediumGray
            : AppColors.darkTextSecondary;

    return TextTheme(
      displaySmall: TextStyle(
        color: primary,
        fontSize: 36,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineLarge: TextStyle(
        color: primary,
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      headlineMedium: TextStyle(
        color: primary,
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: TextStyle(
        color: primary,
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: primary,
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: primary, fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(color: primary, fontSize: 14, height: 1.45),
      bodySmall: TextStyle(color: secondary, fontSize: 12, height: 1.4),
      labelLarge: TextStyle(
        color: primary,
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        color: secondary,
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
