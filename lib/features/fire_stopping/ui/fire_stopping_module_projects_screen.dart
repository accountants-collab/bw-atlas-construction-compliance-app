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
import '../../settings/state/settings_controller.dart';
import '../inspection/domain/models.dart';
import '../inspection/state/survey_controller.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';

class FireStoppingModuleProjectsScreen extends ConsumerStatefulWidget {
  const FireStoppingModuleProjectsScreen({super.key});

  @override
  ConsumerState<FireStoppingModuleProjectsScreen> createState() =>
      _FireStoppingModuleProjectsScreenState();
}

class _FireStoppingModuleProjectsScreenState
    extends ConsumerState<FireStoppingModuleProjectsScreen> {
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
    required SurveyController controller,
    required AuthState auth,
    required Survey project,
    required String action,
  }) async {
    if (action == 'archive') {
      final archivedBy = auth.currentUser?.name.trim().isNotEmpty == true
          ? auth.currentUser!.name.trim()
          : auth.email;
      controller.archiveSurvey(
        surveyId: project.id,
        archivedBy: archivedBy,
      );
      return;
    }
    if (action == 'restore') {
      final restoredBy = auth.currentUser?.name.trim().isNotEmpty == true
          ? auth.currentUser!.name.trim()
          : auth.email;
      controller.restoreSurvey(surveyId: project.id, restoredBy: restoredBy);
      return;
    }
    if (action == 'delete') {
      final confirmed = await _confirmPermanentDelete(context);
      if (!confirmed) return;
      await controller.deleteSurveyPermanently(surveyId: project.id);
    }
  }

  Future<void> _openProjectActions({
    required BuildContext context,
    required SurveyController controller,
    required AuthState auth,
    required Survey project,
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

  Future<void> _bulkDeleteSelectedProjects({
    required BuildContext context,
    required SurveyController controller,
    required List<Survey> projects,
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
      await controller.deleteSurveyPermanently(surveyId: project.id);
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

    if (isWorker) {
      return const Scaffold(
        body: Center(
          child: Text(
              'Access restricted. Worker role can access only Remedial Works and Installation.'),
        ),
      );
    }

    final auth = ref.watch(authControllerProvider);
    final showMobileBottomNav = shouldShowMobileBottomNavigation(context);
    final settings = ref.watch(settingsControllerProvider);
    if (settings.activeWorkspaceKey != 'fire-stopping') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(settingsControllerProvider.notifier)
            .setActiveWorkspace('fire-stopping');
      });
    }

    final controller = ref.read(
        surveyControllerFamilyProvider(InspectionWorkspace.fireStopping)
            .notifier);
    final state = ref.watch(
        surveyControllerFamilyProvider(InspectionWorkspace.fireStopping));
    final workerGroupId = isWorker
        ? ref
            .read(settingsControllerProvider.notifier)
            .workerGroupIdForWorkspace(
                workspaceKey: 'fire-stopping', userId: auth.uid)
        : null;

    final projects = state.surveys.where((s) {
      if (s.type != SurveyType.fireStopping) return false;
      if (!isWorker) return true;
      if (workerGroupId == null || workerGroupId.isEmpty) return true;
      if (s.assignedGroupIds.isEmpty) return false;
      return s.assignedGroupIds.contains(workerGroupId);
    }).toList();
    final canManageProjectLifecycle = _canManageProjectLifecycle(auth);
    final archiveScopedProjects = projects
        .where((p) => _showArchived ? p.isArchived : !p.isArchived)
        .toList();
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final filteredProjects = archiveScopedProjects.where((p) {
      if (normalizedQuery.isEmpty) return true;
      final searchable = <String>[
        p.reportName,
        p.siteName,
        p.reference,
        p.registerReference,
        p.clientName,
        p.siteAddress,
        p.addressLine1,
        p.addressLine2,
        p.cityTown,
        p.postCode,
      ].join(' ').toLowerCase();
      return searchable.contains(normalizedQuery);
    }).toList();
    final selectedVisibleCount = filteredProjects
        .where((p) => _selectedProjectIds.contains(p.id))
        .length;
    final allVisibleSelected = filteredProjects.isNotEmpty &&
        selectedVisibleCount == filteredProjects.length;

    void addProject() {
      final survey = controller.createSurvey(SurveyType.fireStopping);
      context.go(
          '/workspace/fire-stopping/inspection/projects/${survey.id}/details');
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
                  'Create and manage projects for Fire Stopping Inspection.',
                  style: TextStyle(color: Colors.black54, height: 1.3),
                ),
              ),
              const SizedBox(height: AppSpace.m),
              if (projects.isNotEmpty) ...[
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
              if (canManageProjectLifecycle && filteredProjects.isNotEmpty) ...[
                Row(
                  children: [
                    Checkbox(
                      value: allVisibleSelected,
                      onChanged: (value) => _setAllProjectSelections(
                          filteredProjects, value ?? false),
                    ),
                    const Text('All'),
                    const Spacer(),
                    if (selectedVisibleCount > 0)
                      TextButton.icon(
                        onPressed: () => _bulkDeleteSelectedProjects(
                          context: context,
                          controller: controller,
                          projects: filteredProjects,
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
                child: filteredProjects.isEmpty
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
                    : ListView.builder(
                        itemCount: filteredProjects.length,
                        itemBuilder: (context, i) {
                          final p = filteredProjects[i];
                          return GestureDetector(
                            onSecondaryTapUp: (_) => _openProjectActions(
                              context: context,
                              controller: controller,
                              auth: auth,
                              project: p,
                              canManageProjectLifecycle:
                                  canManageProjectLifecycle,
                            ),
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: ListTile(
                                leading: canManageProjectLifecycle
                                    ? Checkbox(
                                        value:
                                            _selectedProjectIds.contains(p.id),
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
                                    IconButton(
                                      tooltip: 'Edit project details',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () {
                                        context.go(
                                            '/workspace/fire-stopping/inspection/projects/${p.id}/details');
                                      },
                                    ),
                                    PopupMenuButton<String>(
                                      enabled: canManageProjectLifecycle,
                                      onSelected: (value) =>
                                          _handleProjectAction(
                                        context: context,
                                        controller: controller,
                                        auth: auth,
                                        project: p,
                                        action: value,
                                      ),
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
                                  ],
                                ),
                                onLongPress: () => _openProjectActions(
                                  context: context,
                                  controller: controller,
                                  auth: auth,
                                  project: p,
                                  canManageProjectLifecycle:
                                      canManageProjectLifecycle,
                                ),
                                onTap: () {
                                  if (p.isArchived) {
                                    context.go(
                                        '/workspace/fire-stopping/inspection/projects/${p.id}/details');
                                  } else {
                                    context.go(
                                        '/workspace/fire-stopping/inspection/projects/${p.id}/doors');
                                  }
                                },
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
        currentRoute: '/workspace/fire-stopping/inspection/projects',
        title: 'Fire Stopping Inspection',
        workflowLabel: 'Inspection Projects',
        drawerRoute: '/workspace/fire-stopping/inspection/projects',
        workspaceKey: 'fire-stopping',
        body: content,
        backgroundColor: const Color(0xFFF6F7F9),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      drawer: const AppDrawer(
          currentRoute: '/workspace/fire-stopping/inspection/projects'),
      appBar: AppBar(
        title: const Text('Fire Stopping Inspection'),
        bottom:
            const WorkspaceSwitchCardsBar(currentWorkspaceKey: 'fire-stopping'),
      ),
      bottomNavigationBar:
          showMobileBottomNav ? const MobileBottomNavigationBar() : null,
      body: content,
    );
  }
}
