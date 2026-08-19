import 'package:flutter/material.dart';

abstract final class AppColors {
  // Paleta oficial HomeWallet de las referencias de marca.
  static const mint = Color(0xFF8FC9C2);
  static const paleMint = Color(0xFFDDEFEA);
  static const lavender = Color(0xFFA98CC8);
  static const paleLavender = Color(0xFFE8E0F0);
  static const peach = Color(0xFFE7B28F);
  static const coral = Color(0xFFF3C5B8);
  static const gold = Color(0xFFEBCB8B);
  static const cream = Color(0xFFF7F1EA);
  static const offWhite = Color(0xFFFAFAF8);
  static const ink = Color(0xFF292B2E);
  static const neutralGray = Color(0xFF777A7D);
  static const warmGray = Color(0xFFE8E6E2);

  // Variantes de contraste para texto, estados y superficies oscuras.
  static const deepMint = Color(0xFF3F706B);
  static const deepLavender = Color(0xFF6D587E);
  static const deepCoral = Color(0xFF9B5049);
  static const darkBackground = Color(0xFF101214);
  static const darkSurface = Color(0xFF181A1C);
  static const darkElevatedSurface = Color(0xFF232628);
  static const darkTextPrimary = Color(0xFFFAFAF8);
  static const darkTextSecondary = Color(0xFFE8E6E2);

  // Alias semánticos conservados para las pantallas existentes.
  static const primaryBlue = mint;
  static const primaryBlueDark = deepMint;
  static const savingsGreen = mint;
  static const accessibleGreen = deepMint;
  static const white = offWhite;
  static const darkGray = ink;
  static const mediumGray = neutralGray;
  static const lightGray = cream;
  static const borderGray = warmGray;
  static const blushPink = lavender;
  static const blushPinkLight = paleLavender;
  static const blushPinkDark = deepLavender;
  static const expenseRed = deepCoral;
  static const warningAmber = Color(0xFF8A651A);
  static const successContainer = paleMint;
  static const errorContainer = coral;
  static const warningContainer = gold;
  static const blueContainer = paleMint;
  static const pinkContainer = paleLavender;

  // Identidad para modo oscuro.
  static const darkPrimary = mint;
  static const darkSavingsGreen = mint;
  static const darkBlushPink = lavender;
  static const darkError = coral;
  static const darkWarning = gold;

  static const transparent = Color(0x00000000);
  static const whiteMuted = Color(0xCCFAFAF8);
  static const whiteOverlay = Color(0x24FAFAF8);
  static const primaryShadow = Color(0x338FC9C2);
}
