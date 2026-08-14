<p align="center">
  <img src="assets/branding/homewallet_logo_horizontal.svg" alt="HomeWallet" width="440">
</p>

<h1 align="center">HomeWallet</h1>

<p align="center">
  Finanzas personales y colaborativas, claras y seguras.
</p>

<p align="center">
  <img alt="Flutter 3.29.2" src="https://img.shields.io/badge/Flutter-3.29.2-02569B?logo=flutter&logoColor=white">
  <img alt="Dart 3.7.2" src="https://img.shields.io/badge/Dart-3.7.2-0175C2?logo=dart&logoColor=white">
  <img alt="Firebase" src="https://img.shields.io/badge/Firebase-Backend-FFCA28?logo=firebase&logoColor=black">
  <img alt="Versión 1.0.7" src="https://img.shields.io/badge/versi%C3%B3n-1.0.7-blue">
</p>

## Descripción

HomeWallet es una aplicación Android desarrollada con Flutter para administrar finanzas personales y compartidas. Cada persona puede conservar un espacio Individual privado y participar además en espacios Pareja, Familia o Grupo, sin mezclar automáticamente sus movimientos. La información financiera se cifra en el dispositivo antes de enviarse a Firebase.

## Funcionalidades principales

- Registro e inicio de sesión con correo o Google, verificación de correo, recuperación de contraseña y gestión del perfil.
- Sesión persistente protegida con biometría o la credencial segura del dispositivo.
- Espacios Individual, Pareja, Familia y Grupo, con cambio seguro entre espacios y datos separados.
- Roles Propietario, Moderador, Miembro y Lector/Integrante Jr., con permisos aplicados por backend.
- Invitaciones mediante QR o código manual, con rol fijado por quien invita, revocación, token de un solo uso y vencimiento automático.
- Registro de ingresos, gastos y ahorros, con categorías, filtros y saldos consolidados.
- Ingreso neto mensual cifrado por integrante, visible en Inicio y reutilizado automáticamente en el reparto proporcional de gastos.
- Presupuestos y metas editables, movimientos recurrentes y deudas compartidas con reparto igualitario, porcentual, proporcional automático por ingresos o personalizado.
- Importación local de estados de cuenta en CSV, XLS, XLSX y PDF compatible, con selección y detección de duplicados mediante SHA-256.
- Exportación de reportes profesionales en Excel, PDF y CSV.
- Alertas inteligentes, recordatorios en segundo plano y notificaciones push adaptadas a Individual, Pareja, Familia y Grupo.
- Comparación de ingresos y gastos con el mes anterior.
- Tema claro, oscuro o del sistema e identidad visual adaptada a Android.
- Requiere conexión para sincronizar y escribir; no ofrece un modo de trabajo offline.

## Seguridad y privacidad

- Cifrado AES-256-GCM en el dispositivo para la información financiera compartida.
- Claves por espacio almacenadas localmente con el almacén seguro de Android.
- Recuperación automática tras reinstalar o cambiar de teléfono: una Cloud Function verifica la sesión y la membresía activa antes de devolver la clave. La copia se cifra con AES-256-GCM mediante un secreto de Google Secret Manager y nunca admite lectura directa desde Firestore.
- Reglas de Firestore basadas en membresía, rol y correo verificado.
- Invitaciones protegidas con tokens aleatorios de 256 bits, hash SHA-256, expiración y límites de uso.
- Firebase App Check preparado para Play Integrity en distribuciones por Google Play.
- La exigencia e inicialización de App Check permanecen desactivadas en los APK instalados directamente para no bloquear teléfonos legítimos; las reglas de Firebase, la autenticación y el cifrado continúan aplicándose.
- Fotos de perfil protegidas por propietario, tipo, nombre y tamaño mediante reglas de Firebase Storage.
- Procesamiento de archivos bancarios en el dispositivo.

## Tecnologías

| Capa | Tecnologías |
|---|---|
| Aplicación | Flutter 3.29.2, Dart 3.7.2, Material Design |
| Backend | Firebase Authentication, Firestore, Cloud Functions, Storage y Cloud Messaging |
| Observabilidad | Firebase Crashlytics |
| Seguridad | App Check, `cryptography`, `flutter_secure_storage` y `local_auth` |
| Funciones | TypeScript, Node.js 22 y Firebase Functions Gen 2 |
| Reportes | Excel, PDF y CSV |

## Requisitos

- Flutter `3.29.2` o una versión estable compatible con Dart `3.7.2`.
- Android Studio y Android SDK.
- Node.js `22` y npm para Cloud Functions.
- Firebase CLI y FlutterFire CLI para utilizar un proyecto Firebase propio.

Verifica el entorno antes de continuar:

```bash
flutter doctor
node --version
firebase --version
```

## Instalación

1. Clona el repositorio e instala las dependencias de Flutter:

   ```bash
   git clone https://github.com/J-Sotomayor/Home_Wallet.git
   cd Home_Wallet
   flutter pub get
   ```

2. Instala las dependencias de Cloud Functions:

   ```bash
   cd functions
   npm ci
   npm run build
   cd ..
   ```

3. Ejecuta la aplicación en un dispositivo o emulador:

   ```bash
   flutter run
   ```

Para seleccionar un destino concreto, consulta primero los dispositivos disponibles:

```bash
flutter devices
flutter run -d <device-id>
```

## Configuración de Firebase

El código está configurado para el proyecto de producción de HomeWallet. Para desplegar el backend necesitas permisos sobre ese proyecto. Para desarrollo independiente, crea tu propio proyecto Firebase y reemplaza la configuración local:

1. Activa Authentication (correo/contraseña y Google), Firestore, Functions, Storage, Cloud Messaging, Crashlytics, Analytics y App Check.
2. Instala las herramientas si aún no están disponibles:

   ```bash
   npm install --global firebase-tools
   dart pub global activate flutterfire_cli
   firebase login
   ```

3. Asocia el repositorio con tu proyecto y genera la configuración de las plataformas:

   ```bash
   firebase use --add
   flutterfire configure --project=<firebase-project-id>
   ```

4. Registra las huellas SHA-1 y SHA-256 necesarias para Google Sign-In y App Check en Android.
5. Configura un secreto aleatorio de 32 bytes para proteger las copias de recuperación:

   ```bash
   firebase functions:secrets:set HOUSEHOLD_KEY_BACKUP_SECRET
   ```

6. Revisa las reglas y despliega el backend:

   ```bash
   npm --prefix functions run build
   firebase deploy --only firestore:rules,firestore:indexes,storage,functions
   ```

No almacenes archivos de cuentas de servicio, contraseñas, certificados de firma ni variables `.env` en el repositorio.

Los valores de `lib/firebase_options.dart` y
`android/app/google-services.json` son configuración pública del cliente, no
credenciales de autorización. Deben utilizarse únicamente con servicios de
Firebase y mantenerse restringidos a las APIs y aplicaciones correspondientes
desde Google Cloud. La protección de los datos depende de IAM, Firebase
Security Rules y App Check. Consulta la
[documentación oficial sobre claves de Firebase](https://firebase.google.com/docs/projects/api-keys).

## Calidad y pruebas

Ejecuta el análisis estático y la suite de Flutter:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Para revisar manualmente reglas y backend sin tocar producción, inicia los emuladores:

```bash
firebase emulators:start --only auth,firestore,functions,storage
```

## Compilación

Para una compilación release, copia `android/key.properties.example` como
`android/key.properties`, completa la ruta y contraseñas del keystore real y
mantén ambos archivos sensibles fuera del repositorio.

Android APK para pruebas internas firmadas:

```bash
flutter build apk --release
```

Android App Bundle para Google Play:

```bash
flutter build appbundle --release --dart-define=HOMEWALLET_ENABLE_APP_CHECK=true
```

El APK directo no activa App Check. Solo debe habilitarse la constante
`HOMEWALLET_ENABLE_APP_CHECK` cuando el artefacto se distribuya por un canal
capaz de proporcionar un veredicto válido de Play Integrity y después de
activar gradualmente la exigencia en Firebase.

> El proyecto no usa la firma debug en release. Sin `android/key.properties` y
> un keystore válido no existe un artefacto apto para publicar. Registra también
> las huellas release en Firebase/App Check y completa pruebas físicas.

## Estructura del proyecto

```text
homewallet/
├── android/                 # Proyecto nativo Android
├── assets/                  # Marca, iconos, splash y tipografías
├── functions/               # Cloud Functions y pruebas de reglas
├── ios/                     # Base Flutter fuera del alcance de esta entrega
├── lib/
│   ├── app/                 # Tema, servicios y componentes compartidos
│   ├── core/                # Seguridad, notificaciones y errores
│   └── features/            # Auth, espacios, finanzas, perfil y legal
├── test/                    # Pruebas unitarias y de widgets
└── web/                     # Configuración de Flutter Web
```

## Documentación

- [Guía de marca](assets/branding/brand_guidelines.md)

## Estado del proyecto

La versión actual es `1.0.7+8`. Esta entrega es exclusivamente Android: `minSdk 23` (Android 6.0), `targetSdk 36`, con validación actual en el emulador Android 17 (API 37) y APK release firmado para pruebas físicas por instalación directa. iOS no forma parte del alcance ni de los criterios de aceptación de esta entrega. La publicación requiere pruebas en los dispositivos Android declarados y la activación controlada de App Check después de publicar por Google Play o adoptar un proveedor compatible con todos los dispositivos admitidos.

## Licencia

Este repositorio no incluye todavía una licencia pública. Todos los derechos permanecen reservados a su autor hasta que se añada un archivo `LICENSE`.
