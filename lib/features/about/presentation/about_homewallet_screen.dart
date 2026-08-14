import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_shapes.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/widgets/homewallet_logo.dart';

class AboutHomeWalletScreen extends StatelessWidget {
  const AboutHomeWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de HomeWallet')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const Center(child: HomeWalletLogo(width: 300, height: 90)),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Un espacio organizado también se construye con decisiones financieras claras.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).brightness == Brightness.light
                      ? AppColors.blushPinkLight
                      : scheme.surfaceContainerHighest,
              borderRadius: AppShapes.largeRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nuestra marca',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'El techo representa el hogar; la forma redondeada, una billetera compartida; y la confirmación verde, el avance hacia una meta. El detalle rosa aporta cercanía familiar.',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.verified_user_outlined),
            title: Text('Privacidad desde el diseño'),
            subtitle: Text('Tu información financiera pertenece a tu espacio.'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.accessibility_new_outlined),
            title: Text('Accesibilidad'),
            subtitle: Text(
              'Color, texto e iconos trabajan juntos para comunicar estados.',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Versión 1.0.7',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
