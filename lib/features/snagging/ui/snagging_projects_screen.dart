import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/app_visual_system.dart';
import '../../../app/ui/mobile_bottom_navigation_bar.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../../auth/current_user_role.dart';
import '../../fire_door/inspection/domain/models.dart';
import '../../fire_door/inspection/state/survey_controller.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../settings/state/settings_controller.dart';
import '../domain/snagging_models.dart';
import '../state/snagging_module_controller.dart';

class SnaggingProjectsScreen extends ConsumerStatefulWidget {
  const SnaggingProjectsScreen({super.key});

  @override
  ConsumerState<SnaggingProjectsScreen> createState() =>
      _SnaggingProjectsScreenState();
}

class _SnaggingProjectsScreenState
    extends ConsumerState<SnaggingProjectsScreen> {
  bool _showArchived = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedProjectIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _canManageProjectLifecycle(AuthState auth) {
    final actualRole = auth.actualRole;
    final userRole = auth.userRole ?? UserRole.worker;
    if (actualRole == UserRole.superAdmin) return true;
    return userRole == UserRole.manager ||
        actualRole == UserRole.owner ||
        actualRole == UserRole.admin;
  }

  Future<bool> _confirmPermanentDelete(BuildContext context) async {
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

  Future<void> _handleProjectAction({
    required BuildContext context,
    required SnaggingModuleController controller,
    required SurveyController surveyController,
    required AuthState auth,
    required SnaggingProject project,
    required String action,
  }) async {
    if (action == 'archive') {
      final archivedBy = auth.currentUser?.name.trim().isNotEmpty == true
          ? auth.currentUser!.name.trim()
          : auth.email;
      controller.archiveProject(
        projectId: project.id,
        archivedBy: archivedBy,
      );
      if (project.surveyId.isNotEmpty) {
        surveyController.archiveSurvey(
          surveyId: project.surveyId,
          archivedBy: archivedBy,
        );
      }
      return;
    }

    if (action == 'restore') {
      final restoredBy = auth.currentUser?.name.trim().isNotEmpty == true
          ? auth.currentUser!.name.trim()
          : auth.email;
      controller.restoreProject(projectId: project.id, restoredBy: restoredBy);
      if (project.surveyId.isNotEmpty) {
        surveyController.restoreSurvey(
          surveyId: project.surveyId,
          restoredBy: restoredBy,
        );
      }
      return;
    }

    if (action == 'delete') {
      final confirmed = await _confirmPermanentDelete(context);
      if (!confirmed) return;
      final linkedSurveyId = project.surveyId;
      await controller.deleteProjectPermanently(projectId: project.id);
      if (linkedSurveyId.isNotEmpty) {
        await surveyController.deleteSurveyPermanently(
            surveyId: linkedSurveyId);
      }
    }
  }

  Future<void> _openProjectActions({
    required BuildContext context,
    required SnaggingModuleController controller,
    required SurveyController surveyController,
    required AuthState auth,
    required SnaggingProject project,
    required bool canManageProjectLifecycle,
  }) async {
    if (!canManageProjectLifecycle) return;

    String? action;
    if (kIsWeb) {
      action = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Project actions'),
          children: [
            if (!project.isArchived)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'archive'),
                child: const Text('Archive'),
              ),
            if (project.isArchived)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'restore'),
                child: const Text('Restore'),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Delete permanently',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!project.isArchived)
                ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('Archive'),
                  onTap: () => Navigator.pop(ctx, 'archive'),
                ),
              if (project.isArchived)
                ListTile(
                  leading: const Icon(Icons.unarchive_outlined),
                  title: const Text('Restore'),
                  onTap: () => Navigator.pop(ctx, 'restore'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined,
                    color: Colors.red),
                title: const Text('Delete permanently',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      );
    }

    if (action == null) return;
    await _handleProjectAction(
      context: context,
      controller: controller,
      surveyController: surveyController,
      auth: auth,
      project: project,
      action: action,
    );
  }

  void _toggleProjectSelection(String projectId) {
    setState(() {
      if (_selectedProjectIds.contains(projectId)) {
        _selectedProjectIds.remove(projectId);
      } else {
        _selectedProjectIds.add(projectId);
      }
    });
  }

  void _setAllProjectSelections(List<SnaggingProject> projects, bool selected) {
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

  Future<void> _bulkDeleteSelectedProjects({
    required BuildContext context,
    required SnaggingModuleController controller,
    required SurveyController surveyController,
    required List<SnaggingProject> projects,
  }) async {
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
      final linkedSurveyId = project.surveyId;
      await controller.deleteProjectPermanently(projectId: project.id);
      if (linkedSurveyId.isNotEmpty) {
        await surveyController.deleteSurveyPermanently(
            surveyId: linkedSurveyId);
      }
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

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserRoleProvider);
    final isWorker = role == UserRole.worker;

    final state = ref.watch(snaggingModuleControllerProvider);
    final controller = ref.read(snaggingModuleControllerProvider.notifier);
    final surveyController = ref.read(
        surveyControllerFamilyProvider(InspectionWorkspace.snagging).notifier);
    final auth = ref.watch(authControllerProvider);
    final showMobileBottomNav = shouldShowMobileBottomNavigation(context);

    final workerGroupId = isWorker
        ? ref
            .read(settingsControllerProvider.notifier)
            .workerGroupIdForWorkspace(
                workspaceKey: 'snagging', userId: auth.uid)
        : null;

    final visibleProjects = state.projects.where((project) {
      if (!isWorker) return true;
      if (project.surveyId.isEmpty) return true;
      final survey = surveyController.getById(project.surveyId);
      if (survey == null) return true;
      if (workerGroupId == null || workerGroupId.isEmpty) return true;
      if (survey.assignedGroupIds.isEmpty) return true;
      return survey.assignedGroupIds.contains(workerGroupId);
    }).toList();
    final filteredProjects = visibleProjects
        .where((project) =>
            _showArchived ? project.isArchived : !project.isArchived)
        .toList();
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final searchedProjects = filteredProjects.where((project) {
      if (normalizedQuery.isEmpty) return true;
      final survey = project.surveyId.isEmpty
          ? null
          : surveyController.getById(project.surveyId);
      final searchable = <String>[
        project.name,
        project.client,
        project.addressLine1,
        project.addressLine2,
        project.city,
        project.postcode,
        survey?.reportName ?? '',
        survey?.reference ?? '',
        survey?.registerReference ?? '',
        survey?.clientName ?? '',
        survey?.siteAddress ?? '',
        survey?.addressLine1 ?? '',
        survey?.addressLine2 ?? '',
        survey?.cityTown ?? '',
        survey?.postCode ?? '',
      ].join(' ').toLowerCase();
      return searchable.contains(normalizedQuery);
    }).toList();
    final selectedVisibleCount = searchedProjects
        .where((p) => _selectedProjectIds.contains(p.id))
        .length;
    final allVisibleSelected = searchedProjects.isNotEmpty &&
        selectedVisibleCount == searchedProjects.length;
    final canManageProjectLifecycle = _canManageProjectLifecycle(auth);

    void addProject() {
      final project = controller.createProject();
      final survey = surveyController.createSurvey(SurveyType.snagging);
      controller.updateProject(
          project.id, (p) => p.copyWith(surveyId: survey.id));
      context
          .go('/workspace/snagging/inspection/projects/${project.id}/details');
    }

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.m),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Create and manage projects for Snagging Inspection.',
                  style: TextStyle(color: Colors.black54, height: 1.3),
                ),
              ),
              const SizedBox(height: AppSpace.m),
              if (visibleProjects.isNotEmpty) ...[
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Active'),
                      selected: !_showArchived,
                      onSelected: (_) => setState(() => _showArchived = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Archived'),
                      selected: _showArchived,
                      onSelected: (_) => setState(() => _showArchived = true),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.s),
                TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search by name, number, address, client...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpace.s),
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
                const SizedBox(height: AppSpace.m),
              ],
              if (canManageProjectLifecycle && searchedProjects.isNotEmpty) ...[
                Row(
                  children: [
                    Checkbox(
                      value: allVisibleSelected,
                      onChanged: (value) => _setAllProjectSelections(
                          searchedProjects, value ?? false),
                    ),
                    const Text('All'),
                    const Spacer(),
                    if (selectedVisibleCount > 0)
                      TextButton.icon(
                        onPressed: () => _bulkDeleteSelectedProjects(
                          context: context,
                          controller: controller,
                          surveyController: surveyController,
                          projects: searchedProjects,
                        ),
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        label: Text(
                          'Delete Selected ($selectedVisibleCount)',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.s),
              ],
              Expanded(
                child: searchedProjects.isEmpty
                    ? AppEmptyState(
                        icon: Icons.folder_open_outlined,
                        title: normalizedQuery.isNotEmpty
                            ? 'No matching projects'
                            : _showArchived
                                ? 'No archived projects'
                                : 'No projects yet',
                        message: normalizedQuery.isNotEmpty
                            ? 'No project matches your search criteria.'
                            : _showArchived
                                ? 'Archived projects will appear here.'
                                : 'Create your first inspection project to get started.',
                        actionLabel: '+ Add Job',
                        onAction: (_showArchived || normalizedQuery.isNotEmpty)
                            ? null
                            : addProject,
                      )
                    : ListView.separated(
                        itemCount: searchedProjects.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpace.s),
                        itemBuilder: (context, index) {
                          final project = searchedProjects[index];
                          final survey = project.surveyId.isEmpty
                              ? null
                              : surveyController.getById(project.surveyId);
                          return GestureDetector(
                            onSecondaryTapUp: (_) => _openProjectActions(
                              context: context,
                              controller: controller,
                              surveyController: surveyController,
                              auth: auth,
                              project: project,
                              canManageProjectLifecycle:
                                  canManageProjectLifecycle,
                            ),
                            child: Card(
                              child: ListTile(
                                leading: canManageProjectLifecycle
                                    ? Checkbox(
                                        value: _selectedProjectIds
                                            .contains(project.id),
                                        onChanged: (_) =>
                                            _toggleProjectSelection(project.id),
                                      )
                                    : null,
                                title: Text(
                                  project.name.isEmpty
                                      ? 'Untitled project'
                                      : project.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  survey?.siteAddress.trim().isNotEmpty == true
                                      ? survey!.siteAddress
                                      : 'No address',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (project.isArchived)
                                      Container(
                                        margin: const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF3E0),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'Archived',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    PopupMenuButton<String>(
                                      enabled: canManageProjectLifecycle,
                                      onSelected: (value) =>
                                          _handleProjectAction(
                                        context: context,
                                        controller: controller,
                                        surveyController: surveyController,
                                        auth: auth,
                                        project: project,
                                        action: value,
                                      ),
                                      itemBuilder: (_) => [
                                        if (!project.isArchived)
                                          const PopupMenuItem<String>(
                                            value: 'archive',
                                            child: Text('Archive'),
                                          ),
                                        if (project.isArchived)
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
                                onLongPress: () => _openProjectActions(
                                  context: context,
                                  controller: controller,
                                  surveyController: surveyController,
                                  auth: auth,
                                  project: project,
                                  canManageProjectLifecycle:
                                      canManageProjectLifecycle,
                                ),
                                onTap: () => context.go(
                                    '/workspace/snagging/inspection/projects/${project.id}/details'),
                              ),
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
        currentRoute: '/workspace/snagging/inspection/projects',
        title: 'Snagging Inspection',
        workflowLabel: 'Inspection Projects',
        drawerRoute: '/workspace/snagging/inspection/projects',
        workspaceKey: 'snagging',
        body: content,
        backgroundColor: const Color(0xFFF6F7F9),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      drawer: const AppDrawer(
          currentRoute: '/workspace/snagging/inspection/projects'),
      appBar: AppBar(
        title: const Text('Snagging Projects'),
        bottom: const WorkspaceSwitchCardsBar(currentWorkspaceKey: 'snagging'),
      ),
      bottomNavigationBar:
          showMobileBottomNav ? const MobileBottomNavigationBar() : null,
      body: content,
    );
  }
}
