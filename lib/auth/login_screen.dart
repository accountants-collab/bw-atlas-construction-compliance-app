import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/ui/branding_resolver.dart';
import 'auth_state.dart';
import 'quick_login_dialogs.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _rememberMe = false;
  bool _showPassword = false;
  bool _quickLoginReady = false;
  bool _quickBiometricEnabled = false;
  bool _quickBiometricAvailable = false;
  bool _quickHasPin = false;
  bool _showEmailPasswordForm = false;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _restoreRememberedLogin();
    _loadQuickLoginStatus();
  }

  Future<void> _restoreRememberedLogin() async {
    final service = ref.read(authServiceProvider);
    final remembered = await service.isRememberMeEnabled();
    final rememberedEmail = await service.getRememberedEmail();
    if (!mounted) return;
    setState(() {
      _rememberMe = remembered;
      if (rememberedEmail.isNotEmpty) {
        _email.text = rememberedEmail;
      }
    });
  }

  Future<void> _loadQuickLoginStatus() async {
    final quick = ref.read(quickLoginServiceProvider);
    final status = await quick.getStatus();
    final hasQuickLogin = status.enabled &&
        (status.hasPin || (status.biometricEnabled && status.canUseBiometrics));
    if (!mounted) return;
    setState(() {
      _quickLoginReady = status.enabled;
      _quickBiometricEnabled = status.biometricEnabled;
      _quickBiometricAvailable = status.canUseBiometrics;
      _quickHasPin = status.hasPin;
      if (!hasQuickLogin) {
        _showEmailPasswordForm = true;
      }
    });
  }

  Future<void> _signInWithBiometric(AuthController ctrl, AuthState auth) async {
    if (auth.isLoading) return;
    final quick = ref.read(quickLoginServiceProvider);
    final ok = await quick.authenticateWithBiometrics();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Biometric authentication failed. Use PIN or normal sign in.')),
      );
      return;
    }
    await ctrl.signInWithQuickLogin();
  }

  Future<void> _signInWithPin(AuthController ctrl, AuthState auth) async {
    if (auth.isLoading) return;
    final pin = await QuickLoginDialogs.showEnterPinDialog(context);
    if (!mounted || pin == null) return;

    final quick = ref.read(quickLoginServiceProvider);
    final valid = await quick.verifyPin(pin);
    if (!mounted) return;
    if (!valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Incorrect PIN. Use normal sign in to continue.')),
      );
      return;
    }
    await ctrl.signInWithQuickLogin();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit(AuthController ctrl, AuthState auth) {
    if (auth.isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    ctrl.signIn(
        email: _email.text, password: _password.text, rememberMe: _rememberMe);
  }

  void _handleBackButton() {
    final now = DateTime.now();
    final isDoublePress = _lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2);

    if (isDoublePress) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    _lastBackPress = now;
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit BW Atlas'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);
    final showQuickLoginSection = !kIsWeb &&
        _quickLoginReady &&
        (_quickHasPin || (_quickBiometricEnabled && _quickBiometricAvailable));
    final showCredentialForm = !showQuickLoginSection || _showEmailPasswordForm;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackButton();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE3F0FF),
        body: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 460,
                minHeight: MediaQuery.of(context).size.height,
              ),
              child: Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Card(
                    elevation: 4,
                    color: const Color(0xFFF5F9FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: Color(0xFFBDD4F0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo / Branding
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: SizedBox(
                                height: 180,
                                child: Image.asset(
                                  kDefaultSystemLogoAssetPath,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stack) =>
                                      const Icon(
                                    Icons.local_fire_department,
                                    size: 120,
                                    color: Color(0xFF1565C0),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (auth.error != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFEF5350)),
                                ),
                                child: Text(
                                  auth.error!,
                                  style: const TextStyle(
                                      color: Color(0xFFC62828),
                                      fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (showQuickLoginSection) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFFA5D6A7)),
                                ),
                                child: const Text(
                                  'Use your quick login method for this device.',
                                  style: TextStyle(
                                    color: Color(0xFF2E7D32),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (!kIsWeb) ...[
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: auth.isLoading || !_quickHasPin
                                      ? null
                                      : () => _signInWithPin(ctrl, auth),
                                  icon: const Icon(Icons.pin_outlined),
                                  label: const Text(
                                    'Quick Login with PIN',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                            if (!kIsWeb &&
                                _quickBiometricEnabled &&
                                _quickBiometricAvailable) ...[
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () => _signInWithBiometric(ctrl, auth),
                                  icon: const Icon(Icons.fingerprint_outlined),
                                  label: const Text(
                                    'Quick Login with Biometrics',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                            if (!kIsWeb &&
                                _quickBiometricEnabled &&
                                !_quickBiometricAvailable) ...[
                              const SizedBox(
                                height: 8,
                              ),
                              const Text(
                                'Biometric login is unavailable on this device. Use PIN or email/password.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.black54),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 14),
                            if (showCredentialForm) ...[
                              TextFormField(
                                controller: _email,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty)
                                    return 'Email is required.';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _password,
                                focusNode: _passwordFocus,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                obscureText: !_showPassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(ctrl, auth),
                                validator: (v) {
                                  if ((v ?? '').trim().isEmpty) {
                                    return 'Password is required.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () => context.go('/forgot-password'),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                              const SizedBox(height: 4),
                              CheckboxListTile(
                                value: _rememberMe,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text('Remember me'),
                                onChanged: auth.isLoading
                                    ? null
                                    : (v) => setState(
                                        () => _rememberMe = v ?? false),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () => _submit(ctrl, auth),
                                  child: auth.isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : const Text(
                                          'Sign In',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700),
                                        ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: auth.isLoading
                                    ? null
                                    : () => context.go('/register'),
                                icon:
                                    const Icon(Icons.person_add_alt_1_outlined),
                                label: const Text(
                                  'Register Company',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            const Text(
                              'Use your registered company admin account to sign in.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.black38),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
