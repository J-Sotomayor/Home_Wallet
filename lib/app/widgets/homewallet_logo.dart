import 'dart:async';

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
            ? 'assets/branding/generated/logo_stacked_dark.png'
            : 'assets/branding/generated/logo_stacked_light.png',
        width: width,
        height: height,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// Branded waiting state shown immediately after the native launch screen.
class HomeWalletLoadingView extends StatelessWidget {
  const HomeWalletLoadingView({
    super.key,
    this.message = 'Preparando tu espacio',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Semantics(
            container: true,
            liveRegion: true,
            label: '$message. Cargando.',
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.94, end: 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(scale: value, child: child),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HomeWalletLogo(width: 300, height: 300),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: scheme.primary,
                      backgroundColor: scheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the full brand visible briefly after Android/iOS hand off to Flutter.
class HomeWalletStartupGate extends StatefulWidget {
  const HomeWalletStartupGate({
    super.key,
    required this.child,
    this.minimumDisplayTime = const Duration(milliseconds: 1000),
  });

  final Widget child;
  final Duration minimumDisplayTime;

  @override
  State<HomeWalletStartupGate> createState() => _HomeWalletStartupGateState();
}

class _HomeWalletStartupGateState extends State<HomeWalletStartupGate> {
  Timer? _timer;
  bool _precacheStarted = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.minimumDisplayTime, () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precacheStarted) return;
    _precacheStarted = true;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final asset = AssetImage(
      dark
          ? 'assets/branding/generated/logo_stacked_dark.png'
          : 'assets/branding/generated/logo_stacked_light.png',
    );
    unawaited(
      precacheImage(asset, context).catchError((_) {
        // In test/unit environments the image cache warm-up can fail or be delayed.
        // The startup splash visibility should remain driven by the minimum display
        // timeout; pre-caching is best-effort.
      }),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return const Scaffold(
      key: ValueKey('brand-loading'),
      body: HomeWalletLoadingView(message: 'Preparando HomeWallet'),
    );
  }
}
