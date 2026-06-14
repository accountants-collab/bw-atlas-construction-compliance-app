import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_drawer.dart';
import '../../../auth/auth_state.dart';
import '../state/settings_controller.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  final _customSeatCtrl = TextEditingController();

  @override
  void dispose() {
    _customSeatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.watch(settingsControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);
    final canEdit = auth.actualRole == UserRole.owner || auth.actualRole == UserRole.superAdmin;

    _customSeatCtrl.text = settings.seatLimit.toString();
    _customSeatCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _customSeatCtrl.text.length),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription / Billing'),
      ),
      drawer: const AppDrawer(currentRoute: '/company/subscription'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current status card
          Card(
            color: const Color(0xFFE3F0FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFBDD4F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_outlined, color: Color(0xFF1565C0), size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${settings.seatLimit} user seat${settings.seatLimit == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${settings.activeSeatsUsed} active · ${settings.seatLimit - settings.activeSeatsUsed} available',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (canEdit) ...[
            const SizedBox(height: 20),
            const Text(
              'Number of users / seats',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter the seat count directly. Minimum is 1.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customSeatCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Number of users / seats',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () {
                    final n = int.tryParse(_customSeatCtrl.text.trim()) ?? 0;
                    if (n < 1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a number of at least 1.')),
                      );
                      return;
                    }
                    ctrl.setCustomSeatCount(n);
                  },
                  child: const Text('Set'),
                ),
              ],
            ),

            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Upgrade / Payment',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Contact your account administrator to upgrade your plan or purchase additional seats.',
              style: TextStyle(color: Colors.black54),
            ),
          ] else ...[
            const SizedBox(height: 20),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline, color: Color(0xFF607D9B)),
                title: const Text('Billing managed by account owner'),
                subtitle: const Text(
                  'To upgrade your plan or change the number of seats, contact your account owner.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
