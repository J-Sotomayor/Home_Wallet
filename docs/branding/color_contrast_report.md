# Informe de contraste — HomeWallet

Fecha de cálculo: 2026-07-31. Método: luminancia relativa y fórmula de contraste de WCAG 2.x. Las relaciones se redondean a dos decimales. Criterio mínimo adoptado: 4.5:1 para texto normal y 3:1 para texto grande, iconos y controles esenciales.

## Combinaciones aprobadas

| Fondo | Frente | Relación | Uso permitido | Uso rechazado | Alternativa accesible |
|---|---|---:|---|---|---|
| `#2563EB` Primary Blue | `#FFFFFF` White | 5.17:1 | Botón principal, navegación y texto normal | Texto azul más claro sobre el mismo fondo | Mantener blanco o usar `#F9FAFB` |
| `#1D4ED8` Primary Blue Dark | `#FFFFFF` White | 6.70:1 | Estado presionado y botones de alto contraste | Texto verde o rosa | Mantener blanco |
| `#047857` Accessible Green | `#FFFFFF` White | 5.48:1 | Botón verde con texto blanco | Usar `#10B981` como fondo del mismo botón | Fondo `#047857` |
| `#10B981` Savings Green | `#1F2937` Dark Gray | 5.79:1 | Chips, indicadores y superficies positivas con texto oscuro | Texto blanco normal | Frente `#1F2937` o fondo `#047857` |
| `#FFFFFF` White | `#1F2937` Dark Gray | 14.68:1 | Texto principal y encabezados | — | — |
| `#FFFFFF` White | `#4B5563` Medium Gray | 7.56:1 | Texto secundario y metadatos | Gris más claro para texto pequeño | Mantener `#4B5563` |
| `#DC2626` Expense Red | `#FFFFFF` White | 4.83:1 | Botón destructivo o etiqueta de error con texto e icono | Comunicar el error solo por color | Añadir icono, título y descripción |
| `#FEF3C7` Warning Container | `#1F2937` Dark Gray | 13.18:1 | Mensajes y tarjetas de advertencia | Blanco sobre ámbar | Texto `#1F2937` |
| `#DBEAFE` Blue Container | `#1D4ED8` Primary Blue Dark | 5.49:1 | Selección, enlaces y chips | Azul claro sobre el contenedor | Frente `#1D4ED8` |
| `#D1FAE5` Success Container | `#047857` Accessible Green | 4.84:1 | Texto positivo normal, iconos y progreso | Blanco o verde claro | Frente `#047857` |
| `#E8B4BC` Blush Pink | `#1F2937` Dark Gray | 8.17:1 | Etiquetas familiares, avatares e ilustraciones | Rosa como texto principal | Texto `#1F2937` |

## Combinaciones limitadas o rechazadas

| Fondo | Frente | Relación | Uso permitido | Uso rechazado | Alternativa accesible |
|---|---|---:|---|---|---|
| `#10B981` Savings Green | `#FFFFFF` White | 2.54:1 | Elemento decorativo sin texto; no para control esencial | Botones y texto, incluso texto grande | Fondo `#047857` con blanco (5.48:1) |
| `#E8B4BC` Blush Pink | `#FFFFFF` White | 1.80:1 | Ninguno para contenido informativo | Texto, iconos y controles | Frente `#1F2937` (8.17:1) |
| `#FFFFFF` White | `#E8B4BC` Blush Pink | 1.80:1 | Decoración no informativa | Texto rosa, iconos funcionales y bordes de campo | `#9F5865` para iconos grandes o `#1F2937` para texto |
| `#FCE7EB` Pink Container | `#9F5865` Blush Pink Dark | 4.38:1 | Texto grande, iconos y controles ≥3:1 | Texto normal pequeño | `#1F2937` sobre `#FCE7EB` |
| `#D97706` Warning Amber | `#FFFFFF` White | 3.19:1 | Iconos grandes y controles gráficos | Texto normal blanco | Texto `#1F2937` sobre `#FEF3C7` |

## Tema oscuro

| Fondo | Frente | Relación | Uso permitido | Uso rechazado | Alternativa accesible |
|---|---|---:|---|---|---|
| `#111827` Background | `#F9FAFB` Text Primary | 16.98:1 | Texto principal | — | — |
| `#1F2937` Surface | `#F9FAFB` Text Primary | 14.05:1 | Texto principal en tarjetas | — | — |
| `#1F2937` Surface | `#D1D5DB` Text Secondary | 9.96:1 | Texto secundario | Gris de menor contraste | Mantener `#D1D5DB` |
| `#111827` Background | `#60A5FA` Primary | 6.98:1 | Enlaces, iconos y controles | Azul oscuro sobre el mismo fondo | Mantener `#60A5FA` |
| `#111827` Background | `#34D399` Savings Green | 9.23:1 | Ahorro e ingresos con texto/icono | Estado solo por color | Añadir signo, etiqueta e icono |
| `#111827` Background | `#F3C6CE` Blush Pink | 11.64:1 | Acentos familiares moderados | Acciones financieras principales | Usar `#60A5FA` para acciones |
| `#1F2937` Surface | `#F87171` Error | 5.31:1 | Error con icono y texto | Comunicar error solo por rojo | Añadir mensaje explícito |
| `#111827` Background | `#FBBF24` Warning | 10.63:1 | Advertencia con icono y etiqueta | Color como único indicador | Añadir texto de advertencia |

## Reglas aplicadas

- Ingresos muestran signo `+`, monto, etiqueta e icono además del verde.
- Gastos muestran signo `-`, monto, etiqueta e icono además del color de gasto.
- Errores y advertencias incluyen icono y texto; el rosa no se usa para ellos.
- `#10B981` no se usa con texto blanco en botones. El botón verde accesible debe usar `#047857`.
- El rosa palo es decorativo o familiar; nunca identifica saldo, gasto, deuda o acción destructiva.
