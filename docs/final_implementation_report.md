# Informe final de implementación — HomeWallet

Fecha: 2026-07-31

## Resultado

HomeWallet quedó conectada al proyecto Blaze `homewallet-prod`, sin datos de demostración y con flujos reales de autenticación, hogares, integrantes, movimientos, presupuestos y metas. Se incorporaron sesión persistente protegida por el dispositivo, invitaciones familiares QR, cifrado de extremo a extremo para la información financiera y controles de acceso del lado servidor.

La identidad visual continúa integrada en iconos, splash, acceso, registro y aplicación. El APK fue instalado y ejecutado en Android; el AAB fue generado e inspeccionado.

## Funcionalidad entregada

| Área | Estado |
|---|---|
| Firebase Auth | Registro, inicio, verificación de correo, recuperación en español y cierre de sesión reales |
| Sesión persistente | Firebase restaura la sesión; HomeWallet solicita biometría o credencial del dispositivo al reabrir y tras 30 s en segundo plano |
| Datos | Firestore en tiempo real, estados vacíos y de error; sin registros ni credenciales prefabricados |
| Familias | Crear hogar vacío, seleccionar hogar, listar integrantes, generar QR y escanear/pegar invitación |
| QR seguro | Administrador, token 256 bits, hash servidor, 15 min, un uso, límites y regeneración que revoca el anterior |
| Cifrado | AES-256-GCM en el dispositivo; claves por hogar en Android Keystore/iOS Keychain |
| Finanzas Plus | Movimientos, filtros, resumen, presupuestos, metas, progreso y tarjeta familiar |
| Seguridad Firebase | Reglas por pertenencia/rol, verificación de correo, payload cifrado, Storage cerrado y Functions Gen 2 |
| App Check | API habilitada; TECNO/AVD debug registrados; Play Integrity y App Attest/DeviceCheck integrados; exigencia pendiente tras registrar releases |
| Marca | Logo, paleta, tema claro/oscuro/sistema, Android adaptive/round/monochrome, iOS AppIcon y splash |

## Backend desplegado

En `homewallet-prod` están activas `createHousehold`, `createInvitation` y `acceptInvitation`, Gen 2 con Node.js 22 en `southamerica-west1`. Firestore y Storage usan las reglas del repositorio. Una petición directa sin Firebase Auth fue rechazada con HTTP 401.

## Validación

- `dart format .`: correcto.
- `flutter analyze`: sin problemas.
- `flutter test`: 7/7.
- reglas Firestore en emulador: 5/5.
- Functions TypeScript: compilación correcta.
- búsqueda de secretos/datos demo: sin datos de producción quemados.
- APK release: 77.394.392 bytes; SHA-256 `1A58D4BCB2781774DBA9C8E5493275793AD49C3C452A0F102166A47714A15210`.
- AAB release: 42.091.818 bytes; SHA-256 `326DAF84947945C5B58159728594D963366466D0ED8198F17DDD5DABB465C13C`.
- instalación Android: correcta en Pixel 7 Pro AVD, Android 17/API 37.
- evidencia real de splash, login limpio e icono temático en `docs/evidence/security_release/`.

## Límites y pendientes antes de publicar

- Los artefactos actuales usan certificado Android Debug. Deben reconstruirse con un keystore de producción.
- App Check está integrado, pero aún no debe declararse exigido: registrar la firma/release, observar solicitudes válidas y activar enforcement en Firebase Console.
- Realizar una prueba de aceptación con dos teléfonos físicos para QR y biometría.
- Compilar y verificar AppIcon, splash y ejecución iOS en macOS; no se atribuye esa prueba desde Windows.
- `npm audit` conserva 7 avisos moderados transitivos sin arreglo seguro disponible en las versiones actuales; no hay avisos altos o críticos. El detalle está en `docs/security/security_review.md`.

La versión está lista para pruebas funcionales Android y conexión real con usuarios. No está lista para Google Play hasta cambiar la firma y completar App Check y las pruebas físicas.
