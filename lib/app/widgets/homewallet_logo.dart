import 'package:flutter/material.dart';

class HomeWalletLogo extends StatelessWidget {
  const HomeWalletLogo({
    super.key,
    this.width,
    this.height,
    this.semanticLabel = 'HomeWallet',
  });

  final double? width;
  final double? height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: Image.asset(
        dark
            ? 'assets/branding/generated/logo_white.png'
            : 'assets/branding/generated/logo_horizontal.png',
        width: width,
        height: height,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}
