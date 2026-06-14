import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_state.dart';
import '../../../auth/quick_login_dialogs.dart';
import '../../../auth/quick_login_service.dart';

class QuickLoginSettingsScreen extends ConsumerStatefulWidget {
  const QuickLoginSettingsScreen({super.key});

  @override
  ConsumerState<QuickLoginSettingsScreen> createState() => _QuickLoginSettingsScreenState();
}

class _QuickLoginSettingsScreenState extends ConsumerState<QuickLoginSettingsScreen> {
  bool _loading = true;
  QuickLoginStatus _status = const QuickLoginStatus(
    enabled: false,
    biometricEnabled: false,
    hasPin: false,
    canUseBiometrics: false,
  );

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final service = ref.read(quickLoginServiceProvider);
    final status = await service.getStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _setupQuickLogin() async {
    final auth = ref.read(authControllerProvider);
    final userId = auth.uid;
    if (userId.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to configure quick login.')),
      );
      return;
    }

    final pin = await QuickLoginDialogs.showCreatePinDialog(context);
    if (!mounted || pin == null) return;

    final service = ref.read(quickLoginServiceProvider);
    final canBio = await service.canUseBiometricAuth();
    bool enableBiometric = false;

    if (canBio && mounted) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable biometric login?'),
          content: const Text('Use fingerprint or face unlock as quick sign-in method.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      enableBiometric = answer == true;
    }

    await service.enableQuickLogin(
      userId: userId,
      pin: pin,
      biometricEnabled: enableBiometric,
    );

    await _loadStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Quick login enabled.')),
    );
  }

  Future<void> _changePin() async {
    final pin = await QuickLoginDialogs.showCreatePinDialog(context, title: 'Change 4-digit PIN');
    if (!mounted || pin == null) return;

    final service = ref.read(quickLoginServiceProvider);
    await service.setPin(pin);
    await _loadStatus();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN updated.')),
    );
  }

  Future<void> _toggleBiometric(bool enabled) async {
    final service = ref.read(quickLoginServiceProvider);
    if (enabled) {
      final canBio = await service.canUseBiometricAuth();
      if (!canBio) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric authentication is not available on this device.')),
        );
        return;
      }
    }

    await service.setBiometricEnabled(enabled);
    await _loadStatus();
  }

  Future<void> _disableQuickLogin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable quick login?'),
        content: const Text('Biometric and PIN quick login will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final service = ref.read(quickLoginServiceProvider);
    await service.disableQuickLogin();
    await _loadStatus();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Quick login disabled.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quick = ref.read(quickLoginServiceProvider);
    if (kIsWeb || !quick.isSupportedPlatform) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quick Login')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('Quick login is available on Android and iOS only.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Quick Login')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _status.enabled ? 'Quick login is enabled.' : 'Quick login is currently disabled.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text('Use biometric authentication and/or a 4-digit PIN for faster sign-in on this device.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!_status.enabled)
                  FilledButton.icon(
                    onPressed: _setupQuickLogin,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('Enable quick login'),
                  ),
                if (_status.enabled) ...[
                  SwitchListTile(
                    value: _status.biometricEnabled,
                    onChanged: _toggleBiometric,
                    title: const Text('Enable biometric login'),
                    subtitle: Text(
                      _status.canUseBiometrics
                          ? 'Use fingerprint or face unlock on this device.'
                          : 'Biometric auth is not available on this device.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _changePin,
                    icon: const Icon(Icons.pin_outlined),
                    label: Text(_status.hasPin ? 'Change 4-digit PIN' : 'Set 4-digit PIN'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _disableQuickLogin,
                    icon: const Icon(Icons.lock_reset_outlined),
                    label: const Text('Disable quick login'),
                  ),
                ],
              ],
            ),
    );
  }
}
