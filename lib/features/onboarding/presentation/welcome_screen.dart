import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/widgets/homewallet_logo.dart';

class FirstLaunchGate extends StatefulWidget {
  const FirstLaunchGate({super.key, required this.child});

  final Widget child;

  @override
  State<FirstLaunchGate> createState() => _FirstLaunchGateState();
}

class _FirstLaunchGateState extends State<FirstLaunchGate> {
  static const _key = 'welcome.completed.v1';
  bool? _completed;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((preferences) {
      if (mounted) {
        setState(() => _completed = preferences.getBool(_key) ?? false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_completed == null) {
      return const Scaffold(body: HomeWalletLoadingView());
    }
    if (_completed!) return widget.child;
    return WelcomeScreen(
      onFinished: () async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setBool(_key, true);
        if (mounted) setState(() => _completed = true);
      },
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinished});

  final Future<void> Function() onFinished;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _busy = false;

  static const _pages = <_WelcomePageData>[
    _WelcomePageData(
      icon: Icons.family_restroom,
      title: 'Toma el control de tu espacio',
      description:
          'Organiza ingresos, gastos y pagos de tu espacio desde un solo lugar.',
      accent: AppColors.blushPinkDark,
    ),
    _WelcomePageData(
      icon: Icons.savings_outlined,
      title: 'Ahorren para lo que importa',
      description:
          'Aparten dinero, creen metas compartidas y sigan el avance juntos.',
      accent: AppColors.primaryBlue,
    ),
    _WelcomePageData(
      icon: Icons.shield_outlined,
      title: 'Seguro y confiable',
      description:
          'La información sensible del espacio se guarda cifrada y con permisos por integrante.',
      accent: AppColors.deepMint,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return PopScope<void>(
      canPop: !_busy && _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && _page > 0) _previousPage();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                child: Row(
                  children: [
                    const HomeWalletLogo(width: 110, height: 100),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : _finish,
                      child: const Text('Saltar'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (value) => setState(() => _page = value),
                  itemBuilder:
                      (context, index) => _WelcomePage(data: _pages[index]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: index == _page ? 22 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color:
                          index == _page
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _busy
                            ? null
                            : () {
                              if (last) {
                                _finish();
                              } else {
                                _controller.nextPage(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOut,
                                );
                              }
                            },
                    icon: Icon(last ? Icons.login : Icons.arrow_forward),
                    label: Text(last ? 'Empezar' : 'Siguiente'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _previousPage() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    await widget.onFinished();
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.data});

  final _WelcomePageData data;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 230,
          height: 230,
          decoration: BoxDecoration(
            color: data.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(42),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(data.icon, size: 112, color: data.accent),
              Positioned(
                right: 24,
                bottom: 24,
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: Icon(Icons.home_outlined, color: data.accent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 38),
        Text(
          data.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          data.description,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    ),
  );
}

class _WelcomePageData {
  const _WelcomePageData({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accent;
}
