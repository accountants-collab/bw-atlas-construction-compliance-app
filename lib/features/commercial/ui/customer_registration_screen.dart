import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/auth_state.dart';

class CustomerRegistrationScreen extends ConsumerStatefulWidget {
  const CustomerRegistrationScreen({super.key});

  @override
  ConsumerState<CustomerRegistrationScreen> createState() => _CustomerRegistrationScreenState();
}

class _CustomerRegistrationScreenState extends ConsumerState<CustomerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyName = TextEditingController();
  final _tradingName = TextEditingController();
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _cityTown = TextEditingController();
  final _postCode = TextEditingController();
  final _adminFullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _phone = TextEditingController();
  final _seatCount = TextEditingController(text: '5');

  @override
  void dispose() {
    _companyName.dispose();
    _tradingName.dispose();
    _addressLine1.dispose();
    _addressLine2.dispose();
    _cityTown.dispose();
    _postCode.dispose();
    _adminFullName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _phone.dispose();
    _seatCount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final seats = int.tryParse(_seatCount.text.trim()) ?? 0;
    await ref.read(authControllerProvider.notifier).registerCompany(
      companyName: _companyName.text,
      tradingName: _tradingName.text,
      address: [
        _addressLine1.text,
        _addressLine2.text,
        _cityTown.text,
        _postCode.text,
      ].where((p) => p.trim().isNotEmpty).join(', '),
      adminFullName: _adminFullName.text,
      adminEmail: _email.text,
      password: _password.text,
      confirmPassword: _confirmPassword.text,
      phone: _phone.text,
      seats: seats,
    );

    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    if (auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company workspace created successfully.')),
      );
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Start Registration')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create Your Company Workspace',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Create a real company workspace and your first manager account.',
                      style: TextStyle(color: Colors.white, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (auth.error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF5350)),
                  ),
                  child: Text(
                    auth.error!,
                    style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Registration Details',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _companyName,
                          decoration: const InputDecoration(
                            labelText: 'Company Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Company name is required.' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _tradingName,
                          decoration: const InputDecoration(
                            labelText: 'Trading Name (optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.storefront_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressLine1,
                          decoration: const InputDecoration(
                            labelText: 'Address line 1 (optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressLine2,
                          decoration: const InputDecoration(
                            labelText: 'Address line 2 (optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.pin_drop_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _cityTown,
                          decoration: const InputDecoration(
                            labelText: 'City / Town (optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_city_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _postCode,
                          decoration: const InputDecoration(
                            labelText: 'Post code (optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.markunread_mailbox_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _adminFullName,
                          decoration: const InputDecoration(
                            labelText: 'Admin / Manager Full Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Admin / Manager full name is required.' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Admin Email',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Email is required.';
                            final isValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                            if (!isValid) return 'Please enter a valid email.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().length < 6) {
                              return 'Password must be at least 6 characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPassword,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm Password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return 'Confirm password is required.';
                            if ((v ?? '') != _password.text) return 'Passwords do not match.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Phone is required.' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _seatCount,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'Team size (initial plan)',
                            hintText: 'Examples: 5, 10, 20, 50, 100',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.groups_outlined),
                          ),
                          validator: (v) {
                            final parsed = int.tryParse((v ?? '').trim());
                            if (parsed == null || parsed < 1) {
                              return 'Enter a valid team size (minimum 1).';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFFD54F)),
                          ),
                          child: const Text(
                            'Your team size determines how many team members can use the app. Upgrade your plan anytime from Team / Users settings to add more team members.',
                            style: TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: auth.isLoading ? null : _submit,
                            icon: const Icon(Icons.arrow_forward_outlined),
                            label: auth.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Continue Registration'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
