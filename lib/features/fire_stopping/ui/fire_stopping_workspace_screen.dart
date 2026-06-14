import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/app_visual_system.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../settings/state/settings_controller.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../inspection/domain/models.dart';
import '../inspection/state/survey_controller.dart';

class FireStoppingWorkspaceScreen extends ConsumerWidget {
  const FireStoppingWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    if (settings.activeWorkspaceKey != 'fire-stopping') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(settingsControllerProvider.notifier).setActiveWorkspace('fire-stopping');
      });
    }
    final surveys = ref.watch(surveyControllerFamilyProvider(InspectionWorkspace.fireStopping)).surveys;

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
        .where((d) => d.remedialStatus == RemedialStatus.forApproval)
        .length;

    final content = ListView(
      padding: const EdgeInsets.all(AppSpace.m),
      children: [
        AppActionTile(
          title: 'Fire Stopping Inspection',
          subtitle: 'Worker inspection workflow, photo upload, and submission.',
          icon: Icons.fact_check_outlined,
          badgeText: null,
          onTap: () => context.go(routeWithCompanyGate('/workspace/fire-stopping/inspection/projects')),
        ),
        const SizedBox(height: AppSpace.s),
        AppActionTile(
          title: 'Manager Review & Approval',
          subtitle: 'Review submitted work, photos, and approve or reject.',
          icon: Icons.verified_user_outlined,
          badgeText: remedialAwaiting > 0 ? '$remedialAwaiting awaiting approval' : null,
          onTap: () => context.go(routeWithCompanyGate('/workspace/fire-stopping/modules/remedials/projects')),
        ),
      ],
    );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: '/workspace/fire-stopping',
        title: 'Fire Stopping Inspection',
        workspaceKey: 'fire-stopping',
        workflowLabel: 'Inspection Projects',
        drawerRoute: '/workspace/fire-stopping',
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fire Stopping Inspection'),
        bottom: const WorkspaceSwitchCardsBar(currentWorkspaceKey: 'fire-stopping'),
      ),
      drawer: const AppDrawer(currentRoute: '/workspace/fire-stopping'),
      body: content,
    );
  }
}
