import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_service.dart';
import '../../../auth/auth_state.dart';
import '../../../core/env/app_environment.dart';
import '../domain/app_settings.dart' as app_settings;
import '../../notifications/data/firebase_email_queue_service.dart';
import '../state/settings_controller.dart';

class TeamUsersScreen extends ConsumerStatefulWidget {
  const TeamUsersScreen({super.key});

  @override
  ConsumerState<TeamUsersScreen> createState() => _TeamUsersScreenState();
}

class _TeamUsersScreenState extends ConsumerState<TeamUsersScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  InviteRole _role = InviteRole.worker;
  String? _latestInviteLink;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Color _statusColor(InviteStatus s) {
    switch (s) {
      case InviteStatus.pending:
        return const Color(0xFFF57C00);
      case InviteStatus.accepted:
        return const Color(0xFF2E7D32);
      case InviteStatus.expired:
        return Colors.black45;
      case InviteStatus.revoked:
        return const Color(0xFFC62828);
    }
  }

  IconData _statusIcon(InviteStatus s) {
    switch (s) {
      case InviteStatus.pending:
        return Icons.schedule_outlined;
      case InviteStatus.accepted:
        return Icons.check_circle_outline;
      case InviteStatus.expired:
        return Icons.history_toggle_off_outlined;
      case InviteStatus.revoked:
        return Icons.block_outlined;
    }
  }

  String _inviteRoleLabel(InviteRole role) {
    switch (role) {
      case InviteRole.admin:
        return 'Admin';
      case InviteRole.manager:
        return 'Manager';
      case InviteRole.worker:
        return 'Worker';
    }
  }

  String _userRoleLabel(UserRole role) {
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

  String _userStatusLabel(UserAccountStatus status) {
    switch (status) {
      case UserAccountStatus.active:
        return 'Active';
      case UserAccountStatus.inactive:
        return 'Inactive';
      case UserAccountStatus.suspended:
        return 'Suspended';
    }
  }

  Color _userStatusColor(UserAccountStatus status) {
    switch (status) {
      case UserAccountStatus.active:
        return const Color(0xFF2E7D32);
      case UserAccountStatus.inactive:
        return Colors.black45;
      case UserAccountStatus.suspended:
        return const Color(0xFFC62828);
    }
  }

  String _statusLabel(InviteStatus status) {
    switch (status) {
      case InviteStatus.pending:
        return 'Pending';
      case InviteStatus.accepted:
        return 'Accepted';
      case InviteStatus.expired:
        return 'Expired';
      case InviteStatus.revoked:
        return 'Revoked';
    }
  }

  Future<void> _copyToClipboard(
      BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _sendInviteEmail({
    required BuildContext context,
    required String invitedEmail,
    required String invitedName,
    required String inviteLink,
  }) async {
    try {
      await FirebaseEmailQueueService().queueInviteEmail(
        toEmail: invitedEmail,
        invitedName: invitedName,
        inviteLink: inviteLink,
        companyName: authCompanyName(context),
      );
      if (!context.mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite email queued for sending.')),
      );
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Automatic email sending is not configured in Firebase yet.')),
      );
      return false;
    }
  }

  String authCompanyName(BuildContext context) {
    final settings = ref.read(settingsControllerProvider);
    final companyName = settings.companyProfile.companyName.trim();
    return companyName.isEmpty ? 'BW Fire Door Inspection' : companyName;
  }

  String _inviteLinkForToken(String token) {
    final webBase = '${Uri.base.origin}/#';
    final base =
        kIsWeb && Uri.base.host != 'localhost' && Uri.base.host != '127.0.0.1'
            ? webBase
            : AppEnvironmentRuntime.current.inviteBaseUrl;
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final encodedToken = Uri.encodeComponent(token);
    return '$normalizedBase/invite/$encodedToken';
  }

  Future<void> _showSeatUpgradeDialog(BuildContext context) async {
    final settings = ref.read(settingsControllerProvider);
    final currentPlan = settings.subscriptionPlan;
    final currentLimit = app_settings.planUserLimit(currentPlan);
    final availablePlans = app_settings.SubscriptionPlan.values
        .where((p) => app_settings.planUserLimit(p) > currentLimit)
        .toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upgrade Subscription'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a plan that fits your team size. More seats = more team members can access projects.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              Text(
                'Current: ${app_settings.planLabel(currentPlan)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 12),
              if (availablePlans.isEmpty)
                const Text(
                  'You already have the maximum plan available.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Available upgrades:',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      children: [
                        ...availablePlans.map(
                          (plan) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    app_settings.planLabel(plan),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                FilledButton.tonal(
                                  onPressed: () {
                                    ref
                                        .read(
                                            settingsControllerProvider.notifier)
                                        .setSubscriptionPlan(plan);
                                    Navigator.pop(ctx);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Subscription upgraded to ${app_settings.planLabel(plan)}.')),
                                      );
                                    }
                                  },
                                  child: const Text('Upgrade'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);
    final usersAsync = ref.watch(companyUsersProvider);
    final invitesAsync = ref.watch(companyInvitesProvider);
    final seatSummaryAsync = ref.watch(companySeatSummaryProvider);

    final users = usersAsync.valueOrNull ?? const <AppUser>[];
    final seatSummary = seatSummaryAsync.valueOrNull;
    final seatLimit = seatSummary?.seatLimit ?? 0;
    final activeSeats = seatSummary?.activeUsers ?? 0;
    final availableSeats = seatSummary?.availableSeats ?? 0;
    final seatLimitReached = seatSummary != null && availableSeats <= 0;
    final canManage = auth.actualRole == UserRole.manager ||
        auth.actualRole == UserRole.owner ||
        auth.actualRole == UserRole.superAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team / Users'),
        bottom: const WorkspaceSwitchCardsBar(),
      ),
      drawer: const AppDrawer(currentRoute: '/company/team-users'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Seat usage banner
          Card(
            color: const Color(0xFFE3F0FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFBDD4F0)),
            ),
            child: ListTile(
              leading: const Icon(Icons.event_seat_outlined,
                  color: Color(0xFF1565C0)),
              title: Text(
                'Seats: $activeSeats / $seatLimit in use',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Color(0xFF1565C0)),
              ),
              subtitle: Text(
                seatLimitReached
                    ? 'No available seats. Deactivate a team member or upgrade your subscription plan.'
                    : '$availableSeats seat${availableSeats == 1 ? '' : 's'} available.',
                style: TextStyle(
                  color: seatLimitReached ? Colors.red : Colors.black54,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (canManage)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => _showSeatUpgradeDialog(context),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Upgrade Seats'),
              ),
            ),
          const SizedBox(height: 16),
          if (seatSummary != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Badge(
                    label: 'Seats: ${seatSummary.seatLimit} total',
                    bgColor: const Color(0xFFE3F0FF),
                    textColor: const Color(0xFF1565C0),
                  ),
                  _Badge(
                    label: 'Active users: ${seatSummary.activeUsers}',
                    bgColor: const Color(0xFFE8F5E9),
                    textColor: const Color(0xFF2E7D32),
                  ),
                  _Badge(
                    label: 'Available seats: ${seatSummary.availableSeats}',
                    bgColor: seatSummary.availableSeats > 0
                        ? const Color(0xFFF1F3F4)
                        : const Color(0xFFFFEBEE),
                    textColor: seatSummary.availableSeats > 0
                        ? Colors.black87
                        : const Color(0xFFC62828),
                  ),
                ],
              ),
            ),

          if (canManage)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F9FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDDE5F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invite Team Member',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<InviteRole>(
                    initialValue: _role,
                    items: InviteRole.values
                        .map((r) => DropdownMenuItem(
                            value: r, child: Text(_inviteRoleLabel(r))))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _role = v ?? InviteRole.worker),
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Deactivate a team member to free a seat instantly. Upgrade your subscription plan for more capacity.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: seatLimitReached || auth.isLoading
                          ? null
                          : () async {
                              final invitedName = _name.text.trim();
                              final invitedEmail = _email.text.trim();
                              if (invitedName.isEmpty || invitedEmail.isEmpty) {
                                return;
                              }
                              try {
                                final link = await ctrl.createInviteLink(
                                  invitedName: invitedName,
                                  invitedEmail: invitedEmail,
                                  role: _role,
                                );
                                if (!context.mounted) return;
                                setState(() => _latestInviteLink = link);
                                _name.clear();
                                _email.clear();
                                await _copyToClipboard(context, link,
                                    'Invite link copied to clipboard.');
                                if (!context.mounted) return;
                                await _sendInviteEmail(
                                  context: context,
                                  invitedEmail: invitedEmail,
                                  invitedName: invitedName,
                                  inviteLink: link,
                                );
                              } on AuthFailure catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.message)));
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Failed to create invite link.')),
                                );
                              }
                            },
                      icon: const Icon(Icons.link_outlined),
                      label: const Text('Create Invite Link'),
                    ),
                  ),
                  if (_latestInviteLink != null) ...[
                    const SizedBox(height: 10),
                    SelectableText(_latestInviteLink!),
                  ],
                ],
              ),
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('Only manager/admin can manage team invites.'),
              ),
            ),

          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Team Members',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F0FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${users.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1565C0),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          usersAsync.when(
            data: (list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No active users yet.',
                      style: TextStyle(color: Colors.black45)),
                );
              }
              return Column(
                children: [
                  for (final u in list) ...[
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE3F0FF),
                          foregroundColor: const Color(0xFF1565C0),
                          child: Text(
                            u.name.trim().isEmpty
                                ? '?'
                                : u.name
                                    .trim()
                                    .split(' ')
                                    .map((s) => s.isNotEmpty ? s[0] : '')
                                    .take(2)
                                    .join()
                                    .toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        title: Text(u.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(u.email),
                        trailing: _Badge(
                          label: _userRoleLabel(u.role),
                          bgColor: const Color(0xFFE3F0FF),
                          textColor: const Color(0xFF1565C0),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 12),
                        _Badge(
                          label: _userStatusLabel(u.status),
                          bgColor: _userStatusColor(u.status)
                              .withValues(alpha: 0.12),
                          textColor: _userStatusColor(u.status),
                        ),
                        const Spacer(),
                        if (canManage && !u.isInternalAdmin)
                          TextButton.icon(
                            onPressed: () async {
                              final nextStatus =
                                  u.status == UserAccountStatus.active
                                      ? UserAccountStatus.inactive
                                      : UserAccountStatus.active;
                              try {
                                await ctrl.setUserStatus(
                                    userId: u.id, status: nextStatus);
                                if (!context.mounted) return;
                                final label =
                                    nextStatus == UserAccountStatus.active
                                        ? 'activated'
                                        : 'deactivated';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('User ${u.name} $label.')),
                                );
                              } on AuthFailure catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.message)));
                              }
                            },
                            icon: Icon(
                              u.status == UserAccountStatus.active
                                  ? Icons.person_off_outlined
                                  : Icons.person_add_alt_1_outlined,
                            ),
                            label: Text(u.status == UserAccountStatus.active
                                ? 'Deactivate'
                                : 'Activate'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              );
            },
            loading: () => const Center(
                child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            )),
            error: (_, __) => const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Failed to load users.',
                  style: TextStyle(color: Colors.red)),
            ),
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Team Groups & Access',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFF5F9FF),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assign team members to workspace groups to control project access. Members only see projects assigned to their group.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  if (canManage)
                    OutlinedButton.icon(
                      onPressed: () => context.go('/company/workspace-groups'),
                      icon: const Icon(Icons.groups_2_outlined),
                      label: const Text('Manage Groups & Assignments'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Pending Invites',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          invitesAsync.when(
            data: (list) {
              if (list.isEmpty) {
                return const Text('No invites yet.',
                    style: TextStyle(color: Colors.black45));
              }
              final sorted = List.from(list);
              try {
                if (sorted.length > 1) {
                  sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                }
              } catch (e) {
                debugPrint('Sort error (team users invites): $e');
              }
              return Column(
                children: [
                  for (final invite in sorted) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(invite.invitedName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800)),
                                      Text(invite.invitedEmail,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54)),
                                    ],
                                  ),
                                ),
                                _Badge(
                                  label: _statusLabel(invite.status),
                                  bgColor: _statusColor(invite.status)
                                      .withValues(alpha: 0.12),
                                  textColor: _statusColor(invite.status),
                                  icon: _statusIcon(invite.status),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Badge(
                                  label: _inviteRoleLabel(invite.invitedRole),
                                  bgColor: const Color(0xFFE3F0FF),
                                  textColor: const Color(0xFF1565C0),
                                ),
                                _Badge(
                                  label:
                                      'Expires ${invite.expiresAt.toLocal().toString().split('.').first}',
                                  bgColor: const Color(0xFFF1F3F4),
                                  textColor: Colors.black87,
                                ),
                              ],
                            ),
                            if (invite.status == InviteStatus.pending) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () async {
                                      final link =
                                          _inviteLinkForToken(invite.token);
                                      await _sendInviteEmail(
                                        context: context,
                                        invitedEmail: invite.invitedEmail,
                                        invitedName: invite.invitedName,
                                        inviteLink: link,
                                      );
                                    },
                                    icon: const Icon(Icons.email_outlined),
                                    label: const Text('Send Email'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () async {
                                      final link =
                                          _inviteLinkForToken(invite.token);
                                      await _copyToClipboard(
                                          context, link, 'Invite link copied.');
                                    },
                                    icon: const Icon(Icons.copy_outlined),
                                    label: const Text('Copy Link'),
                                  ),
                                  const SizedBox(width: 8),
                                  if (canManage)
                                    TextButton.icon(
                                      onPressed: () async {
                                        try {
                                          await ctrl
                                              .revokeInvite(invite.inviteId);
                                        } on AuthFailure catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(e.message)));
                                        }
                                      },
                                      icon: const Icon(Icons.block_outlined,
                                          color: Colors.red),
                                      label: const Text('Revoke',
                                          style: TextStyle(color: Colors.red)),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              );
            },
            loading: () => const Center(
                child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            )),
            error: (_, __) => const Text('Failed to load invites.',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;
  final IconData? icon;

  const _Badge({
    required this.label,
    required this.bgColor,
    required this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: textColor),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
