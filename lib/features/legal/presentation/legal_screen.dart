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
              'Acuerdos claros para tu hogar',
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
                'HomeWallet es una herramienta de organización financiera personal y compartida. No es un banco, asesor financiero ni proveedor de crédito.',
                'Eres responsable de revisar que los movimientos, categorías, saldos, reportes e importaciones sean correctos antes de tomar decisiones.',
                'Debes mantener protegidos tu acceso y los códigos QR. Quien recibe una invitación puede acceder a los datos permitidos por su rol.',
                'El propietario administra integrantes y permisos. En hogares familiares, Integrante Jr es de solo lectura; los demás roles pueden realizar las acciones indicadas en la aplicación.',
                'No debes usar la aplicación para actividades ilícitas, acceder a cuentas ajenas ni cargar información que no estés autorizado a tratar.',
              ],
            ),
            const SizedBox(height: 14),
            const _LegalCard(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacidad y datos',
              paragraphs: [
                'Los detalles financieros se cifran en el dispositivo antes de guardarse. Las claves del hogar permanecen en los dispositivos autorizados y se comparten mediante una invitación QR temporal.',
                'Firebase procesa datos necesarios para autenticación, sincronización, almacenamiento de la foto y funcionamiento de la cuenta. HomeWallet no solicita tus credenciales bancarias para importar archivos.',
                'Los estados de cuenta se leen en el dispositivo. Solo los movimientos que confirmas se cifran y sincronizan con tu hogar.',
                'La foto de perfil es opcional. Puedes recortarla antes de subirla y reemplazarla cuando desees.',
              ],
            ),
            const SizedBox(height: 14),
            const _LegalCard(
              icon: Icons.delete_forever_outlined,
              title: 'Eliminación de cuenta',
              paragraphs: [
                'Puedes solicitar el borrado desde Mi perfil. La cuenta queda programada para eliminarse después de tres días hábiles.',
                'Durante ese plazo puedes cancelar la solicitud. Al ejecutarse, se elimina tu perfil, foto y acceso. Si eres la única persona de un hogar, también se elimina ese hogar; si existen integrantes, la propiedad se transfiere antes de retirar tu cuenta.',
                'El borrado es permanente una vez iniciado. Las copias técnicas temporales pueden conservarse únicamente durante los ciclos normales de respaldo y seguridad del proveedor.',
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
