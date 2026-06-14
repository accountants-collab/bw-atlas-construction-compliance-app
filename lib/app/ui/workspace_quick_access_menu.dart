import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_state.dart';
import '../../features/settings/state/settings_controller.dart';

class WorkspaceQuickAccessMenu extends ConsumerWidget {
  final String? currentWorkspaceKey;

  const WorkspaceQuickAccessMenu({
    super.key,
    this.currentWorkspaceKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String resolveRoute(String workspaceKey, String route) {
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

      final auth = ref.read(authControllerProvider);
      final role = auth.userRole ?? UserRole.worker;
      final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
      final canCreateProject =
          role == UserRole.manager || role == UserRole.owner || isSuperAdmin;
      if (!canCreateProject) return route;
      return route;
    }

    if (!_isWebLayout()) {
      return IconButton(
        tooltip: 'Quick workspace access',
        onPressed: () => _showMobileQuickAccess(context, ref, resolveRoute),
        icon: const Icon(Icons.add_circle_rounded, color: Color(0xFF4F46E5)),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Quick workspace access',
      icon: const Icon(Icons.grid_view_rounded),
      onSelected: (route) => context.go(route),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('Quick Access',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const PopupMenuItem<String>(
            value: '/dashboard',
            child: _MenuLabel(text: 'Workspace Hub', icon: Icons.home_outlined),
          ),
          const PopupMenuDivider(),
        ];

        void addWorkspaceSection({
          required String title,
          required String workspaceKey,
        }) {
          final prefix = '/workspace/$workspaceKey';

          if (workspaceKey == 'fire-stopping') {
            items.add(
              PopupMenuItem<String>(
                value: '$prefix/inspection/projects',
                child: const Padding(
                  padding: EdgeInsets.only(left: 22),
                  child: Text('Fire Stopping Inspection'),
                ),
              ),
            );
            items.add(
              PopupMenuItem<String>(
                value: '$prefix/modules/remedials/projects',
                child: const Padding(
                  padding: EdgeInsets.only(left: 22),
                  child: Text('Manager Review & Approval'),
                ),
              ),
            );
            items.add(const PopupMenuDivider());
            return;
          }

          if (workspaceKey == 'snagging') {
            items.add(
              PopupMenuItem<String>(
                value: '$prefix/inspection/projects',
                child: const Padding(
                  padding: EdgeInsets.only(left: 22),
                  child: Text('Snagging Inspection'),
                ),
              ),
            );
            items.add(
              PopupMenuItem<String>(
                value: '$prefix/verification/projects',
                child: const Padding(
                  padding: EdgeInsets.only(left: 22),
                  child: Text('Snagging Verification'),
                ),
              ),
            );
            items.add(const PopupMenuDivider());
            return;
          }

          items.add(
            PopupMenuItem<String>(
              value: '$prefix/inspection/projects',
              child: Padding(
                padding: EdgeInsets.only(left: 22),
                child: Text(workspaceKey == 'fire-door'
                    ? 'Inspection Projects'
                    : 'Snagging Inspection'),
              ),
            ),
          );
          items.add(
            PopupMenuItem<String>(
              value: '$prefix/modules/remedials/projects',
              child: const Padding(
                padding: EdgeInsets.only(left: 22),
                child: Text('Remedial Works'),
              ),
            ),
          );
          items.add(
            PopupMenuItem<String>(
              value: '$prefix/modules/preinstall/projects',
              child: const Padding(
                padding: EdgeInsets.only(left: 22),
                child: Text('Pre-Installation'),
              ),
            ),
          );
          items.add(
            PopupMenuItem<String>(
              value: '$prefix/modules/installation/projects',
              child: const Padding(
                padding: EdgeInsets.only(left: 22),
                child: Text('Installation & Handover'),
              ),
            ),
          );
          items.add(const PopupMenuDivider());
        }

        addWorkspaceSection(title: 'Fire Door', workspaceKey: 'fire-door');
        addWorkspaceSection(
            title: 'Fire Stopping', workspaceKey: 'fire-stopping');
        addWorkspaceSection(title: 'Snagging', workspaceKey: 'snagging');

        return items.map((entry) {
          if (entry is! PopupMenuItem<String>) return entry;
          final value = entry.value;
          if (value == null || !value.startsWith('/workspace/')) return entry;
          final workspaceKey =
              value.split('/').length > 2 ? value.split('/')[2] : '';
          return PopupMenuItem<String>(
            value: resolveRoute(workspaceKey, value),
            enabled: entry.enabled,
            child: entry.child,
          );
        }).toList();
      },
    );
  }

  bool _isWebLayout() {
    return kIsWeb;
  }

  void _showMobileQuickAccess(
    BuildContext context,
    WidgetRef ref,
    String Function(String workspaceKey, String route) resolveRoute,
  ) {
    final sections = _workspaceSections(currentWorkspaceKey);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF6F7FB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Color(0xFF2E46D1)),
                    const SizedBox(width: 8),
                    Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _MobileQuickActionCard(
                  title: 'Workspace Hub',
                  subtitle: 'Open all workspace entry points',
                  icon: Icons.home_outlined,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go('/dashboard');
                  },
                ),
                const SizedBox(height: 10),
                for (final section in sections) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
                    child: Row(
                      children: [
                        Icon(
                          section.isCurrent
                              ? Icons.check_circle_rounded
                              : Icons.workspaces_outline,
                          size: 18,
                          color: section.isCurrent
                              ? const Color(0xFF0A7F36)
                              : const Color(0xFF2E46D1),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          section.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (section.isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A7F36)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'current',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0A7F36),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final action in section.actions) ...[
                    _MobileQuickActionCard(
                      title: action.label,
                      subtitle: action.subtitle,
                      icon: action.icon,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.go(resolveRoute(section.key, action.route));
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            );
          },
        );
      },
    );
  }
}

List<_WorkspaceSection> _workspaceSections(String? currentWorkspaceKey) {
  _WorkspaceSection section(String key, String title) {
    final prefix = '/workspace/$key';
    if (key == 'snagging') {
      return _WorkspaceSection(
        key: key,
        title: title,
        isCurrent: currentWorkspaceKey == key,
        actions: [
          _WorkspaceAction(
            label: 'Snagging Inspection',
            subtitle: 'Continue snag inspection workflow.',
            route: '$prefix/inspection/projects',
            icon: Icons.fact_check_outlined,
          ),
          _WorkspaceAction(
            label: 'Snagging Verification',
            subtitle: 'Review and verify completed snags.',
            route: '$prefix/verification/projects',
            icon: Icons.verified_outlined,
          ),
        ],
      );
    }

    if (key == 'fire-stopping') {
      return _WorkspaceSection(
        key: key,
        title: title,
        isCurrent: currentWorkspaceKey == key,
        actions: [
          _WorkspaceAction(
            label: 'Fire Stopping Inspection',
            subtitle: 'Continue worker inspection workflow.',
            route: '$prefix/inspection/projects',
            icon: Icons.fact_check_outlined,
          ),
          _WorkspaceAction(
            label: 'Manager Review & Approval',
            subtitle: 'Review submitted work, photos, and decisions.',
            route: '$prefix/modules/remedials/projects',
            icon: Icons.verified_user_outlined,
          ),
        ],
      );
    }

    return _WorkspaceSection(
      key: key,
      title: title,
      isCurrent: currentWorkspaceKey == key,
      actions: [
        _WorkspaceAction(
          label: key == 'fire-door'
              ? 'Inspection Projects'
              : 'Snagging Inspection',
          subtitle: 'Continue inspection workflows',
          route: '$prefix/inspection/projects',
          icon: Icons.fact_check_outlined,
        ),
        _WorkspaceAction(
          label: 'Remedial Works',
          subtitle: 'Track defects and approvals',
          route: '$prefix/modules/remedials/projects',
          icon: Icons.build_outlined,
        ),
        _WorkspaceAction(
          label: 'Pre-Installation',
          subtitle: 'Prepare opening data and checks',
          route: '$prefix/modules/preinstall/projects',
          icon: Icons.rule_folder_outlined,
        ),
        _WorkspaceAction(
          label: 'Installation & Handover',
          subtitle: 'Complete and hand over',
          route: '$prefix/modules/installation/projects',
          icon: Icons.construction_outlined,
        ),
      ],
    );
  }

  return [
    section('fire-door', 'Fire Door'),
    section('fire-stopping', 'Fire Stopping'),
    section('snagging', 'Snagging'),
  ];
}

class _WorkspaceSection {
  final String key;
  final String title;
  final bool isCurrent;
  final List<_WorkspaceAction> actions;

  const _WorkspaceSection({
    required this.key,
    required this.title,
    required this.isCurrent,
    required this.actions,
  });
}

class _WorkspaceAction {
  final String label;
  final String subtitle;
  final String route;
  final IconData icon;

  const _WorkspaceAction({
    required this.label,
    required this.subtitle,
    required this.route,
    required this.icon,
  });
}

class _MobileQuickActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _MobileQuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E46D1).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF2E46D1)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  final String text;
  final IconData icon;

  const _MenuLabel({
    required this.text,
    required this.icon,
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
