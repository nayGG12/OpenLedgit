import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum PinVerificationResult { success, incorrect, lockedOut }

class AppLockService {
  AppLockService._();

  static const _pinKey = 'app_lock_pin';
  static const _setupCompletedKey = 'app_lock_setup_completed';
  static const _failedAttemptsKey = 'app_lock_failed_attempts';
  static const _lockedUntilKey = 'app_lock_locked_until';
  static const _maxAttempts = 5;
  static const _lockoutDuration = Duration(seconds: 30);

  static const _storage = FlutterSecureStorage();
  static final _localAuth = LocalAuthentication();

  static Future<String?> getPin() => _storage.read(key: _pinKey);

  static Future<bool> isSetupCompleted() async {
    if (await getPin() != null) return true;
    return await _storage.read(key: _setupCompletedKey) == 'true';
  }

  static Future<void> savePin(String pin) async {
    _validatePin(pin);
    await _storage.write(key: _pinKey, value: pin);
    await _storage.write(key: _setupCompletedKey, value: 'true');
    await _clearFailedAttempts();
  }

  static Future<void> skipSetup() =>
      _storage.write(key: _setupCompletedKey, value: 'true');

  static Future<bool> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    _validatePin(newPin);
    if (await getPin() != currentPin) return false;
    await savePin(newPin);
    return true;
  }

  static Future<PinVerificationResult> verifyPin(String pin) async {
    final lockedUntilValue = await _storage.read(key: _lockedUntilKey);
    final lockedUntilMilliseconds = int.tryParse(lockedUntilValue ?? '');
    if (lockedUntilMilliseconds != null) {
      final remaining = DateTime.fromMillisecondsSinceEpoch(
        lockedUntilMilliseconds,
      ).difference(DateTime.now());
      if (remaining > Duration.zero) return PinVerificationResult.lockedOut;
      await _clearFailedAttempts();
    }

    if (await getPin() == pin) {
      await _clearFailedAttempts();
      return PinVerificationResult.success;
    }

    final attemptsValue = await _storage.read(key: _failedAttemptsKey);
    final attempts = (int.tryParse(attemptsValue ?? '') ?? 0) + 1;
    if (attempts >= _maxAttempts) {
      await _storage.write(
        key: _lockedUntilKey,
        value: DateTime.now()
            .add(_lockoutDuration)
            .millisecondsSinceEpoch
            .toString(),
      );
      await _storage.delete(key: _failedAttemptsKey);
      return PinVerificationResult.lockedOut;
    }

    await _storage.write(key: _failedAttemptsKey, value: attempts.toString());
    return PinVerificationResult.incorrect;
  }

  static Future<bool> hasBiometrics() async {
    final biometrics = await _localAuth.getAvailableBiometrics();
    return biometrics.isNotEmpty;
  }

  static Future<bool> authenticateBiometrics() {
    return _localAuth.authenticate(
      localizedReason: 'Déverrouillez OpenLedger',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );
  }

  static Future<void> _clearFailedAttempts() async {
    await _storage.delete(key: _failedAttemptsKey);
    await _storage.delete(key: _lockedUntilKey);
  }

  static void _validatePin(String pin) {
    if (!RegExp(r'^\d{4}(\d{2})?$').hasMatch(pin)) {
      throw ArgumentError('Le code PIN doit contenir 4 ou 6 chiffres.');
    }
  }
}
