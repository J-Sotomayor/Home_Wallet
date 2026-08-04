import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum HomeWalletLogoVariant { symbol, horizontal }

class HomeWalletLogo extends StatelessWidget {
  const HomeWalletLogo({
    super.key,
    this.variant = HomeWalletLogoVariant.horizontal,
    this.width,
    this.height,
    this.semanticLabel = 'HomeWallet',
  });

  final HomeWalletLogoVariant variant;
  final double? width;
  final double? height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: switch (variant) {
        HomeWalletLogoVariant.symbol => SvgPicture.asset(
          'assets/branding/homewallet_app_icon.svg',
          width: width,
          height: height,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
        HomeWalletLogoVariant.horizontal => Image.asset(
          dark
              ? 'assets/branding/generated/logo_white.png'
              : 'assets/branding/generated/logo_horizontal.png',
          width: width,
          height: height,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      },
    );
  }
}
