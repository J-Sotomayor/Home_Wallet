# Guía de marca HomeWallet

## Concepto

HomeWallet une dos ideas en una sola silueta: el techo representa el hogar y el cuerpo redondeado funciona como billetera. La puerta azul crea espacio negativo; la moneda verde con confirmación comunica ahorro y progreso; el punto rosa representa cercanía y colaboración familiar. La construcción evita letras, fotografías, sombras y detalles frágiles.

La marca debe percibirse confiable, moderna, tecnológica, familiar y profesional, sin imitar una entidad bancaria, criptomoneda o billetera de terceros.

## Construcción y área de seguridad

- Maestro cuadrado: 1024 × 1024 px.
- Zona principal del símbolo: aproximadamente `x=206–818`, `y=184–797`.
- Margen seguro mínimo: 20 % del lienzo alrededor de los elementos esenciales.
- El techo, la billetera y la confirmación permanecen dentro de la zona segura adaptativa.
- No se dibujan esquinas redondeadas en el App Icon de iOS; el sistema aplica la máscara.
- El símbolo no contiene texto. El nombre aparece únicamente en el logotipo horizontal.

## Tamaños mínimos

- Símbolo: 24 px de lado en interfaz.
- Logotipo horizontal: 120 px de ancho.
- App Icon maestro: 1024 px sin transparencia.
- Para tamaños inferiores a 120 px de ancho debe usarse solo el símbolo.

## Paleta oficial

| Rol | Color |
|---|---|
| Primary Blue | `#2563EB` |
| Primary Blue Dark | `#1D4ED8` |
| Savings Green | `#10B981` |
| Accessible Green | `#047857` |
| White | `#FFFFFF` |
| Dark Gray | `#1F2937` |
| Medium Gray | `#4B5563` |
| Light Gray | `#F3F4F6` |
| Border Gray | `#D1D5DB` |
| Blush Pink | `#E8B4BC` |
| Blush Pink Light | `#FCE7EB` |
| Blush Pink Dark | `#9F5865` |
| Expense Red | `#DC2626` |
| Warning Amber | `#D97706` |

Los contenedores semánticos son `#D1FAE5`, `#FEE2E2`, `#FEF3C7`, `#DBEAFE` y `#FCE7EB`. Los tokens de tema oscuro están centralizados en `lib/app/theme/app_colors.dart`.

## Tipografía

La aplicación usa la tipografía sans serif nativa de cada plataforma para preservar legibilidad, rendimiento y coherencia del sistema: Roboto en Android y San Francisco en iOS. Los pesos 600–800 se reservan para etiquetas, títulos y cifras; el cuerpo usa peso normal. La escala completa vive en `lib/app/theme/app_typography.dart`.

## Versiones y fondos permitidos

- Principal: símbolo azul a color o logotipo horizontal sobre blanco y gris muy claro.
- Blanca: logotipo blanco con acentos adaptados sobre `#111827`, `#1F2937` o fotografía solo si existe una capa oscura uniforme.
- Monocromática: iconos temáticos de Android, tinta única y contextos de accesibilidad.
- Foreground: exclusivamente para el icono adaptativo sobre el fondo sólido `#2563EB`.
- El símbolo puede aparecer sin wordmark en launcher, avatar de aplicación, splash y espacios compactos.

## Uso del rosa palo

El rosa es un acento cálido y minoritario. Se permite en onboarding, tarjeta “Tu familia”, avatares predeterminados, invitaciones pendientes, metas, celebraciones y estados vacíos. No se usa para saldo, ingreso, gasto, deuda, error, advertencia ni botón financiero principal. Nunca se usa como texto principal sobre blanco.

## Usos incorrectos

- No deformar, recortar, rotar ni cambiar proporciones.
- No sustituir el símbolo por una “H”, emoji, fotografía o recurso remoto.
- No añadir texto dentro del icono principal.
- No añadir sombras, contornos, degradados o detalles que desaparezcan a 24 px.
- No recolorear fuera de las versiones definidas.
- No colocar la versión principal sobre fondos que reduzcan el contraste.
- No repetir el logo en cada tarjeta o sección.

## Accesibilidad

El contraste se documenta en [color_contrast_report.md](color_contrast_report.md). Estados financieros y alertas combinan color, signo, valor, etiqueta e icono. Los botones verdes con texto blanco usan `#047857`; `#10B981` se reserva para indicadores o se combina con texto oscuro.

## Archivos fuente

- `assets/branding/homewallet_app_icon.svg`
- `assets/branding/homewallet_logo_horizontal.svg`
- `assets/branding/homewallet_logo_white.svg`
- `assets/branding/homewallet_logo_monochrome.svg`
- `assets/branding/homewallet_icon_foreground.svg`
- `assets/branding/generated/` para derivados PNG

## Regeneración

```powershell
python -m pip install pymupdf pillow
python tool/generate_brand_assets.py
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

El script parte de los SVG y genera PNG maestros, iconos legacy Android redondos y normales, todos los tamaños de AppIcon de iOS y recursos web. Los paquetes Flutter generan las capas adaptativas/monocromáticas y el splash nativo.

## Uso en producto

- Splash nativo: símbolo centrado.
- Login, registro, verificación, recuperación y onboarding: logotipo horizontal.
- Panel: símbolo compacto en el encabezado.
- Acerca de HomeWallet: logotipo horizontal y explicación del concepto.
- Error de inicio: símbolo compacto con mensaje e icono de error.

## Evidencia

La matriz y 11 capturas reales del APK release instalado se guardan en `docs/evidence/branding/`. Incluyen launcher normal, icono temático, splash claro/oscuro, acceso, registro, dashboards, selector de tema y Acerca de. La validación iOS en dispositivo continúa reservada para macOS.
