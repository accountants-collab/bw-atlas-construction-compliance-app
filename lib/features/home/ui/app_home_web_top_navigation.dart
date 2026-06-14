import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../../auth/auth_state.dart';
import '../../settings/state/settings_controller.dart';
import 'dart:async';

import '../../notifications/state/push_notification_service.dart';
import '../../workspaces/state/header_notifications_provider.dart';

class AppHomeWebTopNavigation extends ConsumerWidget implements PreferredSizeWidget {
  const AppHomeWebTopNavigation({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final activeLogo = getActiveLogo(settings.companyProfile);

    final user = auth.currentUser;
    final fullName = (user?.name ?? '').trim().isEmpty ? auth.email : user!.name.trim();
    final role = _roleLabel(auth.actualRole ?? auth.userRole ?? UserRole.worker);

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 56,
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 190,
      leading: Row(
        children: [
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go('/dashboard'),
            child: SizedBox(
              width: 112,
              height: 30,
              child: activeLogo.hasCompanyLogo
                  ? Image.memory(Uint8List.fromList(activeLogo.companyLogoBytes), fit: BoxFit.contain)
                  : Image.asset(activeLogo.fallbackAssetPath, fit: BoxFit.contain),
            ),
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Open navigation menu',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        ],
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          Text(role, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
      actions: const [
        _GlobalBellButton(),
        _ProfileMenuButton(),
        SizedBox(width: 8),
      ],
    );
  }
}

class _GlobalBellButton extends StatelessWidget {
  const _GlobalBellButton();

  @override
  Widget build(BuildContext context) {
    return const _GlobalBellMenu();
  }
}

class _GlobalBellMenu extends ConsumerWidget {
  const _GlobalBellMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(headerNotificationSummaryProvider);
    final actionItems = summary.items.where((n) => n.requiresAction).toList();
    final recentItems = summary.items.where((n) => !n.requiresAction).toList();
    final auth = ref.watch(authControllerProvider);
    final role = auth.actualRole ?? auth.userRole ?? UserRole.worker;

    return Stack(
      children: [
        PopupMenuButton<HeaderNotificationItem>(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_rounded),
          onSelected: (item) {
            final route = item.resolveRoute(isManagerLike: role != UserRole.worker);
            if (route.trim().isEmpty) return;
            final companyId = auth.companyId;
            if (item.notificationId != null && item.notificationId!.isNotEmpty && companyId != null && companyId.isNotEmpty) {
              unawaited(
                ref.read(workflowNotificationRepositoryProvider).markRead(
                      companyId: companyId,
                      notificationId: item.notificationId!,
                    ),
              );
            }
            debugPrint(
              'notification_tap route=$route module=${item.moduleKey ?? ''} workspace=${item.workspaceKey ?? ''} survey=${item.surveyId ?? ''} door=${item.doorId ?? ''} action=navigate_only markRead=${item.notificationId?.isNotEmpty == true}',
            );
            context.go(route);
          },
          itemBuilder: (_) {
            if (summary.items.isEmpty) {
              return const [
                PopupMenuItem<HeaderNotificationItem>(enabled: false, child: Text('No new notifications')),
              ];
            }

            final entries = <PopupMenuEntry<HeaderNotificationItem>>[];
            entries.add(const PopupMenuItem<HeaderNotificationItem>(enabled: false, child: Text('Needs Action')));
            if (actionItems.isEmpty) {
              entries
                  .add(const PopupMenuItem<HeaderNotificationItem>(enabled: false, child: Text('No action-required items')));
            } else {
              for (final item in actionItems.take(8)) {
                entries.add(
                  PopupMenuItem<HeaderNotificationItem>(
                    value: item,
                    child: _NotificationMenuRow(item: item),
                  ),
                );
              }
            }

            if (recentItems.isNotEmpty) {
              entries.add(const PopupMenuDivider());
              entries.add(const PopupMenuItem<HeaderNotificationItem>(enabled: false, child: Text('Recent Updates')));
              for (final item in recentItems.take(4)) {
                entries.add(
                  PopupMenuItem<HeaderNotificationItem>(
                    enabled: false,
                    child: _NotificationMenuRow(item: item),
                  ),
                );
              }
            }
            return entries;
          },
        ),
        if (summary.actionRequiredCount > 0)
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Color(0xFFC62828), shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

class _NotificationMenuRow extends StatelessWidget {
  final HeaderNotificationItem item;

  const _NotificationMenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 2),
          Text(item.subtitle, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }
}

class _ProfileMenuButton extends ConsumerWidget {
  const _ProfileMenuButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.currentUser;
    final fullName = (user?.name ?? '').trim().isEmpty ? auth.email : user!.name.trim();
    final role = _roleLabel(auth.actualRole ?? auth.userRole ?? UserRole.worker);
    final initials = _initialsFor(fullName);

    return PopupMenuButton<String>(
      tooltip: 'Profile menu',
      onSelected: (value) async {
        if (value == 'profile') {
          context.go('/account/profile');
          return;
        }
        if (value == 'logout') {
          await ref.read(authControllerProvider.notifier).logout();
          if (context.mounted) context.go('/login');
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(role, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'profile', child: Text('My Profile')),
        const PopupMenuItem<String>(value: 'logout', child: Text('Log out')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFFE3F2FD),
          foregroundColor: const Color(0xFF0D47A1),
          child: Text(initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

String _initialsFor(String value) {
  final parts = value
      .split(RegExp(r'\s+'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
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
