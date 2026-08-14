import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/services/app_services.dart';
import 'app/theme/app_theme.dart';
import 'app/theme/theme_controller.dart';
import 'app/widgets/homewallet_logo.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/onboarding/presentation/welcome_screen.dart';
import 'firebase_options.dart';

// Directly distributed APKs are not installed by Google Play and therefore
// cannot be expected to produce a Play Integrity verdict on every device.
// Enable App Check only for builds distributed through a trusted channel.
const _enableAppCheck = bool.fromEnvironment(
  'HOMEWALLET_ENABLE_APP_CHECK',
  defaultValue: false,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _rememberFirstLaunch();
  Object? startupError;
  StackTrace? startupStack;
  AppServices? services;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        // HomeWallet requires a confirmed server connection for writes and
        // does not advertise or maintain an offline work queue.
        persistenceEnabled: false,
      );
      if (_enableAppCheck) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid:
              kDebugMode
                  ? const AndroidDebugProvider()
                  : const AndroidPlayIntegrityProvider(),
          providerApple:
              kDebugMode
                  ? const AppleDebugProvider()
                  : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      }
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
    services = AppServices.firebase();
    if (!kIsWeb) {
      try {
        await services.notifications?.initialize();
      } catch (error) {
        // Push notifications are optional and must never block authentication
        // on devices without compatible Google services.
        debugPrint('No se pudieron inicializar las notificaciones: $error');
      }
    }
  } catch (error, stack) {
    startupError = error;
    startupStack = stack;
  }

  final themeController = await ThemeController.load();
  runApp(
    HomeWalletApp(
      themeController: themeController,
      services: services,
      startupError: startupError,
      startupStack: startupStack,
    ),
  );
}

const appFirstLaunchPreferenceKey = 'homewallet.first_launch_at.v1';

Future<void> _rememberFirstLaunch() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    if (!preferences.containsKey(appFirstLaunchPreferenceKey)) {
      await preferences.setString(
        appFirstLaunchPreferenceKey,
        DateTime.now().toIso8601String(),
      );
    }
  } catch (_) {
    // La fecha mejora el filtro local, pero nunca debe impedir abrir la app.
  }
}

class HomeWalletApp extends StatefulWidget {
  const HomeWalletApp({
    super.key,
    required this.themeController,
    required this.services,
    this.startupError,
    this.startupStack,
  });

  final ThemeController themeController;
  final AppServices? services;
  final Object? startupError;
  final StackTrace? startupStack;

  @override
  State<HomeWalletApp> createState() => _HomeWalletAppState();
}

class _HomeWalletAppState extends State<HomeWalletApp> {
  @override
  void initState() {
    super.initState();
    widget.themeController.addListener(_themeChanged);
  }

  @override
  void dispose() {
    widget.themeController.removeListener(_themeChanged);
    super.dispose();
  }

  void _themeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HomeWallet',
      locale: const Locale('es', 'EC'),
      supportedLocales: const [Locale('es', 'EC'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Theme.of(context).colorScheme.surface,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: widget.themeController.themeMode,
      home:
          widget.services == null
              ? StartupErrorScreen(error: widget.startupError)
              : FirstLaunchGate(
                child: AuthGate(
                  services: widget.services!,
                  themeController: widget.themeController,
                ),
              ),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  const HomeWalletLogo(width: 260, height: 78),
                  const SizedBox(height: 30),
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No se pudo iniciar HomeWallet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Revisa la conexión, la configuración Firebase y vuelve a abrir la aplicación.',
                    textAlign: TextAlign.center,
                  ),
                  if (kDebugMode && error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
