import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/app/widgets/homewallet_logo.dart';

void main() {
  testWidgets('uses the stacked light and dark logo variants', (tester) async {
    Future<String> assetFor(Brightness brightness) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          home: const Scaffold(body: HomeWalletLogo()),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      return (image.image as AssetImage).assetName;
    }

    expect(
      await assetFor(Brightness.light),
      'assets/branding/generated/logo_stacked_light.png',
    );
    expect(
      await assetFor(Brightness.dark),
      'assets/branding/generated/logo_stacked_dark.png',
    );
  });

  testWidgets('shows the full brand before revealing startup content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeWalletStartupGate(
          minimumDisplayTime: Duration(milliseconds: 700),
          child: Text('Acceso listo'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('brand-loading')), findsOneWidget);
    expect(find.text('Acceso listo'), findsNothing);
    expect(find.byType(HomeWalletLogo), findsOneWidget);

    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Acceso listo').evaluate().isNotEmpty) break;
    }
    expect(find.text('Acceso listo'), findsOneWidget);
  });
}
