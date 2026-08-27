#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este script debe ejecutarse en macOS."
  exit 1
fi

missing=0
for command_name in flutter xcodebuild pod; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Falta instalar: $command_name"
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  echo "Instala Flutter, Xcode y CocoaPods y vuelve a ejecutar este script."
  exit 1
fi

cd "$PROJECT_ROOT"

echo "==> Verificando herramientas"
flutter --version
xcodebuild -version
pod --version

echo "==> Descargando componentes iOS de Flutter"
flutter precache --ios

echo "==> Instalando dependencias Dart"
flutter pub get

echo "==> Instalando dependencias nativas iOS"
(
  cd ios
  pod install --repo-update
)

echo "==> Ejecutando controles del código compartido Android/iOS"
flutter analyze --no-pub
flutter test --no-pub

echo "==> Compilando la aplicación para el simulador iOS"
flutter build ios --simulator --debug --no-pub

echo
echo "Preparación terminada. Para ejecutar:"
echo "  open -a Simulator"
echo "  flutter devices"
echo "  flutter run -d <id-del-simulador>"
echo
echo "Si prefieres Xcode, abre ios/Runner.xcworkspace (no Runner.xcodeproj)."
