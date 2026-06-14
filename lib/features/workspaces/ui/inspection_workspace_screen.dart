import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/mobile_bottom_navigation_bar.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../settings/state/settings_controller.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/state/survey_controller.dart';

class InspectionWorkspaceScreen extends ConsumerWidget {
  final InspectionWorkspace workspace;

  const InspectionWorkspaceScreen({
    super.key,
    required this.workspace,
  });

  String get workspaceSlug {
    switch (workspace) {
      case InspectionWorkspace.fireDoor:
        return 'fire-door';
      case InspectionWorkspace.fireStopping:
        return 'fire-stopping';
      case InspectionWorkspace.snagging:
        return 'snagging';
    }
  }

  String get inspectionTitle {
    switch (workspace) {
      case InspectionWorkspace.fireDoor:
        return 'Fire Door Inspection';
      case InspectionWorkspace.fireStopping:
        return 'Fire Stopping Inspection';
      case InspectionWorkspace.snagging:
        return 'Snagging Inspection';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    if (settings.activeWorkspaceKey != workspaceSlug) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(settingsControllerProvider.notifier)
            .setActiveWorkspace(workspaceSlug);
      });
    }
    final surveys =
        ref.watch(surveyControllerFamilyProvider(workspace)).surveys;

    final role = auth.userRole ?? UserRole.worker;
    final showMobileBottomNav = shouldShowMobileBottomNavigation(context);
    final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
    final isWorker = role == UserRole.worker && !isSuperAdmin;
    final showPreinstall = role == UserRole.manager || isSuperAdmin;
    final isFireStopping = workspace == InspectionWorkspace.fireStopping;
    final isSnagging = workspace == InspectionWorkspace.snagging;

    String routeWithCompanyGate(String route) {
      if (hasCompletedCompanySetup(settings, workspaceKey: workspaceSlug) ||
          isWorker) {
        return route;
      }
      return Uri(
        path: '/onboarding/company',
        queryParameters: {
          'mode': 'company',
          'returnTo': route,
        },
      ).toString();
    }

    final remedialAwaiting = surveys
        .expand((s) => s.doors)
        .where((d) =>
            !d.replacementRequired &&
            d.remedialStatus == RemedialStatus.forApproval)
        .length;

    final installationAwaiting = surveys
        .expand((s) => s.preInstallItems)
        .where((i) => i.status == InstallationStatus.forApproval)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(inspectionTitle),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: workspaceSlug),
      ),
      drawer: AppDrawer(currentRoute: '/workspace/$workspaceSlug'),
      bottomNavigationBar:
          showMobileBottomNav ? const MobileBottomNavigationBar() : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isFireStopping) ...[
            if (!isWorker) ...[
              _tile(
                context: context,
                title: 'Fire Stopping Inspection',
                subtitle:
                    'Worker inspection workflow, photo upload, and submission.',
                icon: Icons.fact_check_outlined,
                onTap: () => context.go(routeWithCompanyGate(
                    '/workspace/$workspaceSlug/inspection/projects')),
              ),
              const SizedBox(height: 12),
            ],
            _tile(
              context: context,
              title: 'Manager Review & Approval',
              subtitle: 'Review submitted work, photos, and approve or reject.',
              icon: Icons.verified_user_outlined,
              badgeCount: remedialAwaiting,
              onTap: () => context.go(routeWithCompanyGate(
                  '/workspace/$workspaceSlug/modules/remedials/projects')),
            ),
          ] else if (isSnagging) ...[
            if (!isWorker) ...[
              _tile(
                context: context,
                title: 'Snagging Inspection',
                subtitle: 'Open and manage snagging inspection projects',
                icon: Icons.fact_check_outlined,
                onTap: () => context.go(routeWithCompanyGate(
                    '/workspace/$workspaceSlug/inspection/projects')),
              ),
              const SizedBox(height: 12),
              _tile(
                context: context,
                title: 'Snagging Verification',
                subtitle:
                    'Review completed snagging work and approve or reject',
                icon: Icons.verified_outlined,
                onTap: () => context.go(routeWithCompanyGate(
                    '/workspace/$workspaceSlug/verification/projects')),
              ),
            ] else ...[
              _tile(
                context: context,
                title: 'My Assignments',
                subtitle: 'Open remedial tasks assigned to you.',
                icon: Icons.assignment_outlined,
                badgeCount: remedialAwaiting,
                onTap: () => context
                    .go('/workspace/$workspaceSlug/modules/remedials/projects'),
              ),
            ],
          ] else ...[
            if (!isWorker) ...[
              _tile(
                context: context,
                title: inspectionTitle,
                subtitle:
                    'Open projects and continue with the inspection workflow.',
                icon: Icons.fact_check_outlined,
                onTap: () => context.go(routeWithCompanyGate(
                    '/workspace/$workspaceSlug/inspection/projects')),
              ),
              const SizedBox(height: 12),
            ],
            _tile(
              context: context,
              title: 'Remedial Works',
              subtitle: 'Worker execution and manager approval review.',
              icon: Icons.build_outlined,
              badgeCount: remedialAwaiting,
              onTap: () => context.go(routeWithCompanyGate(
                  '/workspace/$workspaceSlug/modules/remedials/projects')),
            ),
            if (showPreinstall) ...[
              const SizedBox(height: 12),
              _tile(
                context: context,
                title: 'Pre-Installation Survey',
                subtitle: 'Manager source module for opening specifications.',
                icon: Icons.rule_folder_outlined,
                onTap: () => context.go(routeWithCompanyGate(
                    '/workspace/$workspaceSlug/modules/preinstall/projects')),
              ),
            ],
            const SizedBox(height: 12),
            _tile(
              context: context,
              title: 'Installation & Handover',
              subtitle: 'Worker completion and manager approval review.',
              icon: Icons.construction_outlined,
              badgeCount: installationAwaiting,
              onTap: () => context.go(routeWithCompanyGate(
                  '/workspace/$workspaceSlug/modules/installation/projects')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1565C0)),
        title: Row(
          children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            if (badgeCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.35)),
                ),
                child: Text(
                  '$badgeCount awaiting approval',
                  style: const TextStyle(
                    color: Color(0xFF1565C0),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.black87)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
