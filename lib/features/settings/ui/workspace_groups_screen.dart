import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../domain/app_settings.dart';
import '../state/settings_controller.dart';

class WorkspaceGroupsScreen extends ConsumerStatefulWidget {
  const WorkspaceGroupsScreen({super.key});

  @override
  ConsumerState<WorkspaceGroupsScreen> createState() => _WorkspaceGroupsScreenState();
}

class _WorkspaceGroupsScreenState extends ConsumerState<WorkspaceGroupsScreen> {
  late String _workspaceKey;
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final role = auth.userRole ?? UserRole.worker;
    final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
    final canManage = role == UserRole.manager || role == UserRole.owner || isSuperAdmin;

    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);

    if (!_seeded) {
      _seeded = true;
      _workspaceKey = settings.activeWorkspaceKey;
    }

    final usersAsync = ref.watch(companyUsersProvider);
    final groups = settings.workspaceGroups[_workspaceKey] ?? const <WorkspaceWorkerGroup>[];
    final assignments = settings.workspaceWorkerGroupAssignments[_workspaceKey] ?? const <String, String>{};

    if (!canManage) {
      return const Scaffold(
        body: Center(child: Text('Only managers can manage workspace groups.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: _workspaceKey),
      ),
      drawer: const AppDrawer(currentRoute: '/company/workspace-groups'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _workspaceChip('fire-door', 'Fire Door'),
              _workspaceChip('fire-stopping', 'Fire Stopping'),
              _workspaceChip('snagging', 'Snagging'),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            color: const Color(0xFFEAF3FF),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Control Project Access with Groups',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Groups are optional. Use them when you need to limit project access for specific teams or subcontractors. If you do not use groups, all team members keep access to all projects.',
                    style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _showCreateGroupDialog(ctrl),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Group'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.go('/company/team-users'),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Invite Team Members'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Create Group'),
              subtitle: const Text('Use team name, subcontractor name, or Group 1, Group 2, ...'),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () => _showCreateGroupDialog(ctrl),
            ),
          ),
          const SizedBox(height: 10),
          if (groups.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'No groups created yet. This is fine for smaller teams. Without groups, all team members can access all projects. Create groups only when you need restricted access.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
            )
          else
            Column(
              children: [
                for (final g in groups)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.groups_2_outlined),
                      title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('Members: ${assignments.values.where((id) => id == g.id).length}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Rename',
                            onPressed: () => _showRenameGroupDialog(ctrl, g),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _deleteGroup(ctrl, g),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          const Text('Assign Team Members to Groups', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Leave a team member unassigned if they should continue to access all projects. Assign a group only when their access needs to be restricted.',
            style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          usersAsync.when(
            data: (users) {
              final workers = users
                  .where((u) => u.role == UserRole.worker && u.status == UserAccountStatus.active)
                  .toList();
              if (workers.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('No active team members found.', style: TextStyle(fontSize: 13)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/company/team-users'),
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Invite Team Members'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  for (final worker in workers)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(worker.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(worker.email),
                        trailing: SizedBox(
                          width: 240,
                          child: DropdownButtonFormField<String?>(
                            initialValue: assignments[worker.id],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              labelText: 'Group',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Unassigned'),
                              ),
                              ...groups.map(
                                (g) => DropdownMenuItem<String?>(
                                  value: g.id,
                                  child: Text(g.name),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              ctrl.assignWorkerToGroup(
                                workspaceKey: _workspaceKey,
                                userId: worker.id,
                                groupId: value,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            )),
            error: (_, __) => const Text('Failed to load workers.'),
          ),
        ],
      ),
    );
  }

  Widget _workspaceChip(String key, String label) {
    final selected = _workspaceKey == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _workspaceKey = key);
        ref.read(settingsControllerProvider.notifier).setActiveWorkspace(key);
      },
    );
  }

  Future<void> _showCreateGroupDialog(SettingsController ctrl) async {
    final textCtrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: textCtrl,
              decoration: const InputDecoration(
                labelText: 'Group name',
                border: OutlineInputBorder(),
                hintText: 'Group 1 / Subcontractor Name',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Create or select a group, then add the team that should manage only those projects in this workspace.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    if (created != true) return;
    final name = textCtrl.text.trim();
    if (name.isEmpty) return;
    ctrl.createWorkspaceGroup(workspaceKey: _workspaceKey, name: name);
  }

  Future<void> _showRenameGroupDialog(SettingsController ctrl, WorkspaceWorkerGroup group) async {
    final textCtrl = TextEditingController(text: group.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: textCtrl,
          decoration: const InputDecoration(labelText: 'Group name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (confirmed != true) return;
    ctrl.renameWorkspaceGroup(workspaceKey: _workspaceKey, groupId: group.id, name: textCtrl.text.trim());
  }

  Future<void> _deleteGroup(SettingsController ctrl, WorkspaceWorkerGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('Delete "${group.name}"? Workers in this group will become unassigned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed == true) {
      ctrl.deleteWorkspaceGroup(workspaceKey: _workspaceKey, groupId: group.id);
    }
  }
}
