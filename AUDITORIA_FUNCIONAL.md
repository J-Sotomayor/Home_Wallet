# Auditoría funcional de HomeWallet

Fecha de revisión: 14 de agosto de 2026.

Esta matriz describe el código que existe en este repositorio y las pruebas ejecutadas localmente. `Implementado` significa que existe interfaz y lógica; cuando la operación es sensible también se revisó la protección en Functions o reglas. Una prueba que depende de Firebase desplegado, entrega FCM, un dispositivo físico o un archivo bancario real queda identificada expresamente y no se presenta como aprobada sin evidencia.

| # | Área | Estado comprobado | Resultado |
|---|---|---|---|
| 1 | Individual / Pareja / Familia / Grupo | Implementado | Existen los cuatro tipos. Cada cuenta puede tener como máximo un Individual, protegido transaccionalmente; Individual tiene un único propietario y oculta invitaciones, integrantes, división, deudas y filtros colaborativos. No se convierte hacia/desde tipos compartidos. Pareja mantiene el límite atómico de dos y, al completarse, cambia “Invitar” por “Integrantes”; Familia y Grupo no tienen un máximo de producto. |
| 2 | Invitaciones | Implementado con protección de servidor | Generación por código/QR, rol fijado por quien invita, revocación explícita, token aleatorio con hash, vencimiento de 15 minutos y uso único. UI y Cloud Functions impiden invitar desde Individual, aceptar hacia Individual, reutilizar o aceptar tokens vencidos, y controlan pertenencia/cupos. |
| 3 | Roles y permisos | Implementado | Propietario, Moderador, Miembro y Lector (Integrante Jr). Jr solo está permitido en Familia y es de lectura. Propietario/Moderador administran; el cambio de rol y expulsión quedan reservados al propietario; un integrante puede salir y el propietario no puede abandonar accidentalmente. Las reglas de Firestore vuelven a validar lectura/escritura. |
| 4 | Terminología | Implementado en la interfaz | Los textos visibles principales usan “espacio financiero”, “mi espacio”, “unirse a un espacio” e “invitar integrante”. Se conservaron nombres internos como `Household`, `householdId` y `HouseholdKind`. |
| 5 | Modo offline | Eliminado del alcance | No hay cola, pantalla ni promesa de trabajo offline. La persistencia local de Firestore está deshabilitada; la app requiere conexión para sincronizar/escribir. |
| 6 | RF10 / análisis financiero | Implementado sin inventar datos | Se conservaron las alertas financieras existentes y se añadió comparación real contra el mes calendario anterior: variación de ingresos, gastos y categoría con mayor aumento. |
| 7 | Dividir gasto y deudas | Implementado | División igualitaria, porcentual, personalizada y proporcional a ingresos; participantes, pagador, porción, saldo, deuda, liquidación y redondeo al centavo. Es independiente de registrar un movimiento y no aparece en Individual. |
| 8 | Presupuestos | Implementado | Alta, categoría, límite mensual, cálculo consumido, progreso, niveles de alerta, cambio de mes, edición, activación/desactivación y eliminación. |
| 9 | Metas de ahorro | Implementado | Alta, objetivo, categoría, aportes vinculados, progreso, edición, completar/desactivar, reactivar y eliminar cuando no posee aportes. Si existen aportes se conserva la meta para no romper trazabilidad. No se afirma que existan “hitos”. |
| 10 | Movimientos recurrentes | Implementado | Alta, frecuencia, próxima fecha, edición, activación/desactivación y eliminación. Al vencer se notifica; al abrir la app se confirma o valida el registro y se genera un movimiento con identificador determinista para evitar dobles ejecuciones. |
| 11 | Importación | Implementado | Parsers para PDF digital, CSV, XLS y XLSX; detección bancaria, ingresos/gastos, reglas de categoría, fechas, signos, previsualización, selección/cancelación y validación. Se añadió huella SHA-256 para detectar duplicados del archivo y contra movimientos importados existentes. El archivo se procesa localmente y no se sube; solo se guardan los movimientos seleccionados cifrados. |
| 12 | Exportación | Implementado y probado | Genera XLSX, PDF y CSV con filtros de periodo, categoría, origen e integrante cuando corresponde. Individual no muestra un filtro absurdo por integrante. Las pruebas validan firmas y contenido de los tres formatos. |
| 13 | Reportes | Implementado | Ingresos, gastos, categorías, periodos, filtros, integrantes solo en espacios compartidos, gráficas y totales derivados de movimientos reales. La comparación mensual nueva se integra en el mismo reporte. |
| 14 | Notificaciones | Implementado; entrega externa pendiente de validación final | FCM y notificaciones locales cubren actividad/movimientos, invitación aceptada, cambio de rol, retiro, recurrencias, presupuesto, metas y estado financiero. El código y la compilación se verificaron; la recepción en producción depende de permisos, token, Functions desplegadas y configuración FCM. |
| 15 | Bloqueo de HomeWallet | Implementado | Activación/desactivación, autenticación biométrica o credencial configurada en Android, bloqueo al salir y solicitud al volver. La app no almacena la biometría. |
| 16 | Recuperación de contraseña | Implementado | Solicitud de restablecimiento mediante Firebase Authentication y acceso posterior con la nueva clave. La personalización visual del correo se hace en Firebase Console y no puede verificarse desde este repositorio. |
| 17 | Android para esta entrega | Implementado en configuración/documentación | README y flujo oficial declaran Android. La automatización iOS quedó manual y fuera del criterio de entrega; no se eliminó la base Flutter iOS. |
| 18 | Firebase / Firestore | Implementado y probado | Authentication, Firestore, Storage, Functions y FCM están conectados. Las claves de espacio tienen recuperación tras reinstalación: se validan contra el contenido cifrado, se envuelven con AES-256-GCM y un secreto de Secret Manager, y solo una Function las entrega a una cuenta verificada que siga siendo integrante activo. Firestore niega su lectura/escritura directa. La inicialización y exigencia de App Check permanecen desactivadas durante instalaciones directas; deben activarse gradualmente al publicar por Google Play. Ningún secreto de servidor se guarda en el repositorio. |
| 19 | Entornos Firebase | Comprobado | `.firebaserc` contiene un único proyecto real: `homewallet-prod`. No existen tres entornos dev/test/prod en este repositorio. |
| 20 | Seguridad y privacidad | Implementado | Aislamiento por espacio y rol en Firestore/Storage, contenido financiero cifrado antes de sincronizar, recuperación de clave protegida por autenticación, membresía y Secret Manager, funciones privilegiadas para invitaciones/roles/borrado, tokens FCM protegidos, archivos bancarios locales y texto legal coherente con el tratamiento de datos. |
| 21 | Eliminación de cuenta/datos | Implementado | Edición de perfil y solicitud de borrado con tres días hábiles para cancelar. La función elimina perfil/foto/Auth; elimina un espacio si queda vacío o transfiere propiedad antes de retirar la cuenta cuando hay otros integrantes. |
| 22 | Compatibilidad Android | Parcialmente comprobado | Configuración real: `minSdk 23`, `targetSdk 36`, `compileSdk 36`. Compilación e instalación se validan en emulador Android 17/API 37. La compatibilidad en dispositivos físicos/versiones adicionales necesita una matriz de dispositivos real. |
| 23 | Accesibilidad | Pendiente de prueba física formal | Se usan componentes Material, etiquetas, tooltips y controles estándar, pero no se marca como “aprobada” una prueba con TalkBack que no se ejecutó físicamente. |
| 24 | Rendimiento | Sin métricas inventadas | No se encontró una medición reproducible de P95. Las consultas conservan el historial completo del espacio y cada lote de importación admite hasta 500 movimientos; esto no equivale a una métrica de rendimiento. La tesis debe omitir o reformular cualquier cifra hasta medirla. |

## Validaciones locales ejecutadas

- `flutter analyze`: sin problemas.
- `flutter test`: 18 pruebas aprobadas, incluidas tema claro tras verificación, cuatro tipos/roles, Pareja completa sin nueva invitación, división proporcional, comparación mensual, historial sin corte arbitrario, deduplicación y exportación XLSX/PDF/CSV.
- `npm run build` en `functions`: compilación TypeScript aprobada.
- Firebase Emulator: 5 pruebas de reglas aprobadas (aislamiento, Individual sin divisiones, Jr. de solo lectura, selector activo autorizado y bloqueo directo de copias de clave) y 5 pruebas de Functions aprobadas (Individual único, más de cinco espacios, rol/revocación, concurrencia de Pareja, conservación de membresías y recuperación autorizada de clave).
- Firebase producción: reglas y Functions desplegadas; tareas programadas activas en `us-central1`, región compatible con Cloud Scheduler.
- Recuperación de cifrado: se retiró de forma controlada la clave local del emulador, se conservó la sesión y la app restauró automáticamente la clave desde producción; el espacio y sus importes volvieron a descifrarse sin QR.
- Auditoría agregada de producción: 4 espacios Individual; ninguno con integrantes, propietarios o conteos inválidos; ningún espacio activo inválido y ninguna cuenta con más de un Individual.
- Android release: APK `1.0.6+7` compilado y firma v1/v2 verificada. La instalación y los flujos entre dos teléfonos quedan como prueba manual final.

## Validaciones que requieren evidencia externa

- Recepción real de FCM y ejecución de Functions ya desplegadas.
- Flujo de invitación entre dos cuentas/dispositivos contra el proyecto desplegado.
- Importación con muestras reales de cada banco/formato, especialmente PDF y XLS antiguos.
- TalkBack y bloqueo biométrico en dispositivo físico.
- Matriz de versiones/dispositivos Android y medición P95 con una metodología definida.
- Plantilla visual de los correos de Firebase Authentication.
