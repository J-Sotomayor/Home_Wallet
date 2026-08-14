import 'package:flutter/material.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  static const version = '2026-08-02';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Términos y privacidad')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          children: [
            Icon(
              Icons.gavel_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Acuerdos claros para tu espacio financiero',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            const Text(
              'Versión 2 de agosto de 2026',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const _LegalCard(
              icon: Icons.description_outlined,
              title: 'Términos y condiciones',
              paragraphs: [
                'HomeWallet es una herramienta de organización financiera personal y compartida. No es un banco, asesor financiero, contador, proveedor de crédito ni entidad supervisada por la Superintendencia de Bancos.',
                'Los movimientos, reportes y archivos exportados son registros informativos. No sustituyen estados de cuenta emitidos por una institución financiera, facturas, comprobantes autorizados por el SRI ni documentación contable o tributaria.',
                'Eres responsable de revisar que los movimientos, categorías, fechas, saldos, reportes e importaciones sean correctos antes de tomar decisiones.',
                'Debes mantener protegidos tu acceso y los códigos QR. Quien recibe una invitación puede acceder a los datos permitidos por su rol.',
                'El propietario administra integrantes y permisos. En espacios Familia, Integrante Jr es de solo lectura; los demás roles pueden realizar las acciones indicadas en la aplicación.',
                'No debes usar la aplicación para actividades ilícitas, acceder a cuentas ajenas ni cargar información que no estés autorizado a tratar.',
              ],
            ),
            const SizedBox(height: 14),
            const _LegalCard(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacidad y datos',
              paragraphs: [
                'HomeWallet trata datos de cuenta y contacto, pertenencia y rol en el espacio, información financiera que registras, identificadores técnicos del dispositivo, preferencias, foto opcional y diagnósticos de fallos necesarios para operar y proteger el servicio.',
                'Las finalidades son autenticarte, sincronizar tu espacio, calcular saldos y planes, importar o exportar datos cuando lo solicitas, enviar avisos que habilitas, prevenir abuso, resolver fallos y atender la eliminación de la cuenta.',
                'Los detalles financieros se cifran en el dispositivo antes de guardarse. Las claves del espacio permanecen en los dispositivos autorizados y se comparten mediante una invitación QR temporal.',
                'Firebase procesa datos necesarios para autenticación, sincronización, funciones del servidor, notificaciones, almacenamiento de la foto y diagnóstico de errores. Su infraestructura puede implicar tratamiento fuera de Ecuador conforme a la configuración y garantías contractuales del proveedor.',
                'HomeWallet no solicita ni almacena tus credenciales bancarias para importar archivos.',
                'Los estados de cuenta se leen en el dispositivo. Solo los movimientos que confirmas se cifran y sincronizan con tu espacio.',
                'La foto de perfil y las notificaciones son opcionales. La aplicación solicita esos permisos únicamente cuando eliges usar cada función.',
              ],
            ),
            const SizedBox(height: 14),
            const _LegalCard(
              icon: Icons.manage_accounts_outlined,
              title: 'Tus controles y derechos',
              paragraphs: [
                'Puedes consultar tus datos dentro de la aplicación, corregir tu perfil y los registros autorizados, exportar tus movimientos desde Reportes y retirar permisos opcionales desde la configuración del dispositivo.',
                'Puedes solicitar la eliminación de la cuenta desde Mi perfil. Si necesitas ejercer acceso, rectificación, actualización, eliminación, oposición, suspensión o portabilidad de datos que no puedas gestionar directamente, utiliza el canal de privacidad publicado en la ficha oficial de HomeWallet.',
                'Eliminar un movimiento cambia los saldos y el avance relacionado para todos los integrantes del espacio y no se puede deshacer. La aplicación solicita confirmación antes de hacerlo.',
              ],
            ),
            const SizedBox(height: 14),
            const _LegalCard(
              icon: Icons.child_care_outlined,
              title: 'Espacios con menores',
              paragraphs: [
                'Integrante Jr está diseñado como una experiencia educativa y de consulta. No puede registrar, modificar ni eliminar información financiera.',
                'El propietario del espacio es responsable de invitar al menor, asignar su rol y contar con la autorización que corresponda. No deben cargarse datos innecesarios o sensibles del menor.',
              ],
            ),
            const SizedBox(height: 14),
            const _LegalCard(
              icon: Icons.delete_forever_outlined,
              title: 'Eliminación de cuenta',
              paragraphs: [
                'Puedes solicitar el borrado desde Mi perfil. La cuenta queda programada para eliminarse después de tres días hábiles.',
                'Durante ese plazo puedes cancelar la solicitud. Al ejecutarse, se elimina tu perfil, foto y acceso. Si eres la única persona de un espacio, también se elimina ese espacio; si existen integrantes, la propiedad se transfiere antes de retirar tu cuenta.',
                'Mientras la cuenta permanezca activa se conservan los datos necesarios para prestar el servicio. El borrado es permanente una vez iniciado; las copias técnicas temporales pueden persistir únicamente durante los ciclos normales de respaldo, seguridad y cumplimiento del proveedor.',
              ],
            ),
            const SizedBox(height: 14),
            const _LegalCard(
              icon: Icons.update_outlined,
              title: 'Cambios y contacto',
              paragraphs: [
                'Si estos términos cambian de manera importante, la aplicación mostrará una nueva versión para revisión y aceptación.',
                'Para soporte, utiliza el canal de contacto indicado en la sección Acerca de HomeWallet.',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalCard extends StatelessWidget {
  const _LegalCard({
    required this.icon,
    required this.title,
    required this.paragraphs,
  });

  final IconData icon;
  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...paragraphs.map(
            (paragraph) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(paragraph),
            ),
          ),
        ],
      ),
    ),
  );
}
