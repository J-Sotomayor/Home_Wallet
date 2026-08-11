param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"

$signingDirectory = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "HomeWallet-Signing"
$keystorePath = Join-Path $signingDirectory "homewallet-release.jks"
$recoveryPath = Join-Path $signingDirectory "RECOVERY.txt"
$propertiesPath = Join-Path $ProjectRoot "android\key.properties"

if (Test-Path -LiteralPath $keystorePath) {
    throw "Ya existe una llave de firma en $keystorePath. No se reemplazó."
}

New-Item -ItemType Directory -Force -Path $signingDirectory | Out-Null

$randomBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
$password = [Convert]::ToBase64String($randomBytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
$androidStudioKeytool = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
if ($keytoolCommand) {
    $keytool = $keytoolCommand.Source
} elseif (Test-Path -LiteralPath $androidStudioKeytool) {
    $keytool = $androidStudioKeytool
} else {
    throw "No se encontró keytool en PATH ni en Android Studio."
}

& $keytool -genkeypair -v `
    -keystore $keystorePath `
    -storepass $password `
    -keypass $password `
    -alias homewallet `
    -keyalg RSA `
    -keysize 4096 `
    -validity 10000 `
    -dname "CN=HomeWallet, OU=HomeWallet, O=HomeWallet, L=Guayaquil, ST=Guayas, C=EC"

if ($LASTEXITCODE -ne 0) {
    throw "keytool no pudo crear la llave de firma."
}

$normalizedKeystorePath = $keystorePath.Replace("\", "/")
$properties = @(
    "storePassword=$password"
    "keyPassword=$password"
    "keyAlias=homewallet"
    "storeFile=$normalizedKeystorePath"
) -join [Environment]::NewLine
[IO.File]::WriteAllText($propertiesPath, $properties + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

$recovery = @"
HOMEWALLET - CREDENCIALES DE FIRMA ANDROID

Archivo de firma: $keystorePath
Alias: homewallet
Contraseña: $password

IMPORTANTE:
- Conserva esta carpeta y una copia de respaldo privada.
- No compartas estos archivos ni los subas al repositorio.
- Sin esta llave no se podrán publicar actualizaciones compatibles con el APK actual.
"@
[IO.File]::WriteAllText($recoveryPath, $recovery, [Text.UTF8Encoding]::new($false))

$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls $signingDirectory /inheritance:r /grant:r "${currentUser}:(OI)(CI)F" | Out-Null

$sha256 = & $keytool -J-Duser.language=en -list -v -keystore $keystorePath -storepass $password -alias homewallet |
    Select-String -Pattern "SHA256:" |
    ForEach-Object { ($_.Line -split "SHA256:", 2)[1].Trim().Replace(":", "").ToLowerInvariant() }

Write-Output "Keystore=$keystorePath"
Write-Output "Recovery=$recoveryPath"
Write-Output "Properties=$propertiesPath"
Write-Output "SHA256=$sha256"
