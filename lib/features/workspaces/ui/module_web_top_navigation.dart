import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../../auth/auth_state.dart';
import '../../settings/state/settings_controller.dart';
import 'dart:async';

import '../../notifications/state/push_notification_service.dart';
import '../state/header_notifications_provider.dart';

class ModuleWorkflowItem {
  final String label;
  final String route;

  const ModuleWorkflowItem({
    required this.label,
    required this.route,
  });
}

class ModuleQuickAction {
  final String label;
  final void Function(BuildContext context) onTap;
  final bool isPrimary;
  final bool enabled;

  const ModuleQuickAction({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.enabled = true,
  });
}

class ModuleWebTopNavigationConfig {
  final String currentRoute;
  final String moduleChipLabel;
  final String moduleTitle;
  final String workflowLabel;
  final List<ModuleWorkflowItem> workflowItems;
  final List<ModuleQuickAction> quickActions;

  const ModuleWebTopNavigationConfig({
    required this.currentRoute,
    required this.moduleChipLabel,
    required this.moduleTitle,
    required this.workflowLabel,
    required this.workflowItems,
    required this.quickActions,
  });
}

class ModuleWebTopNavigation extends ConsumerWidget implements PreferredSizeWidget {
  final ModuleWebTopNavigationConfig config;

  const ModuleWebTopNavigation({
    super.key,
    required this.config,
  });

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final activeLogo = getActiveLogo(settings.companyProfile);

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 44,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 8,
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
                  ? Image.memory(
                      Uint8List.fromList(activeLogo.companyLogoBytes),
                      fit: BoxFit.contain,
                    )
                  : Image.asset(
                      activeLogo.fallbackAssetPath,
                      fit: BoxFit.contain,
                    ),
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
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              config.moduleChipLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D47A1),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _WorkflowMenu(
            currentLabel: config.workflowLabel,
            items: config.workflowItems,
          ),
        ],
      ),
      actions: [
        for (final action in config.quickActions) ...[
          _HeaderQuickActionButton(action: action),
          const SizedBox(width: 6),
        ],
        const _NotificationBellButton(),
        _ProfileMenuButton(auth: auth),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _WorkflowMenu extends StatelessWidget {
  final String currentLabel;
  final List<ModuleWorkflowItem> items;

  const _WorkflowMenu({
    required this.currentLabel,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedLabel = currentLabel.trim().isNotEmpty
        ? currentLabel.trim()
        : (items.isNotEmpty ? items.first.label : 'Workflow');

    return PopupMenuButton<String>(
      tooltip: 'Module workflow menu',
      onSelected: (route) => context.go(route),
      itemBuilder: (_) => [
        for (final item in items)
          PopupMenuItem<String>(
            value: item.route,
            child: Text(item.label),
          ),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB8C6D8)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              normalizedLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF102A43),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Color(0xFF102A43),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderQuickActionButton extends StatelessWidget {
  final ModuleQuickAction action;

  const _HeaderQuickActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: action.enabled ? () => action.onTap(context) : null,
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        action.label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _NotificationBellButton extends ConsumerWidget {
  const _NotificationBellButton();

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
                PopupMenuItem<HeaderNotificationItem>(
                  enabled: false,
                  child: Text('No new notifications'),
                ),
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
  final AuthState auth;

  const _ProfileMenuButton({required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (context.mounted) {
            context.go('/login');
          }
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
