import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_shapes.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static const lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primaryBlue,
    onPrimary: AppColors.white,
    primaryContainer: AppColors.blueContainer,
    onPrimaryContainer: AppColors.primaryBlueDark,
    secondary: AppColors.savingsGreen,
    onSecondary: AppColors.darkGray,
    secondaryContainer: AppColors.successContainer,
    onSecondaryContainer: AppColors.accessibleGreen,
    tertiary: AppColors.blushPink,
    onTertiary: AppColors.darkGray,
    tertiaryContainer: AppColors.pinkContainer,
    onTertiaryContainer: AppColors.blushPinkDark,
    error: AppColors.expenseRed,
    onError: AppColors.white,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.expenseRed,
    surface: AppColors.white,
    onSurface: AppColors.darkGray,
    surfaceContainerHighest: AppColors.lightGray,
    onSurfaceVariant: AppColors.mediumGray,
    outline: AppColors.borderGray,
    outlineVariant: AppColors.borderGray,
    shadow: AppColors.darkGray,
    scrim: AppColors.darkGray,
    inverseSurface: AppColors.darkGray,
    onInverseSurface: AppColors.white,
    inversePrimary: AppColors.darkPrimary,
    surfaceTint: AppColors.primaryBlue,
  );

  static const darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.darkBackground,
    primaryContainer: AppColors.primaryBlueDark,
    onPrimaryContainer: AppColors.darkTextPrimary,
    secondary: AppColors.darkSavingsGreen,
    onSecondary: AppColors.darkBackground,
    secondaryContainer: AppColors.accessibleGreen,
    onSecondaryContainer: AppColors.darkTextPrimary,
    tertiary: AppColors.darkBlushPink,
    onTertiary: AppColors.darkBackground,
    tertiaryContainer: AppColors.blushPinkDark,
    onTertiaryContainer: AppColors.darkTextPrimary,
    error: AppColors.darkError,
    onError: AppColors.darkBackground,
    errorContainer: AppColors.expenseRed,
    onErrorContainer: AppColors.darkTextPrimary,
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkTextPrimary,
    surfaceContainerHighest: AppColors.darkElevatedSurface,
    onSurfaceVariant: AppColors.darkTextSecondary,
    outline: AppColors.mediumGray,
    outlineVariant: AppColors.darkElevatedSurface,
    shadow: AppColors.darkBackground,
    scrim: AppColors.darkBackground,
    inverseSurface: AppColors.darkTextPrimary,
    onInverseSurface: AppColors.darkGray,
    inversePrimary: AppColors.primaryBlueDark,
    surfaceTint: AppColors.darkPrimary,
  );

  static ThemeData get light => _build(lightColorScheme, AppColors.lightGray);
  static ThemeData get dark =>
      _build(darkColorScheme, AppColors.darkBackground);

  static ThemeData _build(ColorScheme scheme, Color scaffoldBackground) {
    final isLight = scheme.brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: AppTypography.textTheme(scheme.brightness),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: AppColors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: AppShapes.card(borderColor: scheme.outlineVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? AppColors.white : AppColors.darkSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: const OutlineInputBorder(borderRadius: AppShapes.mediumRadius),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppShapes.mediumRadius,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppShapes.mediumRadius,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppShapes.mediumRadius,
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppShapes.mediumRadius),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed) && isLight) {
              return AppColors.primaryBlueDark;
            }
            return scheme.primary;
          }),
          foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color:
                states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color:
                states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      dividerColor: scheme.outlineVariant,
    );
  }
}
