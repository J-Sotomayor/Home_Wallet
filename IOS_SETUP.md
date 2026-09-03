# HomeWallet en iOS y Android

El mismo código Flutter se utiliza para Android e iOS. La configuración de
Android permanece en `android/`; la configuración nativa de Apple está en
`ios/`. La aplicación iOS usa el mismo proyecto Firebase de producción y el
bundle ID `com.homewallet.app`.

## Qué debe tener la Mac

- Una versión de macOS compatible con la versión de Xcode instalada.
- Xcode actualizado, abierto al menos una vez y con un simulador de iOS
  instalado desde **Xcode > Settings > Platforms**.
- Flutter estable. El proyecto usa como base Flutter 3.29.2 y Dart 3.7.2; para
  Xcode reciente conviene usar el Flutter estable más reciente compatible.
- CocoaPods.
- Git, conexión a Internet y aproximadamente 40 GB libres para Xcode,
  simuladores, Flutter y dependencias.
- Un Apple ID solo si se instalará en un iPhone físico. El simulador no exige
  una membresía pagada de Apple Developer.

Apple Silicon es recomendable. 8 GB de RAM pueden servir; 16 GB o más ofrecen
una experiencia mucho mejor con Xcode y el simulador abiertos al mismo tiempo.

## Preparación única de la Mac

1. Instala Xcode desde App Store. Ábrelo, acepta la licencia e instala los
   componentes solicitados. Después ejecuta:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

2. Instala Flutter estable siguiendo la documentación oficial y confirma que
   `flutter` esté disponible en la terminal:

   ```bash
   flutter --version
   flutter doctor -v
   ```

3. Instala CocoaPods. Con Homebrew:

   ```bash
   brew install cocoapods
   pod --version
   ```

4. Copia o clona el repositorio en la Mac, entra en su directorio y ejecuta:

   ```bash
   bash tool/setup_ios_macos.sh
   ```

El script instala dependencias, ejecuta el análisis y las pruebas compartidas,
instala los Pods y genera una compilación debug para el simulador. La primera
ejecución puede tardar bastante porque descarga Xcode, Flutter y Firebase.

## Ejecutar en un simulador de iPhone

```bash
open -a Simulator
flutter devices
flutter run -d <id-del-simulador>
```

También se puede abrir `ios/Runner.xcworkspace` en Xcode, seleccionar un
simulador de iPhone y pulsar **Run**. Debe abrirse siempre el `.xcworkspace`, no
el `.xcodeproj`, porque Firebase y los demás plugins se integran con CocoaPods.

Para cambiar el modelo simulado, usa **File > Open Simulator** desde la app
Simulator o selecciona otro destino en Xcode.

## Ejecutar en un iPhone físico

1. Conecta el iPhone por cable y acepta **Confiar en este ordenador**.
2. En Xcode abre **Settings > Accounts** e inicia sesión con el Apple ID.
3. Abre `ios/Runner.xcworkspace`, selecciona el target **Runner** y entra en
   **Signing & Capabilities**.
4. Mantén **Automatically manage signing** y selecciona tu Team.
5. Conserva `com.homewallet.app` si ese identificador pertenece a tu cuenta de
   Apple Developer. Si Apple obliga a cambiarlo, también habrá que registrar el
   nuevo bundle ID como una app iOS en Firebase y regenerar
   `lib/firebase_options.dart`; no cambies solo el valor en Xcode.
6. Activa Developer Mode en el iPhone si iOS lo solicita y ejecuta desde Xcode
   o con `flutter run -d <id-del-iphone>`.

Una cuenta gratuita permite pruebas en un dispositivo propio con limitaciones.
TestFlight y App Store requieren membresía en Apple Developer Program.

Antes de enviar a revisión en App Store, revisa también la regla de Apple para
apps que ofrecen inicio de sesión de terceros. Debido a que HomeWallet incluye
Google Sign-In, Apple puede exigir una opción equivalente de **Sign in with
Apple**. Esto no impide ejecutar o probar la app en Simulator/iPhone, pero debe
resolverse antes de presentar la versión pública si aplica al caso de la app.

## Firebase, Google y notificaciones

La configuración pública de Firebase y Google Sign-In ya está incluida para
`homewallet-prod`. No hacen falta contraseñas, cuentas de servicio ni archivos
privados para abrir la aplicación en el simulador.

Para recibir notificaciones push reales en iPhone todavía se necesita una clave
APNs de la cuenta de Apple Developer:

1. Crear o utilizar una APNs Authentication Key (`.p8`) en Apple Developer.
2. Subirla en **Firebase Console > Project settings > Cloud Messaging** para la
   aplicación iOS de HomeWallet, junto con su Key ID y Team ID.
3. Probar el permiso y la recepción de una notificación en un iPhone físico.

El archivo `.p8`, certificados, perfiles y contraseñas nunca deben guardarse en
este repositorio.

## Comprobaciones mínimas en iOS

- Registro e inicio por correo, verificación y recuperación de contraseña.
- Inicio con Google y cierre de sesión.
- Creación y sincronización de espacios y movimientos.
- Persistencia segura y bloqueo con Face ID. En Simulator se puede simular la
  biometría desde sus menús de características.
- Cámara/QR en dispositivo físico y selección de foto.
- Importación y exportación de CSV, XLSX y PDF.
- Notificaciones locales y push en dispositivo físico.

Android se sigue ejecutando normalmente con `flutter run`, y sus artefactos se
generan con `flutter build apk` o `flutter build appbundle`.
