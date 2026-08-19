import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/app/theme/app_colors.dart';
import 'package:homewallet/app/theme/app_theme.dart';

void main() {
  test('official HomeWallet palette keeps the approved HEX values', () {
    expect(AppColors.mint, const Color(0xFF8FC9C2));
    expect(AppColors.paleMint, const Color(0xFFDDEFEA));
    expect(AppColors.lavender, const Color(0xFFA98CC8));
    expect(AppColors.paleLavender, const Color(0xFFE8E0F0));
    expect(AppColors.peach, const Color(0xFFE7B28F));
    expect(AppColors.coral, const Color(0xFFF3C5B8));
    expect(AppColors.gold, const Color(0xFFEBCB8B));
    expect(AppColors.cream, const Color(0xFFF7F1EA));
    expect(AppColors.offWhite, const Color(0xFFFAFAF8));
    expect(AppColors.ink, const Color(0xFF292B2E));
    expect(AppColors.neutralGray, const Color(0xFF777A7D));
    expect(AppColors.warmGray, const Color(0xFFE8E6E2));
  });

  test('light and dark themes use the HomeWallet brand hierarchy', () {
    expect(AppTheme.light.scaffoldBackgroundColor, AppColors.cream);
    expect(AppTheme.light.colorScheme.primary, AppColors.mint);
    expect(AppTheme.light.colorScheme.secondary, AppColors.lavender);
    expect(AppTheme.light.colorScheme.tertiary, AppColors.peach);
    expect(AppTheme.light.colorScheme.onSurface, AppColors.ink);

    expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.darkBackground);
    expect(AppTheme.dark.colorScheme.primary, AppColors.mint);
    expect(AppTheme.dark.colorScheme.secondary, AppColors.lavender);
    expect(AppTheme.dark.colorScheme.tertiary, AppColors.peach);
    expect(AppTheme.dark.colorScheme.onSurface, AppColors.offWhite);
  });
}
