import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_service.dart';
import 'auth_state.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _submitting = false;
  String? _info;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).requestPasswordReset(
            email: _email.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _info = 'If this email exists, a reset link has been sent. Please check your inbox and spam folder.';
      });
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to send reset email. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reset your password',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text('Enter your account email and we will send you a reset link.'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final email = (value ?? '').trim();
                        final re = RegExp(r'^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$');
                        if (email.isEmpty) return 'Email is required.';
                        if (!re.hasMatch(email)) return 'Enter a valid email address.';
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 10),
                      Text(_info!, style: const TextStyle(color: Color(0xFF2E7D32))),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: Text(_submitting ? 'Sending...' : 'Send Reset Link'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: _submitting ? null : () => context.go('/login'),
                        child: const Text('Back to Sign In'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
