# Evidencia de branding

Fecha: 2026-07-31  
Host de compilación: Windows, zona `America/Guayaquil`  
AVD: `Pixel_7_Pro`  
Modelo: `sdk_gphone16k_x86_64`  
Android: 17 / API 37  
Paquete: `com.homewallet.app`  
Versión: `1.0.0` (`versionCode` 1; `minSdk` 23; `targetSdk` 36)

## Resultado automatizado

| Comprobación | Resultado |
|---|---|
| `python tool/generate_brand_assets.py` | PNG y recursos nativos regenerados desde SVG |
| `dart run flutter_launcher_icons` | Legacy, adaptativo, round, iOS y monocromático generados |
| `dart run flutter_native_splash:create` | Splash claro, oscuro y Android 12+ generado |
| `dart format .` | Correcto |
| `flutter analyze` | Sin problemas |
| `flutter test` | 7/7 |
| `flutter build apk --release` | 77.394.392 bytes |
| `flutter build appbundle --release` | 42.091.818 bytes |
| Instalación ADB | Correcta |
| AppIcon iOS | 25 entradas, dimensiones correctas y PNG 1024 opaco |
| Colores en widgets | Sin literales hex fuera de los tokens de tema |

## Artefactos

| Archivo | SHA-256 |
|---|---|
| `build/app/outputs/flutter-apk/app-release.apk` | `1A58D4BCB2781774DBA9C8E5493275793AD49C3C452A0F102166A47714A15210` |
| `build/app/outputs/bundle/release/app-release.aab` | `326DAF84947945C5B58159728594D963366466D0ED8198F17DDD5DABB465C13C` |

El manifiesto compilado declara HomeWallet, icono normal/redondo, `minSdk 23` y `targetSdk 36`. El AAB contiene mdpi–xxxhdpi, adaptive/round/monochrome, splash y activos Flutter de marca. No solicita `AD_ID` ni servicios de atribución.

La firma local pasó la validación v1/v2, pero corresponde a `CN=Android Debug`. Los binarios verifican compilación e instalación; deben volver a firmarse con el keystore privado de producción antes de publicar.

## Capturas Android

Las 11 capturas existentes en esta carpeta prueban icono a color/temático, splash claro/oscuro, login, registro, dashboard, selector de tema y Acerca de. Todas proceden del APK release instalado. La evidencia adicional de la versión sin datos quemados está en `docs/evidence/security_release/`.

## iOS

`AppIcon.appiconset` y el splash se verificaron estáticamente en Windows. Build, simulador, dispositivo y capturas iOS requieren macOS y no se declaran ejecutados.

