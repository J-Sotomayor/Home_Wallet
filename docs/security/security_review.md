# Revisión de seguridad de HomeWallet

Fecha: 2026-07-31  
Proyecto Firebase: `homewallet-prod`

## Resultado ejecutivo

La aplicación ya no usa credenciales, saldos, movimientos, metas ni hogares de demostración. La autenticación, los hogares, las transacciones, los presupuestos y las metas trabajan con Firebase. Las reglas de Firestore y Storage se desplegaron y las operaciones privilegiadas se ejecutan en Cloud Functions.

La información financiera privada se cifra en el dispositivo con AES-256-GCM antes de enviarse a Firestore. La clave de cada hogar se almacena en Android Keystore o iOS Keychain mediante `flutter_secure_storage`; Firebase no recibe esa clave. Además, Firebase protege el transporte con TLS y cifra sus servicios en reposo.

## Datos y cifrado

Se cifran de extremo a extremo por hogar:

- nombre del hogar;
- nombre visible de sus integrantes;
- descripción, categoría, importe y propiedad compartida de movimientos;
- nombre, objetivo y avance de presupuestos y metas.

Cada documento usa un IV aleatorio y datos asociados con su ruta. Una alteración del ciphertext, IV, etiqueta o contexto hace fallar la autenticación GCM. El formato persistido es `{v, alg, ct, iv, tag}` y no contiene esos valores financieros en claro.

Metadatos que no son E2E y siguen visibles para Firebase por necesidad operativa: UID y correo gestionados por Firebase Authentication, rol, estado, tipo de movimiento o plan, marcas de tiempo, identificadores y contadores. No se afirma que esos metadatos estén ocultos al proveedor.

La clave del hogar no se respalda en la nube. Después de reinstalar o cambiar de teléfono hay que escanear un QR nuevo de otro integrante. Si todos los dispositivos pierden la clave, el contenido financiero cifrado no se puede recuperar; es el costo deliberado de no entregar la clave a Firebase.

## Autenticación y bloqueo local

- Firebase Authentication conserva la sesión nativa al cerrar y volver a abrir la aplicación.
- Una sesión restaurada se presenta detrás del bloqueo del dispositivo cuando este es compatible y la protección está habilitada.
- También se bloquea después de permanecer al menos 30 segundos en segundo plano.
- Se admite biometría o la credencial segura del dispositivo (PIN, patrón o contraseña). HomeWallet no guarda la contraseña de Firebase.
- El usuario puede activar o desactivar esta protección desde la aplicación; activarla exige autenticarse en el dispositivo.
- Las operaciones familiares exigen correo verificado.

## Invitaciones QR

- Solo `owner` o `admin` puede crear una invitación.
- El servidor genera un token criptográficamente aleatorio de 256 bits y almacena únicamente su SHA-256.
- La invitación vence en 15 minutos, es de un solo uso y se consume en una transacción atómica.
- Hay un único QR activo por hogar; generar uno nuevo invalida inmediatamente el anterior.
- Se aplican límites de frecuencia, máximo de 5 hogares por usuario y 12 integrantes por hogar.
- El texto copiado se intenta borrar del portapapeles después de 60 segundos.
- El lector rechaza URLs y cargas que no tengan el esquema estricto `HW1`.

El QR contiene tanto el token de acceso como la clave de descifrado del hogar. Por eso debe tratarse como un secreto: compartirlo únicamente en persona o por un canal confiable y regenerarlo si fue expuesto. El cifrado del QR en sí no sustituiría ese control, porque el dispositivo invitado necesita obtener la clave.

## Controles de Firebase y Android

- Reglas Firestore con denegación predeterminada, correo verificado, pertenencia activa y control de roles.
- Los clientes no pueden leer invitaciones ni contadores internos de frecuencia.
- Las reglas validan forma de documentos, tipos, campos permitidos, autoría y payload cifrado.
- Storage está bloqueado completamente hasta implementar adjuntos cifrados de extremo a extremo.
- Las funciones callable validan Firebase Auth en el servidor y rechazan usuarios no verificados.
- App Check está integrado: Play Integrity en Android release y App Attest con DeviceCheck como respaldo en iOS release.
- `firebaseappcheck.googleapis.com` está habilitada en `homewallet-prod`. Los tokens de desarrollo del TECNO KJ7 y Pixel 7 Pro AVD están registrados sin almacenarlos en el repositorio.
- Android desactiva backup, tráfico HTTP en claro y permisos publicitarios; `minSdk 23`, `targetSdk 36`.
- Errores no controlados de producción se registran con Crashlytics sin mostrar detalles internos al usuario.

## Pruebas realizadas

- `flutter analyze`: sin problemas.
- `flutter test`: 7/7; incluye cifrado/descifrado, rechazo por manipulación, QR válido y QR malicioso.
- Pruebas de reglas en emulador: 5/5; anónimo, correo no verificado, intruso, datos en claro y cambios de rol no autorizados rechazados.
- `npm run build`: TypeScript correcto.
- Petición real sin credenciales a `createInvitation`: HTTP 401 `UNAUTHENTICATED`.
- Tres funciones Gen 2 desplegadas y `ACTIVE` en `southamerica-west1`.
- Intercambio real del token App Check del TECNO: correcto, TTL 3600 segundos; cero errores App Check después de reiniciar la aplicación.
- APK release instalado en emulador con datos de aplicación limpios; login vacío y sin cuentas de prueba.

## Hallazgos pendientes y riesgo residual

| Prioridad | Hallazgo | Estado / mitigación |
|---|---|---|
| Alta para publicar | El APK y AAB actuales están firmados con el certificado Android Debug. | No publicar. Configurar un keystore privado de producción, proteger sus secretos y reconstruir ambos artefactos. |
| Alta para producción | App Check está integrado pero su exigencia debe activarse después de registrar las versiones de Play/App Store y observar métricas. | Pendiente en Firebase Console; activarlo directamente antes de registrar proveedores podría bloquear usuarios legítimos. |
| Media | `npm audit --omit=dev` informa 7 vulnerabilidades moderadas transitivas relacionadas con `uuid` a través del SDK de Google. | `firebase-admin` y `firebase-functions` ya están en sus versiones actuales. No aplicar `--force`, porque propone una regresión mayor. La invitación usa `node:crypto`, no las APIs vulnerables de UUID; vigilar actualización upstream. No hay hallazgos altos o críticos del audit. |
| Media | El QR transfiere una clave maestra y un token bearer. Una captura antes de consumirse concede acceso. | Caducidad 15 minutos, un solo uso, revocación al regenerar, 256 bits aleatorios y aviso visible. No enviarlo por canales no confiables. |
| Media | No se realizó prueba completa QR/biometría entre dos teléfonos físicos. | Código, parser, reglas, función y UI validados; prueba física pendiente antes del lanzamiento. |
| Media | Build y ejecución iOS no comprobados en Windows. | Configuración estática lista; compilar y probar en macOS, simulador y dispositivo. |
| Baja | Una cuenta ya autenticada puede seguir accediendo hasta que su token se renueve si se revoca fuera del dispositivo. | Comportamiento normal de tokens Firebase; para acciones administrativas futuras conviene exigir reautenticación reciente. |

## Acciones obligatorias antes de tienda

1. Configurar firma Android de producción y guardar el keystore fuera del repositorio.
2. Registrar SHA-256 de esa firma en Firebase/Google Play y volver a descargar la configuración si fuera necesaria.
3. Publicar en una pista interna, validar Play Integrity y después exigir App Check para Firestore y Functions.
4. Probar registro, verificación, recuperación, biometría y QR con dos dispositivos reales.
5. Ejecutar build y pruebas iOS desde macOS.
6. Revisar periódicamente `flutter pub outdated` y `npm audit --omit=dev`.
