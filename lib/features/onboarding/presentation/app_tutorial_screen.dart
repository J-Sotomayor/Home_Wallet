import 'package:flutter/material.dart';

class AppTutorialScreen extends StatefulWidget {
  const AppTutorialScreen({super.key, required this.onFinished});

  final Future<void> Function() onFinished;

  @override
  State<AppTutorialScreen> createState() => _AppTutorialScreenState();
}

class _AppTutorialScreenState extends State<AppTutorialScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _busy = false;

  static const _steps = <_TutorialStep>[
    _TutorialStep(
      Icons.home_outlined,
      'Tu resumen',
      'En Inicio verás el dinero disponible, lo apartado para ahorrar y la actividad reciente del hogar.',
    ),
    _TutorialStep(
      Icons.receipt_long_outlined,
      'Registra movimientos',
      'Añade ingresos, gastos o ahorros. Puedes indicar quién pagó y repartir gastos compartidos.',
    ),
    _TutorialStep(
      Icons.savings_outlined,
      'Construye tus ahorros',
      'Consulta lo que has apartado, sigue tus metas y registra un nuevo ahorro desde su propia pestaña.',
    ),
    _TutorialStep(
      Icons.query_stats_outlined,
      'Entiende tus reportes',
      'Filtra por fecha, categoría o integrante y exporta únicamente los datos que necesites.',
    ),
    _TutorialStep(
      Icons.tune_outlined,
      'Hazla tuya',
      'Desde Perfil puedes gestionar categorías, importar estados bancarios y volver a abrir este tutorial.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conoce HomeWallet'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _busy ? null : _finish,
            child: const Text('Saltar'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 76,
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(
                            step.icon,
                            size: 76,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          step.description,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Text(
              '${_index + 1} de ${_steps.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
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
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                  icon: Icon(last ? Icons.check : Icons.arrow_forward),
                  label: Text(last ? 'Listo, empezar' : 'Siguiente'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onFinished();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _TutorialStep {
  const _TutorialStep(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
}
