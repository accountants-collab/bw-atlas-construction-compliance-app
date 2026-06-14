import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/app_visual_system.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../settings/state/settings_controller.dart';
import '../domain/snagging_models.dart';
import '../state/snagging_module_controller.dart';

class SnaggingWorkspaceScreen extends ConsumerWidget {
  const SnaggingWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    if (settings.activeWorkspaceKey != 'snagging') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(settingsControllerProvider.notifier).setActiveWorkspace('snagging');
      });
    }

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

    final state = ref.watch(snaggingModuleControllerProvider);
    final projectCount = state.projects.length;
    final awaitingVerification = state.projects
        .expand((p) => p.issues)
      .where((i) => i.status == SnaggingStatus.awaitingVerification && i.completionPhotoBase64.isNotEmpty)
        .length;

    final content = ListView(
      padding: const EdgeInsets.all(AppSpace.m),
      children: [
        AppActionTile(
          icon: Icons.fact_check_outlined,
          title: 'Snagging Inspection',
          subtitle: 'Open and manage snagging inspection projects',
          badgeText: projectCount > 0 ? '$projectCount projects' : null,
          onTap: () => context.go(routeWithCompanyGate('/workspace/snagging/inspection/projects')),
        ),
        const SizedBox(height: AppSpace.s),
        AppActionTile(
          title: 'Snagging Verification',
          subtitle: 'Review completed snagging work and approve or reject',
          icon: Icons.verified_outlined,
          badgeText: awaitingVerification > 0 ? '$awaitingVerification awaiting review' : null,
          onTap: () => context.go(routeWithCompanyGate('/workspace/snagging/verification/projects')),
        ),
      ],
    );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: '/workspace/snagging',
        title: 'Snagging Inspection',
        workspaceKey: 'snagging',
        workflowLabel: 'Inspection Projects',
        drawerRoute: '/workspace/snagging',
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Snagging Inspection'),
        bottom: const WorkspaceSwitchCardsBar(currentWorkspaceKey: 'snagging'),
      ),
      drawer: const AppDrawer(currentRoute: '/workspace/snagging'),
      body: content,
    );
  }
}
