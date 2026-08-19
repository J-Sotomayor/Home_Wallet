import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_shapes.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static const lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primaryBlue,
    onPrimary: AppColors.ink,
    primaryContainer: AppColors.blueContainer,
    onPrimaryContainer: AppColors.primaryBlueDark,
    secondary: AppColors.lavender,
    onSecondary: AppColors.ink,
    secondaryContainer: AppColors.paleLavender,
    onSecondaryContainer: AppColors.deepLavender,
    tertiary: AppColors.peach,
    onTertiary: AppColors.ink,
    tertiaryContainer: AppColors.coral,
    onTertiaryContainer: AppColors.ink,
    error: AppColors.expenseRed,
    onError: AppColors.white,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.expenseRed,
    surface: AppColors.offWhite,
    onSurface: AppColors.darkGray,
    surfaceContainerHighest: AppColors.lightGray,
    onSurfaceVariant: AppColors.mediumGray,
    outline: AppColors.borderGray,
    outlineVariant: AppColors.borderGray,
    shadow: AppColors.darkGray,
    scrim: AppColors.darkGray,
    inverseSurface: AppColors.ink,
    onInverseSurface: AppColors.offWhite,
    inversePrimary: AppColors.darkPrimary,
    surfaceTint: AppColors.primaryBlue,
  );

  static const darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.ink,
    primaryContainer: AppColors.deepMint,
    onPrimaryContainer: AppColors.offWhite,
    secondary: AppColors.darkBlushPink,
    onSecondary: AppColors.ink,
    secondaryContainer: AppColors.deepLavender,
    onSecondaryContainer: AppColors.darkTextPrimary,
    tertiary: AppColors.peach,
    onTertiary: AppColors.ink,
    tertiaryContainer: AppColors.deepCoral,
    onTertiaryContainer: AppColors.offWhite,
    error: AppColors.darkError,
    onError: AppColors.darkBackground,
    errorContainer: AppColors.deepCoral,
    onErrorContainer: AppColors.offWhite,
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkTextPrimary,
    surfaceContainerHighest: AppColors.darkElevatedSurface,
    onSurfaceVariant: AppColors.darkTextSecondary,
    outline: AppColors.neutralGray,
    outlineVariant: AppColors.ink,
    shadow: AppColors.darkBackground,
    scrim: AppColors.darkBackground,
    inverseSurface: AppColors.darkTextPrimary,
    onInverseSurface: AppColors.darkGray,
    inversePrimary: AppColors.deepMint,
    surfaceTint: AppColors.darkPrimary,
  );

  static ThemeData get light => _build(lightColorScheme, AppColors.cream);
  static ThemeData get dark =>
      _build(darkColorScheme, AppColors.darkBackground);

  static ThemeData _build(ColorScheme scheme, Color scaffoldBackground) {
    final isLight = scheme.brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
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
        color: isLight ? scheme.surface : AppColors.darkElevatedSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: AppShapes.card(),
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
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainerHighest,
        checkmarkColor: scheme.primary,
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected)
                    ? scheme.primaryContainer
                    : scheme.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected)
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
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
            fontSize: 10.5,
            height: 1,
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? scheme.onPrimary
                  : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.surfaceContainerHighest,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? scheme.primary
                  : AppColors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: .28),
        selectionHandleColor: scheme.primary,
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
