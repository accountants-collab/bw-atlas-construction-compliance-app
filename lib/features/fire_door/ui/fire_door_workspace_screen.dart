import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/app_visual_system.dart';
import '../../../auth/auth_state.dart';
import '../../settings/state/settings_controller.dart';
import '../inspection/domain/models.dart';
import '../inspection/state/survey_controller.dart';
import 'fire_door_web_shell_scaffold.dart';

class FireDoorWorkspaceScreen extends ConsumerWidget {
  const FireDoorWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    if (settings.activeWorkspaceKey != 'fire-door') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(settingsControllerProvider.notifier).setActiveWorkspace('fire-door');
      });
    }
    final surveys = ref.watch(surveyControllerFamilyProvider(InspectionWorkspace.fireDoor)).surveys;

    final role = auth.userRole ?? UserRole.worker;
    final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
    final isWorker = role == UserRole.worker && !isSuperAdmin;
    final showPreinstall = role == UserRole.manager || isSuperAdmin;

    String routeWithCompanyGate(String route) {
      if (settings.onboardingCompleted) return route;
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
      .where((d) => !d.replacementRequired && d.remedialStatus == RemedialStatus.forApproval)
        .length;

    final installationAwaiting = surveys
        .expand((s) => s.preInstallItems)
        .where((i) => i.status == InstallationStatus.forApproval)
        .length;

    final content = ListView(
        padding: const EdgeInsets.all(AppSpace.m),
        children: [
          if (!isWorker) ...[
            AppActionTile(
              title: 'Fire Door Inspection',
              subtitle: 'Open projects and continue with the inspection workflow.',
              icon: Icons.fact_check_outlined,
              badgeText: null,
              onTap: () => context.go(routeWithCompanyGate('/workspace/fire-door/inspection/projects')),
            ),
            const SizedBox(height: AppSpace.s),
          ],
          AppActionTile(
            title: 'Remedial Works',
            subtitle: 'Worker execution and manager approval review.',
            icon: Icons.build_outlined,
            badgeText: remedialAwaiting > 0 ? '$remedialAwaiting awaiting approval' : null,
            onTap: () => context.go(routeWithCompanyGate('/workspace/fire-door/modules/remedials/projects')),
          ),
          if (showPreinstall) ...[
            const SizedBox(height: AppSpace.s),
            AppActionTile(
              title: 'Pre-Installation Survey',
              subtitle: 'Manager source module for opening specifications.',
              icon: Icons.rule_folder_outlined,
              badgeText: null,
              onTap: () => context.go(routeWithCompanyGate('/workspace/fire-door/modules/preinstall/projects')),
            ),
          ],
          const SizedBox(height: AppSpace.s),
          AppActionTile(
            title: 'Installation & Handover',
            subtitle: 'Worker completion and manager approval review.',
            icon: Icons.construction_outlined,
            badgeText: installationAwaiting > 0 ? '$installationAwaiting awaiting approval' : null,
            onTap: () => context.go(routeWithCompanyGate('/workspace/fire-door/modules/installation/projects')),
          ),
        ],
      );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: '/workspace/fire-door',
        title: 'Fire Door Inspection',
        workflowLabel: 'Inspection Projects',
        drawerRoute: '/workspace/fire-door',
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fire Door Inspection'),
      ),
      drawer: const AppDrawer(currentRoute: '/workspace/fire-door'),
      body: content,
    );
  }
}
