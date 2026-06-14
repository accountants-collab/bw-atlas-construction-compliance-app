import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_service.dart';
import 'auth_state.dart';

class AcceptInviteScreen extends ConsumerStatefulWidget {
  final String token;

  const AcceptInviteScreen({required this.token, super.key});

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Accept Invitation')),
      body: FutureBuilder<InviteAcceptanceContext>(
        future: ctrl.getInviteContext(widget.token),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            final message = snapshot.error is AuthFailure
                ? (snapshot.error as AuthFailure).message
                : 'This invitation is invalid or expired.';
            return _ErrorState(message: message);
          }

          final contextData = snapshot.data!;
          final invite = contextData.invite;
          final company = contextData.company;
          if (_email.text.trim().isEmpty) {
            _email.text = invite.invitedEmail;
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Join ${company.companyName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text('Invitation for ${invite.invitedName} as ${_roleLabel(invite.invitedRole)}.'),
                        const SizedBox(height: 4),
                        Text('Set your password to activate your account.', style: TextStyle(color: Colors.grey.shade700)),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _email,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Invited Email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Create Password',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _confirm,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm Password',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (auth.error != null) ...[
                          const SizedBox(height: 10),
                          Text(auth.error!, style: const TextStyle(color: Colors.red)),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _submitting
                                ? null
                                : () async {
                                    setState(() => _submitting = true);
                                    await ctrl.acceptInviteToken(
                                      token: widget.token,
                                      email: _email.text.trim(),
                                      password: _password.text,
                                      confirmPassword: _confirm.text,
                                    );
                                    if (!context.mounted) return;
                                    setState(() => _submitting = false);
                                    final updated = ref.read(authControllerProvider);
                                    if (updated.isLoggedIn) {
                                      context.go('/dashboard');
                                    }
                                  },
                            child: Text(_submitting ? 'Activating account...' : 'Accept Invite & Set Password'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _roleLabel(InviteRole role) {
  switch (role) {
    case InviteRole.admin:
      return 'Admin';
    case InviteRole.manager:
      return 'Manager';
    case InviteRole.worker:
      return 'Worker';
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    final lower = message.toLowerCase();
    final isAlreadyUsed = lower.contains('already used');
    final isExpired = lower.contains('expired');
    final title = isAlreadyUsed
        ? 'Invitation Already Used'
        : isExpired
            ? 'Invitation Expired'
            : 'Invalid Invitation';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 36),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/login'),
              child: Text(isAlreadyUsed ? 'Go to Login' : 'Back to Login'),
            ),
          ],
        ),
      ),
    );
  }
}
