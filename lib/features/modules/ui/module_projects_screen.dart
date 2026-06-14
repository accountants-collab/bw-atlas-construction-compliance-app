import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/mobile_bottom_navigation_bar.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../../auth/current_user_role.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../remedials/ui/remedial_project_list_screen.dart';
import '../../settings/state/settings_controller.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/state/survey_controller.dart';

enum AppModuleKey { inspection, remedials, preinstall, installation }

AppModuleKey? parseModuleKey(String raw) {
  switch (raw) {
    case 'inspection':
      return AppModuleKey.inspection;
    case 'remedials':
      return AppModuleKey.remedials;
    case 'preinstall':
      return AppModuleKey.preinstall;
    case 'installation':
      return AppModuleKey.installation;
    default:
      return null;
  }
}

InspectionWorkspace? parseWorkspaceKey(String raw) {
  switch (raw) {
    case 'fire-door':
      return InspectionWorkspace.fireDoor;
    case 'fire-stopping':
      return InspectionWorkspace.fireStopping;
    case 'snagging':
      return InspectionWorkspace.snagging;
    default:
      return null;
  }
}

SurveyType surveyTypeForInspectionWorkspace(InspectionWorkspace workspace) {
  switch (workspace) {
    case InspectionWorkspace.fireDoor:
      return SurveyType.survey;
    case InspectionWorkspace.fireStopping:
      return SurveyType.fireStopping;
    case InspectionWorkspace.snagging:
      return SurveyType.snagging;
  }
}

SurveyType surveyTypeForModule(
    AppModuleKey module, InspectionWorkspace workspace) {
  switch (module) {
    case AppModuleKey.inspection:
      return surveyTypeForInspectionWorkspace(workspace);
    case AppModuleKey.remedials:
      return SurveyType.maintenance;
    case AppModuleKey.preinstall:
      return SurveyType.installationSurvey;
    case AppModuleKey.installation:
      return SurveyType.installationSurvey;
  }
}

String inspectionTitleForWorkspace(InspectionWorkspace workspace) {
  switch (workspace) {
    case InspectionWorkspace.fireDoor:
      return 'Fire Door Inspection';
    case InspectionWorkspace.fireStopping:
      return 'Fire Stopping Inspection';
    case InspectionWorkspace.snagging:
      return 'Snagging Inspection';
  }
}

String moduleTitle(AppModuleKey module, InspectionWorkspace workspace) {
  switch (module) {
    case AppModuleKey.inspection:
      return inspectionTitleForWorkspace(workspace);
    case AppModuleKey.remedials:
      return 'Remedial Works';
    case AppModuleKey.preinstall:
      return 'Pre-Installation Survey';
    case AppModuleKey.installation:
      return 'Installation & Handover';
  }
}

String moduleSubtitle(AppModuleKey module, InspectionWorkspace workspace) {
  switch (module) {
    case AppModuleKey.inspection:
      return 'Create and manage projects for ${inspectionTitleForWorkspace(workspace)}.';
    case AppModuleKey.remedials:
      return 'Track remedial works projects and manage defect resolution.';
    case AppModuleKey.preinstall:
      return 'Build factory-ready opening specifications for manufacture and ordering.';
    case AppModuleKey.installation:
      return 'Execute installation workflow with evidence capture and approvals.';
  }
}

class ModuleProjectsScreen extends ConsumerStatefulWidget {
  final String moduleKey;
  final String workspaceKey;

  const ModuleProjectsScreen({
    super.key,
    required this.moduleKey,
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<ModuleProjectsScreen> createState() =>
      _ModuleProjectsScreenState();
}

class _ModuleProjectsScreenState extends ConsumerState<ModuleProjectsScreen> {
  final Set<String> _selectedProjectIds = <String>{};

  void _toggleProjectSelection(String projectId) {
    setState(() {
      if (_selectedProjectIds.contains(projectId)) {
        _selectedProjectIds.remove(projectId);
      } else {
        _selectedProjectIds.add(projectId);
      }
    });
  }

  void _setAllProjectSelections(List<Survey> projects, bool selected) {
    setState(() {
      if (selected) {
        _selectedProjectIds
          ..clear()
          ..addAll(projects.map((p) => p.id));
      } else {
        _selectedProjectIds.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final module = parseModuleKey(widget.moduleKey);
    final workspace = parseWorkspaceKey(widget.workspaceKey);

    if (module == null || workspace == null) {
      return const Scaffold(body: Center(child: Text('Module not found')));
    }

    final role = ref.watch(currentUserRoleProvider);
    final isWorker = role == UserRole.worker;
    final auth = ref.watch(authControllerProvider);
    if (role == UserRole.worker &&
        module != AppModuleKey.remedials &&
        module != AppModuleKey.installation) {
      return const Scaffold(
        body: Center(
            child: Text(
                'Access restricted. Worker role can access only Remedial Works and Installation.')),
      );
    }

    if (module == AppModuleKey.remedials) {
      return RemedialProjectListScreen(workspace: workspace);
    }

    final showMobileBottomNav = shouldShowMobileBottomNavigation(context);

    final settings = ref.watch(settingsControllerProvider);
    if (settings.activeWorkspaceKey != widget.workspaceKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(settingsControllerProvider.notifier)
            .setActiveWorkspace(widget.workspaceKey);
      });
    }

    final surveyController =
        ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final state = ref.watch(surveyControllerFamilyProvider(workspace));
    final type = surveyTypeForModule(module, workspace);
    final workerGroupId = isWorker
        ? settingsControllerGroupId(
            ref: ref,
            workspaceKey: widget.workspaceKey,
            userId: auth.uid,
          )
        : null;

    final projects = state.surveys.where((s) {
      final includeByType = s.type == type;
      final includeReplacementInInspectionProject =
          module == AppModuleKey.installation &&
              workspace == InspectionWorkspace.fireDoor &&
              s.type == SurveyType.survey &&
              s.preInstallItems.any((item) => item.fullReplacementTask);
      if (!includeByType && !includeReplacementInInspectionProject)
        return false;
      if (!isWorker) return true;
      if (workerGroupId == null || workerGroupId.isEmpty) return true;
      if (s.assignedGroupIds.isEmpty) return false;
      return s.assignedGroupIds.contains(workerGroupId);
    }).toList();

    final canManageProjectLifecycle = !isWorker &&
        (auth.actualRole == UserRole.superAdmin ||
            (auth.userRole ?? UserRole.worker) == UserRole.manager ||
            auth.actualRole == UserRole.owner ||
            auth.actualRole == UserRole.admin);

    String projectDetailsRoute(Survey project) {
      if (module == AppModuleKey.inspection) {
        return '/workspace/${widget.workspaceKey}/inspection/projects/${project.id}/details';
      }
      return '/workspace/${widget.workspaceKey}/modules/${widget.moduleKey}/projects/${project.id}/details';
    }

    Future<bool> confirmPermanentDelete() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permanently delete project?'),
          content: const Text(
            'This action cannot be undone. All inspection data will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      );
      return result == true;
    }

    Future<void> handleProjectAction(Survey project, String action) async {
      if (!canManageProjectLifecycle) return;
      if (action == 'archive') {
        final archivedBy = auth.currentUser?.name.trim().isNotEmpty == true
            ? auth.currentUser!.name.trim()
            : auth.email;
        surveyController.archiveSurvey(
          surveyId: project.id,
          archivedBy: archivedBy,
        );
        return;
      }
      if (action == 'restore') {
        final restoredBy = auth.currentUser?.name.trim().isNotEmpty == true
            ? auth.currentUser!.name.trim()
            : auth.email;
        surveyController.restoreSurvey(
          surveyId: project.id,
          restoredBy: restoredBy,
        );
        return;
      }
      if (action == 'delete') {
        final confirmed = await confirmPermanentDelete();
        if (!confirmed) return;
        await surveyController.deleteSurveyPermanently(surveyId: project.id);
      }
    }

    Future<void> bulkDeleteSelectedProjects() async {
      final selected =
          projects.where((p) => _selectedProjectIds.contains(p.id)).toList();
      if (selected.isEmpty) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete selected projects?'),
          content: Text(
            'You are about to permanently delete ${selected.length} selected project(s). This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete selected'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      for (final project in selected) {
        await surveyController.deleteSurveyPermanently(surveyId: project.id);
      }

      if (!mounted) return;
      setState(() {
        _selectedProjectIds
            .removeWhere((id) => selected.any((project) => project.id == id));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${selected.length} project(s).')),
      );
    }

    void addProject() {
      final survey = surveyController.createSurvey(type);

      if (module == AppModuleKey.inspection) {
        context.go(
            '/workspace/${widget.workspaceKey}/inspection/projects/${survey.id}/details');
        return;
      }

      context.go(
          '/workspace/${widget.workspaceKey}/modules/${widget.moduleKey}/projects/${survey.id}/details');
    }

    final drawerRoute = module == AppModuleKey.inspection
        ? '/workspace/${widget.workspaceKey}/inspection/projects'
        : '/workspace/${widget.workspaceKey}/modules/${widget.moduleKey}/projects';

    final selectedCount =
        projects.where((p) => _selectedProjectIds.contains(p.id)).length;
    final allSelected = projects.isNotEmpty && selectedCount == projects.length;

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isWorker && module == AppModuleKey.installation
                      ? 'Open installation projects shared by your manager and continue evidence capture.'
                      : moduleSubtitle(module, workspace),
                  style: const TextStyle(color: Colors.black54, height: 1.3),
                ),
              ),
              if (!isWorker) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: addProject,
                        icon: const Icon(Icons.add),
                        label: const Text('+ Add Job'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 14),
              if (canManageProjectLifecycle && projects.isNotEmpty) ...[
                Row(
                  children: [
                    Checkbox(
                      value: allSelected,
                      onChanged: (value) =>
                          _setAllProjectSelections(projects, value ?? false),
                    ),
                    const Text('All'),
                    const Spacer(),
                    if (selectedCount > 0)
                      TextButton.icon(
                        onPressed: bulkDeleteSelectedProjects,
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        label: Text(
                          'Delete Selected ($selectedCount)',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: projects.isEmpty
                    ? Center(
                        child: Text(
                          isWorker
                              ? 'No projects have been shared by your manager yet.'
                              : 'No projects yet.\nClick "+ Add Job" to create your first project.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.black54, height: 1.3),
                        ),
                      )
                    : ListView.builder(
                        itemCount: projects.length,
                        itemBuilder: (context, i) {
                          final p = projects[i];
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: ListTile(
                              leading: canManageProjectLifecycle
                                  ? Checkbox(
                                      value: _selectedProjectIds.contains(p.id),
                                      onChanged: (_) =>
                                          _toggleProjectSelection(p.id),
                                    )
                                  : null,
                              title: Text(
                                p.reportName.trim().isEmpty
                                    ? 'Untitled project'
                                    : p.reportName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                p.siteAddress.trim().isEmpty
                                    ? 'No address'
                                    : p.siteAddress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (p.isArchived)
                                    Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF3E0),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Archived',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  if (!isWorker)
                                    IconButton(
                                      tooltip: 'Edit project details',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () =>
                                          context.go(projectDetailsRoute(p)),
                                    ),
                                  if (canManageProjectLifecycle)
                                    PopupMenuButton<String>(
                                      onSelected: (value) =>
                                          handleProjectAction(p, value),
                                      itemBuilder: (_) => [
                                        if (!p.isArchived)
                                          const PopupMenuItem<String>(
                                            value: 'archive',
                                            child: Text('Archive'),
                                          ),
                                        if (p.isArchived)
                                          const PopupMenuItem<String>(
                                            value: 'restore',
                                            child: Text('Restore'),
                                          ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Text('Delete permanently'),
                                        ),
                                      ],
                                    ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () {
                                switch (module) {
                                  case AppModuleKey.inspection:
                                    context.go(
                                        '/workspace/${widget.workspaceKey}/inspection/projects/${p.id}/doors');
                                    break;
                                  case AppModuleKey.preinstall:
                                    context.go(
                                        '/workspace/${widget.workspaceKey}/preinstall/${p.id}/items');
                                    break;
                                  case AppModuleKey.installation:
                                    context.go(
                                        '/workspace/${widget.workspaceKey}/installation/${p.id}/items');
                                    break;
                                  case AppModuleKey.remedials:
                                    context.go(
                                        '/workspace/${widget.workspaceKey}/remedials/${p.id}/doors');
                                    break;
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: drawerRoute,
        title: moduleTitle(module, workspace),
        workflowLabel: moduleTitle(module, workspace),
        drawerRoute: drawerRoute,
        workspaceKey: widget.workspaceKey,
        body: content,
        backgroundColor: const Color(0xFFF6F7F9),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      drawer: AppDrawer(currentRoute: drawerRoute),
      appBar: AppBar(
        title: Text(moduleTitle(module, workspace)),
        bottom:
            WorkspaceSwitchCardsBar(currentWorkspaceKey: widget.workspaceKey),
      ),
      bottomNavigationBar:
          showMobileBottomNav ? const MobileBottomNavigationBar() : null,
      body: content,
    );
  }
}

String? settingsControllerGroupId({
  required WidgetRef ref,
  required String workspaceKey,
  required String userId,
}) {
  final settings = ref.read(settingsControllerProvider.notifier);
  return settings.workerGroupIdForWorkspace(
      workspaceKey: workspaceKey, userId: userId);
}
