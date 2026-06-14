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
import '../../surveys/domain/models.dart';
import '../../surveys/state/survey_controller.dart';
import '../../settings/state/settings_controller.dart';

class RemedialProjectListScreen extends ConsumerStatefulWidget {
  final InspectionWorkspace workspace;

  const RemedialProjectListScreen({
    super.key,
    this.workspace = InspectionWorkspace.fireDoor,
  });

  @override
  ConsumerState<RemedialProjectListScreen> createState() =>
      _RemedialProjectListScreenState();
}

class _RemedialProjectListScreenState
    extends ConsumerState<RemedialProjectListScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(surveyControllerFamilyProvider(widget.workspace));
    final workspaceSlug = inspectionWorkspaceSlug(widget.workspace);
    final auth = ref.watch(authControllerProvider);
    final showMobileBottomNav = shouldShowMobileBottomNavigation(context);
    final role = ref.watch(currentUserRoleProvider);
    final isWorker = role == UserRole.worker;
    final workerGroupId = isWorker
        ? ref
            .read(settingsControllerProvider.notifier)
            .workerGroupIdForWorkspace(
                workspaceKey: workspaceSlug, userId: auth.uid)
        : null;

    bool hasRemedialDoor(Door door) {
      if (door.replacementRequired) return false;
      if (door.remedialItems.any((i) => i.severity.toLowerCase() != 'advisory'))
        return true;
      if (door.issues.any((i) =>
          i.severity == IssueSeverity.fail ||
          i.severity == IssueSeverity.criticalFail)) {
        return true;
      }
      return door.result == DoorResult.fail;
    }

    final projects = state.surveys.where((s) {
      if (s.workspace != widget.workspace) return false;
      // Workers assigned to a specific group only see projects for that group.
      // Workers with no group assignment see ALL projects (small-company usage).
      // If a project has no explicit group assignment, keep it visible to workers.
      if (isWorker && workerGroupId != null && workerGroupId.isNotEmpty) {
        if (s.assignedGroupIds.isNotEmpty &&
            !s.assignedGroupIds.contains(workerGroupId)) return false;
      }
      return s.doors.any(hasRemedialDoor);
    }).toList();

    if (kDebugMode) {
      final visibleStatusCount = projects
          .expand((s) => s.doors)
          .where(hasRemedialDoor)
          .where(
            (d) =>
                d.remedialStatus == RemedialStatus.pending ||
                d.remedialStatus == RemedialStatus.inProgress ||
                d.remedialStatus == RemedialStatus.completedByWorker ||
                d.remedialStatus == RemedialStatus.forApproval ||
                d.remedialStatus == RemedialStatus.rejectedNeedsRework,
          )
          .length;
      debugPrint(
        'remedial_projects_query role=${role.name} workspace=$workspaceSlug uid=${auth.uid} group=${workerGroupId ?? ''} totalSurveys=${state.surveys.length} resultCount=${projects.length} activeWorkerStatusDoors=$visibleStatusCount',
      );
    }

    final pageBody = projects.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No remedial projects yet.\nProjects appear here automatically when inspection failures are recorded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, height: 1.3),
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: projects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final p = projects[index];
              final doors = p.doors.where(hasRemedialDoor).toList();

              final totalDefectiveDoors = doors.length;
              final pending = doors
                  .where((d) => d.remedialStatus == RemedialStatus.pending)
                  .length;
              final inProgress = doors
                  .where(
                    (d) =>
                        d.remedialStatus == RemedialStatus.inProgress ||
                        d.remedialStatus == RemedialStatus.completedByWorker ||
                        d.remedialStatus == RemedialStatus.rejectedNeedsRework,
                  )
                  .length;
              final forApproval = doors
                  .where((d) => d.remedialStatus == RemedialStatus.forApproval)
                  .length;
              final approved = doors
                  .where((d) => d.remedialStatus == RemedialStatus.approved)
                  .length;

              final address = p.siteAddress.trim().isEmpty
                  ? [
                      p.addressLine1.trim(),
                      p.addressLine2.trim(),
                      p.cityTown.trim(),
                      p.postCode.trim(),
                    ].where((e) => e.isNotEmpty).join(', ')
                  : p.siteAddress.trim();

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  title: Text(
                    p.reportName.trim().isEmpty
                        ? 'Untitled project'
                        : p.reportName.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(address.isEmpty ? 'No address' : address),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill('Defective doors', '$totalDefectiveDoors',
                              Colors.red),
                          _pill('Pending', '$pending', Colors.blueGrey),
                          _pill('In progress', '$inProgress', Colors.orange),
                          _pill('For approval', '$forApproval',
                              const Color(0xFF1565C0)),
                          _pill('Approved', '$approved', Colors.green),
                        ],
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context
                      .go('/workspace/$workspaceSlug/remedials/${p.id}/doors'),
                ),
              );
            },
          );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: '/workspace/$workspaceSlug/modules/remedials/projects',
        title: 'Remedial Works',
        workflowLabel: 'Remedial Works',
        drawerRoute: '/workspace/$workspaceSlug/modules/remedials/projects',
        workspaceKey: workspaceSlug,
        body: pageBody,
        backgroundColor: const Color(0xFFF6F7F9),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Remedial Works - Projects'),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: workspaceSlug),
      ),
      drawer: AppDrawer(
          currentRoute: '/workspace/$workspaceSlug/modules/remedials/projects'),
      bottomNavigationBar:
          showMobileBottomNav ? const MobileBottomNavigationBar() : null,
      body: pageBody,
    );
  }

  Widget _pill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style:
            TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 12),
      ),
    );
  }
}
