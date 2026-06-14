import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_state.dart';
import '../features/settings/state/settings_controller.dart';

class AppDrawer extends ConsumerWidget {
  final String currentRoute;

  const AppDrawer({
    super.key,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const primaryBlue = Color(0xFF1565C0);
    const lightBlue = Color(0xFFE3F0FF);
    const textMuted = Color(0xFF4A6080);
    const textMain = Color(0xFF1A2A3A);

    final auth = ref.watch(authControllerProvider);
    final role = auth.userRole ?? UserRole.worker;
    final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
    final isManager = role == UserRole.manager || isSuperAdmin;

    final settings = ref.watch(settingsControllerProvider);
    final activeWorkspaceKey = settings.activeWorkspaceKey;

    final userEmail = auth.email;
    final userDisplayName = auth.currentUser?.name.trim().isNotEmpty == true
        ? auth.currentUser!.name.trim()
        : userEmail;
    final avatarLetter = userDisplayName.isNotEmpty
        ? userDisplayName[0].toUpperCase()
        : '?';
    final String roleLabel;
    if (isSuperAdmin) {
      roleLabel = 'Admin';
    } else if (auth.actualRole == UserRole.owner) {
      roleLabel = 'Owner';
    } else if (auth.actualRole == UserRole.admin) {
      roleLabel = 'Admin';
    } else if (role == UserRole.manager) {
      roleLabel = 'Manager';
    } else {
      roleLabel = 'Worker';
    }

    bool isRouteActive(String route) {
      return currentRoute == route || currentRoute.startsWith('$route/') || currentRoute.startsWith('$route?');
    }

    Widget item({
      required IconData icon,
      required String title,
      required String route,
      bool selected = false,
    }) {
      final isSelected = selected || isRouteActive(route);
      return ListTile(
        leading: Icon(
          icon,
          color: isSelected ? primaryBlue : textMuted,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? primaryBlue : textMain,
          ),
        ),
        dense: true,
        tileColor: isSelected ? lightBlue : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        selected: isSelected,
        onTap: () {
          Navigator.of(context).pop();
          if (!isSelected) context.go(route);
        },
      );
    }

    Widget section(String title) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF607D9B),
            fontSize: 11,
            letterSpacing: 0.9,
          ),
        ),
      );
    }

    return Drawer(
      backgroundColor: const Color(0xFFF5F9FF),
      child: SafeArea(
        child: Column(
          children: [
            // ── User Profile Header ──────────────────────────────────────
            Container(
              color: primaryBlue,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white24,
                    child: Text(
                      avatarLetter,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userEmail,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            roleLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable Menu Items ────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  section('MAIN'),
                  item(
                    icon: Icons.home_outlined,
                    title: 'Home',
                    route: '/dashboard',
                  ),
                  if (!isManager) ...[
                    item(
                      icon: Icons.assignment_outlined,
                      title: 'My Assignments',
                      route: '/workspace/$activeWorkspaceKey/modules/remedials/projects',
                    ),
                    item(
                      icon: Icons.verified_user_outlined,
                      title: 'My Disclaimer Forms',
                      route: '/company/disclaimer-records',
                    ),
                  ],
                  if (isManager) ...[
                    section('COMPANY'),
                    item(
                      icon: Icons.business_outlined,
                      title: 'Company Details',
                      route: '/company/settings',
                    ),
                    item(
                      icon: Icons.verified_user_outlined,
                      title: 'Disclaimer Forms',
                      route: '/company/disclaimer-records',
                    ),
                    item(
                      icon: Icons.group_outlined,
                      title: 'Team / Users',
                      route: '/company/team-users',
                    ),
                    item(
                      icon: Icons.groups_2_outlined,
                      title: 'Groups',
                      route: '/company/workspace-groups',
                    ),
                    item(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Subscription / Billing',
                      route: '/company/subscription',
                    ),
                  ],
                  if (isSuperAdmin) ...[
                    section('PLATFORM'),
                    item(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Super Admin',
                      route: '/platform/admin',
                    ),
                  ],
                  section('APP'),
                  item(
                    icon: Icons.tune_outlined,
                    title: 'App Settings',
                    route: '/app/preferences',
                  ),
                  item(
                    icon: Icons.support_agent_outlined,
                    title: 'Support & Feedback',
                    route: '/info/contact-support',
                  ),
                  item(
                    icon: Icons.info_outline,
                    title: 'About / How It Works',
                    route: '/info/about-app',
                  ),
                ],
              ),
            ),

            // ── Logout (pinned bottom) ───────────────────────────────────
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFC62828), size: 20),
              title: const Text(
                'Logout',
                style: TextStyle(
                  color: Color(0xFFC62828),
                  fontWeight: FontWeight.w700,
                ),
              ),
              dense: true,
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
