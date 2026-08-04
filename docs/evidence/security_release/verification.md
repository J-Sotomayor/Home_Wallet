# Evidencia de versión funcional y segura

Fecha: 2026-07-31  
Host: Windows, zona `America/Guayaquil`  
AVD: `Pixel_7_Pro`, Android 17 / API 37  
Paquete: `com.homewallet.app`, versión `1.0.0` (`versionCode` 1)

## Resultado

| Comprobación | Resultado |
|---|---|
| Datos o credenciales quemados en `lib/`, Android, iOS y Functions | Ninguno; solo texto informativo sobre iniciar sin datos demo |
| `dart format .` | Correcto |
| `flutter analyze` | Sin problemas |
| `flutter test` | 7/7 |
| Reglas Firestore en emulador | 5/5 |
| Functions TypeScript | Correcto |
| `npm audit --omit=dev` | 0 altos/críticos; 7 moderados transitivos documentados |
| Functions desplegadas | 3/3 `ACTIVE`, Gen 2, Node.js 22, `southamerica-west1` |
| Smoke test sin autenticación | HTTP 401 `UNAUTHENTICATED` |
| Reglas Firestore y Storage | Desplegadas en `homewallet-prod`; Storage deniega todo |
| Firebase App Check API | Habilitada; intercambio de token TECNO correcto, TTL 3600 s |
| Dispositivos debug App Check | `TECNO KJ7 desarrollo` y `Pixel 7 Pro AVD desarrollo`, secretos no expuestos |
| APK release | Compilado, instalado y ejecutado |
| AAB release | Compilado e inspeccionado |
| Manifiesto Android | `minSdk 23`, `targetSdk 36`, sin AD_ID ni HTTP claro |

## Artefactos

| Archivo | Tamaño | SHA-256 |
|---|---:|---|
| `build/app/outputs/flutter-apk/app-release.apk` | 77.394.392 bytes | `1A58D4BCB2781774DBA9C8E5493275793AD49C3C452A0F102166A47714A15210` |
| `build/app/outputs/bundle/release/app-release.aab` | 42.091.818 bytes | `326DAF84947945C5B58159728594D963366466D0ED8198F17DDD5DABB465C13C` |

La firma se validó con esquemas v1/v2, pero el certificado es `CN=Android Debug`. Estos archivos sirven para prueba interna, no para publicar en Google Play.

## Capturas nuevas

| Archivo | Evidencia |
|---|---|
| `01_native_splash.png` | Splash nativo oscuro con la marca final |
| `02_login_clean.png` | Arranque limpio: campos vacíos, sin usuario ni contraseña de demostración |
| `02_login_clean.xml` | Jerarquía accesible de la pantalla de login instalada |
| `03_launcher_icon.png` | Icono temático monocromático en Pixel Launcher |
| `03_launcher_icon.xml` | Jerarquía del launcher que identifica HomeWallet |

Las pruebas automáticas validan la lógica de bloqueo e invitación, pero la autenticación biométrica y el flujo completo de escaneo entre dos dispositivos físicos quedan como aceptación previa a lanzamiento. iOS requiere macOS y no se declara verificado.
