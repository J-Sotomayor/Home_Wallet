# Trazabilidad de HomeWallet

| Requisito | Implementación | Verificación | Estado |
|---|---|---|---|
| Identidad original | SVG/PNG en `assets/branding/`; tema centralizado | Evidencia Android y guía de marca | Implementado |
| Android icon/splash | Legacy, round, adaptive, monochrome y splash claro/oscuro | APK instalado, Pixel Launcher y capturas | Verificado en emulador |
| iOS icon/splash | AppIcon completo y configuración nativa | Inspección estática en Windows | Configurado; macOS pendiente |
| Datos quemados | Repositorios Firebase y formularios vacíos | Búsqueda en fuentes y login limpio | Eliminados |
| Autenticación real | Firebase Auth, perfil, verificación y reset | Tests widget y Firebase configurado | Implementado |
| Sesión al reabrir | `userChanges()` y `SessionLockGate` | Tests/código; sesión física pendiente | Implementado |
| Biometría | `local_auth`, credencial del dispositivo y preferencia segura por usuario | Configuración nativa y pruebas de flujo | Implementado; hardware pendiente |
| Hogares | Repositorio Firestore + `createHousehold` callable | Función `ACTIVE`, reglas y estados vacíos | Implementado |
| QR familiar | Generación, escáner, código manual y parser `HW1` | Tests válido/malicioso y función real | Implementado; dos equipos pendiente |
| Invitación segura | 256 bits, SHA-256 servidor, 15 min, un uso, revocación y rate limit | Reglas 5/5; smoke 401; Functions `ACTIVE` | Desplegado |
| Datos cifrados | AES-256-GCM por hogar con AAD y claves Keystore/Keychain | Roundtrip y manipulación rechazados | Implementado |
| Firestore | Membresía, roles, correo verificado, validación y default deny | Suite del emulador 5/5; reglas desplegadas | Desplegado |
| Storage | Denegación total hasta adjuntos E2E | Reglas desplegadas | Protegido |
| App Check | Play Integrity / App Attest + DeviceCheck | Inicialización release inspeccionada | Integrado; enforcement pendiente |
| Funciones Blaze | Tres callables Gen 2 Node 22 en Santiago | `functions:list` 3/3 `ACTIVE` | Desplegado |
| Finanzas Plus | Resumen, movimientos/filtros, presupuestos, metas/progreso y familia | `flutter analyze` y tests | Implementado |
| APK/AAB | Builds release, recursos y manifest target 36 | Hashes, instalación y evidencia | Prueba interna; firma producción pendiente |
| Auditoría | Revisión de datos, reglas, cifrado, Android y dependencias | `docs/security/security_review.md` | Documentado |

Ningún estado se eleva a “verificado en dispositivo físico” o “publicable” sin evidencia real. Los pendientes de tienda no se presentan como completados.

