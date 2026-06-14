import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_state.dart';
import '../../../auth/auth_service.dart';

class ManagerInvitesScreen extends ConsumerStatefulWidget {
  const ManagerInvitesScreen({super.key});

  @override
  ConsumerState<ManagerInvitesScreen> createState() => _ManagerInvitesScreenState();
}

class _ManagerInvitesScreenState extends ConsumerState<ManagerInvitesScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  InviteRole _role = InviteRole.manager;
  String? _lastLink;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Invites')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Company: ${auth.companyId ?? "-"}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<InviteRole>(
                    initialValue: _role,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: InviteRole.admin, child: Text('Admin')),
                      DropdownMenuItem(value: InviteRole.manager, child: Text('Manager')),
                      DropdownMenuItem(value: InviteRole.worker, child: Text('Worker')),
                    ],
                    onChanged: auth.isLoading
                        ? null
                        : (value) {
                            if (value != null) setState(() => _role = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: auth.isLoading
                        ? null
                        : () async {
                            final link = await ref.read(authControllerProvider.notifier).createInviteLink(
                                  invitedName: _name.text.trim(),
                                  invitedEmail: _email.text.trim(),
                                  role: _role,
                                );

                            setState(() => _lastLink = link);
                          },
                    child: auth.isLoading ? const Text('...') : const Text('Generate invite link'),
                  ),
                  if (_lastLink != null) ...[
                    const SizedBox(height: 16),
                    SelectableText(_lastLink!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}