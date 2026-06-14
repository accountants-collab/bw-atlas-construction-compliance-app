import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_drawer.dart';
import '../../../auth/auth_state.dart';

class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.currentUser;
    final role = _roleLabel(auth.actualRole ?? auth.userRole ?? UserRole.worker);

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      drawer: const AppDrawer(currentRoute: '/account/profile'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personal Information',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: 'Full Name',
                    value: (user?.name.trim().isNotEmpty ?? false) ? user!.name.trim() : '-',
                  ),
                  _InfoRow(
                    label: 'Email',
                    value: auth.email.trim().isNotEmpty ? auth.email.trim() : '-',
                  ),
                  _InfoRow(label: 'Role', value: role),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Company details are managed separately in Company Details.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _roleLabel(UserRole role) {
  switch (role) {
    case UserRole.owner:
      return 'Owner';
    case UserRole.admin:
      return 'Admin';
    case UserRole.manager:
      return 'Manager';
    case UserRole.worker:
      return 'Worker';
    case UserRole.superAdmin:
      return 'Super Admin';
  }
}
