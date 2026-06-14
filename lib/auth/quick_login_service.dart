import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class QuickLoginStatus {
  final bool enabled;
  final bool biometricEnabled;
  final bool hasPin;
  final bool canUseBiometrics;

  const QuickLoginStatus({
    required this.enabled,
    required this.biometricEnabled,
    required this.hasPin,
    required this.canUseBiometrics,
  });
}

class QuickLoginService {
  static const _keyEnabled = 'quick_login_enabled';
  static const _keyBiometricEnabled = 'quick_login_biometric_enabled';
  static const _keyPinSalt = 'quick_login_pin_salt';
  static const _keyPinHash = 'quick_login_pin_hash';
  static const _keyUserId = 'quick_login_user_id';

  static final _pinRegex = RegExp(r'^\d{4}$');

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  QuickLoginService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _localAuth = localAuth ?? LocalAuthentication();

  bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<QuickLoginStatus> getStatus() async {
    if (!isSupportedPlatform) {
      return const QuickLoginStatus(
        enabled: false,
        biometricEnabled: false,
        hasPin: false,
        canUseBiometrics: false,
      );
    }

    final enabled = await isQuickLoginEnabled();
    final biometricEnabled = await isBiometricEnabled();
    final hasPin = await hasPinConfigured();
    final canUseBiometrics = await canUseBiometricAuth();

    return QuickLoginStatus(
      enabled: enabled,
      biometricEnabled: biometricEnabled,
      hasPin: hasPin,
      canUseBiometrics: canUseBiometrics,
    );
  }

  Future<bool> isQuickLoginEnabled() async {
    if (!isSupportedPlatform) return false;
    return (await _storage.read(key: _keyEnabled)) == 'true';
  }

  Future<bool> isBiometricEnabled() async {
    if (!isSupportedPlatform) return false;
    return (await _storage.read(key: _keyBiometricEnabled)) == 'true';
  }

  Future<bool> hasPinConfigured() async {
    if (!isSupportedPlatform) return false;
    final salt = await _storage.read(key: _keyPinSalt);
    final hash = await _storage.read(key: _keyPinHash);
    return (salt ?? '').isNotEmpty && (hash ?? '').isNotEmpty;
  }

  Future<String?> getLinkedUserId() async {
    if (!isSupportedPlatform) return null;
    return _storage.read(key: _keyUserId);
  }

  Future<bool> canUseBiometricAuth() async {
    if (!isSupportedPlatform) return false;
    try {
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!isDeviceSupported || !canCheckBiometrics) return false;
      final enrolled = await _localAuth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    if (!isSupportedPlatform) return false;
    final canUse = await canUseBiometricAuth();
    if (!canUse) return false;

    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to quick sign in',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: false,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> enableQuickLogin({
    required String userId,
    required String pin,
    required bool biometricEnabled,
  }) async {
    if (!isSupportedPlatform) return;
    _ensurePin(pin);

    final salt = _generateSalt();
    final hash = _pinHash(pin: pin, salt: salt);

    await _storage.write(key: _keyUserId, value: userId.trim());
    await _storage.write(key: _keyPinSalt, value: salt);
    await _storage.write(key: _keyPinHash, value: hash);
    await _storage.write(key: _keyEnabled, value: 'true');
    await _storage.write(
      key: _keyBiometricEnabled,
      value: biometricEnabled ? 'true' : 'false',
    );
  }

  Future<void> setPin(String pin) async {
    if (!isSupportedPlatform) return;
    _ensurePin(pin);

    final salt = _generateSalt();
    final hash = _pinHash(pin: pin, salt: salt);
    await _storage.write(key: _keyPinSalt, value: salt);
    await _storage.write(key: _keyPinHash, value: hash);
    await _storage.write(key: _keyEnabled, value: 'true');
  }

  Future<bool> verifyPin(String pin) async {
    if (!isSupportedPlatform) return false;
    _ensurePin(pin);

    final salt = await _storage.read(key: _keyPinSalt);
    final savedHash = await _storage.read(key: _keyPinHash);
    if ((salt ?? '').isEmpty || (savedHash ?? '').isEmpty) return false;

    final candidate = _pinHash(pin: pin, salt: salt!);
    return candidate == savedHash;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (!isSupportedPlatform) return;
    await _storage.write(
      key: _keyBiometricEnabled,
      value: enabled ? 'true' : 'false',
    );
    await _storage.write(key: _keyEnabled, value: 'true');
  }

  Future<void> disableQuickLogin() async {
    if (!isSupportedPlatform) return;
    await _storage.delete(key: _keyEnabled);
    await _storage.delete(key: _keyBiometricEnabled);
    await _storage.delete(key: _keyPinSalt);
    await _storage.delete(key: _keyPinHash);
    await _storage.delete(key: _keyUserId);
  }

  void _ensurePin(String pin) {
    final normalized = pin.trim();
    if (!_pinRegex.hasMatch(normalized)) {
      throw const FormatException('PIN must be exactly 4 digits.');
    }
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _pinHash({required String pin, required String salt}) {
    final input = utf8.encode('${pin.trim()}:$salt');
    return sha256.convert(input).toString();
  }
}
