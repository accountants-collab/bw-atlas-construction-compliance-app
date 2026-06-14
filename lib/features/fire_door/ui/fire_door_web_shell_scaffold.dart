import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workspaces/ui/module_web_shell_scaffold.dart';
import '../../workspaces/ui/module_web_top_navigation.dart';

class FireDoorWebShellScaffold extends ConsumerWidget {
  final String currentRoute;
  final String title;
  final String workspaceKey;
  final String? workflowLabel;
  final String? drawerRoute;
  final String? surveyId;
  final Color? backgroundColor;
  final Widget body;

  const FireDoorWebShellScaffold({
    super.key,
    required this.currentRoute,
    required this.title,
    required this.body,
    this.workspaceKey = 'fire-door',
    this.workflowLabel,
    this.drawerRoute,
    this.surveyId,
    this.backgroundColor,
  });

  String get _resolvedWorkflowLabel {
    if (workspaceKey == 'fire-stopping') {
      return 'Fire Stopping Inspection';
    }

    if (workspaceKey == 'snagging') {
      return 'Snagging Inspection';
    }

    if (workspaceKey == 'fire-door') {
      return 'Fire Door Inspection';
    }

    if (workflowLabel != null && workflowLabel!.trim().isNotEmpty) {
      return workflowLabel!;
    }

    if (currentRoute.contains('/modules/remedials/') || currentRoute.contains('/remedials/')) {
      return 'Remedial Works';
    }
    if (currentRoute.contains('/modules/preinstall/') || currentRoute.contains('/preinstall/')) {
      return 'Pre-Installation';
    }
    if (currentRoute.contains('/modules/installation/') || currentRoute.contains('/installation/')) {
      return 'Installation & Handover';
    }
    return 'Inspection Projects';
  }

  String get _resolvedDrawerRoute {
    if (drawerRoute != null && drawerRoute!.trim().isNotEmpty) {
      return drawerRoute!;
    }

    final prefix = '/workspace/$workspaceKey';
    if (workspaceKey == 'snagging') {
      if (currentRoute.contains('/verification/')) {
        return '$prefix/verification/projects';
      }
      return '$prefix/inspection/projects';
    }

    if (currentRoute.contains('/modules/remedials/') || currentRoute.contains('/remedials/')) {
      return '$prefix/modules/remedials/projects';
    }
    if (currentRoute.contains('/modules/preinstall/') || currentRoute.contains('/preinstall/')) {
      return '$prefix/modules/preinstall/projects';
    }
    if (currentRoute.contains('/modules/installation/') || currentRoute.contains('/installation/')) {
      return '$prefix/modules/installation/projects';
    }
    if (currentRoute == prefix) {
      return prefix;
    }
    return '$prefix/inspection/projects';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moduleChipLabel = workspaceKey == 'fire-stopping'
        ? 'Fire Stopping'
        : workspaceKey == 'snagging'
            ? 'Snagging'
            : 'Fire Door';

    final workflowItems = workspaceKey == 'fire-stopping'
        ? const [
            ModuleWorkflowItem(
              label: 'Fire Stopping Inspection',
              route: '/workspace/fire-stopping/inspection/projects',
            ),
            ModuleWorkflowItem(
              label: 'Manager Review & Approval',
              route: '/workspace/fire-stopping/modules/remedials/projects',
            ),
          ]
        : workspaceKey == 'snagging'
            ? const [
                ModuleWorkflowItem(
                  label: 'Snagging Inspection',
                  route: '/workspace/snagging/inspection/projects',
                ),
                ModuleWorkflowItem(
                  label: 'Snagging Verification',
                  route: '/workspace/snagging/verification/projects',
                ),
              ]
            : const [
                ModuleWorkflowItem(
                  label: 'Inspection Projects',
                  route: '/workspace/fire-door/inspection/projects',
                ),
                ModuleWorkflowItem(
                  label: 'Remedial Works',
                  route: '/workspace/fire-door/modules/remedials/projects',
                ),
                ModuleWorkflowItem(
                  label: 'Pre-Installation',
                  route: '/workspace/fire-door/modules/preinstall/projects',
                ),
                ModuleWorkflowItem(
                  label: 'Installation & Handover',
                  route: '/workspace/fire-door/modules/installation/projects',
                ),
              ];

    return ModuleWebShellScaffold(
      backgroundColor: backgroundColor,
      drawerRoute: _resolvedDrawerRoute,
      config: ModuleWebTopNavigationConfig(
        currentRoute: currentRoute,
        moduleChipLabel: moduleChipLabel,
        moduleTitle: title,
        workflowLabel: _resolvedWorkflowLabel,
        workflowItems: workflowItems,
        quickActions: const [],
      ),
      body: body,
    );
  }
}
