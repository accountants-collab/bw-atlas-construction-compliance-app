import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_state.dart';
import '../../features/modules/ui/module_projects_screen.dart';
import '../../features/settings/state/settings_controller.dart';

class WorkspaceSwitchCardsBar extends ConsumerWidget
    implements PreferredSizeWidget {
  final String? currentWorkspaceKey;

  const WorkspaceSwitchCardsBar({
    super.key,
    this.currentWorkspaceKey,
  });

  @override
  Size get preferredSize => const Size.fromHeight(46);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedWorkspaceKey = currentWorkspaceKey ??
        ref.watch(settingsControllerProvider).activeWorkspaceKey;
    final auth = ref.watch(authControllerProvider);
    final role = auth.userRole ?? UserRole.worker;
    final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
    final canAccessFullMenu =
        role == UserRole.manager || role == UserRole.owner || isSuperAdmin;

    return SizedBox(
      height: preferredSize.height,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 360),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _WorkspaceMenuCard(
                  title: 'Fire Door',
                  workspaceKey: 'fire-door',
                  isCurrent: resolvedWorkspaceKey == 'fire-door',
                  canAccessFullMenu: canAccessFullMenu,
                ),
                const SizedBox(width: 10),
                _WorkspaceMenuCard(
                  title: 'Fire Stopping',
                  workspaceKey: 'fire-stopping',
                  isCurrent: resolvedWorkspaceKey == 'fire-stopping',
                  canAccessFullMenu: canAccessFullMenu,
                ),
                const SizedBox(width: 10),
                _WorkspaceMenuCard(
                  title: 'Snagging Inspection',
                  workspaceKey: 'snagging',
                  isCurrent: resolvedWorkspaceKey == 'snagging',
                  canAccessFullMenu: canAccessFullMenu,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceMenuCard extends StatelessWidget {
  final String title;
  final String workspaceKey;
  final bool isCurrent;
  final bool canAccessFullMenu;

  const _WorkspaceMenuCard({
    required this.title,
    required this.workspaceKey,
    required this.isCurrent,
    required this.canAccessFullMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final auth = ref.watch(authControllerProvider);
        final role = auth.userRole ?? UserRole.worker;
        final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
        final canCreateProject =
            role == UserRole.manager || role == UserRole.owner || isSuperAdmin;

        String resolveRoute(String route) {
          final settings = ref.read(settingsControllerProvider);
          if (!hasCompletedCompanySetup(settings, workspaceKey: workspaceKey)) {
            return Uri(
              path: '/onboarding/company',
              queryParameters: {
                'mode': 'company',
                'returnTo': route,
              },
            ).toString();
          }

          final workspace = parseWorkspaceKey(workspaceKey);
          if (!canCreateProject || workspace == null) return route;
          return route;
        }

        return PopupMenuButton<String>(
          onSelected: (route) => context.go(resolveRoute(route)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          itemBuilder: (_) => _menuItemsFor(workspaceKey, canAccessFullMenu),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(
                  minWidth: 126, maxWidth: 200, minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isCurrent ? const Color(0xFF0D47A1) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCurrent
                      ? const Color(0xFF0B3D91)
                      : const Color(0xFFCFD8E3),
                  width: isCurrent ? 1.6 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: isCurrent ? 10 : 6,
                    offset: const Offset(0, 2),
                    color: isCurrent
                        ? const Color(0xFF0D47A1).withValues(alpha: 0.28)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color:
                            isCurrent ? Colors.white : const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: isCurrent ? Colors.white : const Color(0xFF1F2937),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<PopupMenuEntry<String>> _menuItemsFor(
      String key, bool canAccessFullMenu) {
    final base = '/workspace/$key';

    if (key == 'snagging') {
      return <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('Choose destination',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        PopupMenuItem<String>(
          value: '$base/inspection/projects',
          child: const _MenuLabel(
              icon: Icons.fact_check_outlined, text: 'Snagging Inspection'),
        ),
        PopupMenuItem<String>(
          value: '$base/verification/projects',
          child: const _MenuLabel(
              icon: Icons.verified_outlined, text: 'Snagging Verification'),
        ),
      ];
    }

    if (key == 'fire-stopping') {
      return <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('Choose destination',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        PopupMenuItem<String>(
          value: '$base/inspection/projects',
          child: const _MenuLabel(
              icon: Icons.fact_check_outlined,
              text: 'Fire Stopping Inspection'),
        ),
        PopupMenuItem<String>(
          value: '$base/modules/remedials/projects',
          child: const _MenuLabel(
              icon: Icons.verified_user_outlined,
              text: 'Manager Review & Approval'),
        ),
      ];
    }

    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        enabled: false,
        child: Text('Choose destination',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    ];

    if (canAccessFullMenu) {
      items.add(
        PopupMenuItem<String>(
          value: '$base/inspection/projects',
          child: const _MenuLabel(
              icon: Icons.fact_check_outlined, text: 'Inspection Projects'),
        ),
      );
    }

    items.addAll([
      PopupMenuItem<String>(
        value: '$base/modules/remedials/projects',
        child: const _MenuLabel(
            icon: Icons.build_outlined, text: 'Remedial Works'),
      ),
      PopupMenuItem<String>(
        value: '$base/modules/installation/projects',
        child: const _MenuLabel(
            icon: Icons.construction_outlined, text: 'Installation & Handover'),
      ),
    ]);

    if (canAccessFullMenu) {
      items.insert(
        items.length - 1,
        PopupMenuItem<String>(
          value: '$base/modules/preinstall/projects',
          child: const _MenuLabel(
              icon: Icons.rule_folder_outlined, text: 'Pre-Installation'),
        ),
      );
    }

    return items;
  }
}

class _MenuLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MenuLabel({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
