import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_state.dart';
import '../../settings/state/settings_controller.dart';
import '../../snagging/domain/snagging_models.dart';
import '../../surveys/domain/models.dart';
import '../domain/workflow_notification.dart';
import 'push_notification_service.dart';

class WorkflowEventDispatcher {
  WorkflowEventDispatcher(this._ref);

  final Ref _ref;

  Future<void> dispatchDoorWorkflowEvent({
    required Survey survey,
    required Door door,
    required String notificationType,
    required String title,
    required String body,
    required bool toManagers,
    required bool requiresAction,
  }) async {
    final auth = _ref.read(authControllerProvider);
    final companyId = auth.companyId;
    if (companyId == null || companyId.isEmpty || auth.uid.isEmpty) return;

    final workspaceKey = inspectionWorkspaceSlug(survey.workspace);
    final recipients = await _resolveDoorRecipients(
      companyId: companyId,
      workspaceKey: workspaceKey,
      assignedGroupIds: survey.assignedGroupIds,
      toManagers: toManagers,
    );
    if (recipients.isEmpty) return;

    final routeTarget = toManagers
        ? '/workspace/$workspaceKey/remedials/${survey.id}/doors/${door.id}/review'
        : '/workspace/$workspaceKey/remedials/${survey.id}/doors/${door.id}';
    await _ref.read(workflowNotificationRepositoryProvider).publishNotifications(
      companyId: companyId,
      notifications: recipients
          .map(
            (recipient) => WorkflowNotification(
              id: '',
              companyId: companyId,
              recipientUserId: recipient['id'] as String,
              actorUserId: auth.uid,
              title: title,
              body: body,
              workspaceId: workspaceKey,
              module: 'remedial',
              projectId: survey.id,
              doorId: door.id,
              taskId: door.id,
              routeTarget: routeTarget,
              status: door.remedialStatus.name,
              notificationType: notificationType,
              requiresAction: requiresAction,
              isRead: false,
              createdAt: null,
              readAt: null,
            ),
          )
          .toList(),
    );
  }

  Future<void> dispatchInstallationWorkflowEvent({
    required Survey survey,
    required PreInstallItem item,
    required String notificationType,
    required String title,
    required String body,
    required bool toManagers,
    required bool requiresAction,
  }) async {
    final auth = _ref.read(authControllerProvider);
    final companyId = auth.companyId;
    if (companyId == null || companyId.isEmpty || auth.uid.isEmpty) return;

    final workspaceKey = inspectionWorkspaceSlug(survey.workspace);
    final recipients = await _resolveDoorRecipients(
      companyId: companyId,
      workspaceKey: workspaceKey,
      assignedGroupIds: survey.assignedGroupIds,
      toManagers: toManagers,
    );
    if (recipients.isEmpty) return;

    final routeTarget = toManagers
        ? '/workspace/$workspaceKey/installation/${survey.id}/items/${item.id}/review'
        : '/workspace/$workspaceKey/installation/${survey.id}/items/${item.id}';
    await _ref.read(workflowNotificationRepositoryProvider).publishNotifications(
      companyId: companyId,
      notifications: recipients
          .map(
            (recipient) => WorkflowNotification(
              id: '',
              companyId: companyId,
              recipientUserId: recipient['id'] as String,
              actorUserId: auth.uid,
              title: title,
              body: body,
              workspaceId: workspaceKey,
              module: 'installation',
              projectId: survey.id,
              itemId: item.id,
              taskId: item.id,
              routeTarget: routeTarget,
              status: item.status.name,
              notificationType: notificationType,
              requiresAction: requiresAction,
              isRead: false,
              createdAt: null,
              readAt: null,
            ),
          )
          .toList(),
    );
  }

  Future<void> dispatchSnaggingWorkflowEvent({
    required SnaggingProject project,
    required SnaggingIssue issue,
    required String notificationType,
    required String title,
    required String body,
    required bool toManagers,
    required bool requiresAction,
  }) async {
    final auth = _ref.read(authControllerProvider);
    final companyId = auth.companyId;
    if (companyId == null || companyId.isEmpty || auth.uid.isEmpty) return;

    final repository = _ref.read(workflowNotificationRepositoryProvider);
    final recipients = toManagers
        ? await repository.listRecipientsByRole(companyId: companyId, roles: const {'owner', 'admin', 'manager'})
        : await repository.listAllMembers(companyId: companyId);
    final filtered = toManagers
        ? recipients
        : recipients.where((member) {
            final userId = (member['id'] as String? ?? '').trim();
            return issue.assignedToUserId.trim().isEmpty || userId == issue.assignedToUserId.trim();
          }).toList();
    if (filtered.isEmpty) return;

    await repository.publishNotifications(
      companyId: companyId,
      notifications: filtered
          .map(
            (recipient) => WorkflowNotification(
              id: '',
              companyId: companyId,
              recipientUserId: recipient['id'] as String,
              actorUserId: auth.uid,
              title: title,
              body: body,
              workspaceId: 'snagging',
              module: 'snagging',
              projectId: project.id,
              itemId: issue.id,
              taskId: issue.id,
              routeTarget: '/workspace/snagging/inspection/projects/${project.id}/items/${issue.id}',
              status: issue.status.name,
              notificationType: notificationType,
              requiresAction: requiresAction,
              isRead: false,
              createdAt: null,
              readAt: null,
            ),
          )
          .toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _resolveDoorRecipients({
    required String companyId,
    required String workspaceKey,
    required List<String> assignedGroupIds,
    required bool toManagers,
  }) async {
    final repository = _ref.read(workflowNotificationRepositoryProvider);
    if (toManagers) {
      return repository.listRecipientsByRole(companyId: companyId, roles: const {'owner', 'admin', 'manager'});
    }

    final settings = _ref.read(settingsControllerProvider.notifier);
    final members = await repository.listRecipientsByRole(companyId: companyId, roles: const {'worker'});
    if (assignedGroupIds.isEmpty) return members;
    return members.where((member) {
      final groupId = settings.workerGroupIdForWorkspace(
        workspaceKey: workspaceKey,
        userId: (member['id'] as String? ?? '').trim(),
      );
      return groupId != null && assignedGroupIds.contains(groupId);
    }).toList();
  }
}

final workflowEventDispatcherProvider = Provider<WorkflowEventDispatcher>((ref) {
  return WorkflowEventDispatcher(ref);
});
