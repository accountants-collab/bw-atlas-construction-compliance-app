import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_drawer.dart';
import '../../../auth/auth_service.dart';
import '../../../auth/auth_state.dart';

class SuperAdminPanelScreen extends ConsumerWidget {
  const SuperAdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    if (auth.actualRole != UserRole.superAdmin) {
      return const Scaffold(
        body: Center(
          child: Text('Access denied. Super admin account required.'),
        ),
      );
    }

    final companiesAsync = ref.watch(allCompaniesProvider);
    final allUsersAsync = ref.watch(allUsersProvider);
    final companyUsersAsync = ref.watch(companyUsersProvider);
    final seatSummaryAsync = ref.watch(companySeatSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Platform Super Admin')),
      drawer: const AppDrawer(currentRoute: '/platform/admin'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFE3F2FD),
            child: const ListTile(
              leading: Icon(Icons.security_outlined, color: Color(0xFF1565C0)),
              title: Text(
                'Platform scope enabled',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('This account can switch company context and manage users across companies.'),
            ),
          ),
          const SizedBox(height: 12),
          companiesAsync.when(
            data: (companies) {
              final activeCompanyId = auth.companyId;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Company context', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: activeCompanyId,
                        decoration: const InputDecoration(
                          labelText: 'Active company',
                          border: OutlineInputBorder(),
                        ),
                        items: companies
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c.companyId,
                                child: Text('${c.companyName} (${c.companyId})'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) async {
                          if (value == null) return;
                          try {
                            await ref.read(authControllerProvider.notifier).switchCompanyContext(value);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Company context switched.')),
                            );
                          } on AuthFailure catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Card(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            error: (_, __) => const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Failed to load companies.'))),
          ),
          const SizedBox(height: 12),
          allUsersAsync.when(
            data: (allUsers) {
              final managerCount = allUsers.where((u) => u.role == UserRole.manager).length;
              final workerCount = allUsers.where((u) => u.role == UserRole.worker).length;
              final superAdminCount = allUsers.where((u) => u.role == UserRole.superAdmin).length;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CountChip(label: 'Companies', value: ref.read(allCompaniesProvider).valueOrNull?.length ?? 0),
                      _CountChip(label: 'All Users', value: allUsers.length),
                      _CountChip(label: 'Managers', value: managerCount),
                      _CountChip(label: 'Workers', value: workerCount),
                      _CountChip(label: 'Super Admin', value: superAdminCount),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          seatSummaryAsync.when(
            data: (seatSummary) {
              if (seatSummary == null) return const SizedBox.shrink();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.event_seat_outlined),
                  title: Text(
                    'Active company seats: ${seatSummary.activeUsers}/${seatSummary.seatLimit}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text('Available seats: ${seatSummary.availableSeats}'),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          const Text('Users in active company', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          companyUsersAsync.when(
            data: (users) {
              if (users.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No users in selected company.'),
                  ),
                );
              }

              return Column(
                children: users
                    .map(
                      (u) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(u.name),
                          subtitle: Text('${u.email}\nRole: ${u.role.name} • Status: ${u.status.name}'),
                          isThreeLine: true,
                          trailing: u.isInternalAdmin
                              ? const Chip(label: Text('Internal'))
                              : TextButton(
                                  onPressed: () async {
                                    final nextStatus = u.status == UserAccountStatus.active
                                        ? UserAccountStatus.inactive
                                        : UserAccountStatus.active;
                                    try {
                                      await ref.read(authControllerProvider.notifier).setUserStatus(
                                            userId: u.id,
                                            status: nextStatus,
                                          );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('${u.name} set to ${nextStatus.name}.')),
                                      );
                                    } on AuthFailure catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e.message)),
                                      );
                                    }
                                  },
                                  child: Text(u.status == UserAccountStatus.active ? 'Deactivate' : 'Activate'),
                                ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            )),
            error: (_, __) => const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Failed to load users.'))),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int value;

  const _CountChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F0FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Color(0xFF1565C0),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
