import '../../core/security/biometric_lock_service.dart';
import '../../core/security/household_crypto_service.dart';
import '../../core/security/secure_key_store.dart';
import '../../core/notifications/notification_service.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/households/data/household_repository.dart';
import '../../features/transactions/data/finance_repository.dart';

class AppServices {
  const AppServices({
    required this.auth,
    required this.households,
    required this.finance,
    required this.biometricLock,
    this.notifications,
  });

  factory AppServices.firebase() {
    final keyStore = DeviceSecureKeyStore();
    final crypto = HouseholdCryptoService();
    return AppServices(
      auth: FirebaseAuthRepository(),
      households: FirebaseHouseholdRepository(
        keyStore: keyStore,
        crypto: crypto,
      ),
      finance: FirebaseFinanceRepository(keyStore: keyStore, crypto: crypto),
      biometricLock: BiometricLockService(keyStore: keyStore),
      notifications: NotificationService(),
    );
  }

  final AuthRepository auth;
  final HouseholdRepository households;
  final FinanceRepository finance;
  final BiometricLockService biometricLock;
  final NotificationService? notifications;
}
