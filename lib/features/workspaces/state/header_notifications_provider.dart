import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_state.dart';
import '../../notifications/state/workflow_notifications_provider.dart';
import '../../settings/state/settings_controller.dart';
import '../../snagging/domain/snagging_models.dart' as sg_models;
import '../../snagging/state/snagging_module_controller.dart';
import '../../surveys/domain/models.dart' as survey_models;
import '../../surveys/state/survey_controller.dart' as survey_state;

class HeaderNotificationItem {
  final String title;
  final String subtitle;
  final String route;
  final bool requiresAction;
  final String? workspaceKey;
  final String? moduleKey;
  final String? surveyId;
  final String? doorId;
  final String? notificationId;
  final bool isRead;
  final DateTime? createdAt;

  const HeaderNotificationItem({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.requiresAction,
    this.workspaceKey,
    this.moduleKey,
    this.surveyId,
    this.doorId,
    this.notificationId,
    this.isRead = false,
    this.createdAt,
  });

  String resolveRoute({required bool isManagerLike}) {
    final wk = workspaceKey;
    final sk = surveyId;
    final dk = doorId;
    if (wk != null && sk != null && moduleKey == 'remedial') {
      if (dk != null && dk.isNotEmpty) {
        if (isManagerLike) {
          return '/workspace/$wk/remedials/$sk/doors/$dk/review';
        }
        return '/workspace/$wk/remedials/$sk/doors/$dk';
      }
      return '/workspace/$wk/remedials/$sk/doors';
    }

    if (wk != null && sk != null && moduleKey == 'installation') {
      if (route.trim().contains('/installation/')) {
        return route;
      }
      return '/workspace/$wk/installation/$sk/items';
    }

    if (wk != null && sk != null && dk != null && moduleKey == 'snagging') {
      return '/workspace/$wk/inspection/projects/$sk/items/$dk';
    }

    return route;
  }
}

class HeaderNotificationSummary {
  final List<HeaderNotificationItem> items;

  const HeaderNotificationSummary(this.items);

  int get actionRequiredCount => items.where((n) => n.requiresAction && !n.isRead).length;
}

final headerNotificationSummaryProvider = Provider<HeaderNotificationSummary>((ref) {
  final auth = ref.watch(authControllerProvider);
  final role = auth.actualRole ?? auth.userRole ?? UserRole.worker;
  final isManagerLike = role != UserRole.worker;
  final settingsCtrl = ref.read(settingsControllerProvider.notifier);
  final fireDoorWorkerGroupId = isManagerLike
      ? null
      : settingsCtrl.workerGroupIdForWorkspace(workspaceKey: 'fire-door', userId: auth.uid);
  final fireStoppingWorkerGroupId = isManagerLike
      ? null
      : settingsCtrl.workerGroupIdForWorkspace(workspaceKey: 'fire-stopping', userId: auth.uid);

  final fireDoorSurveys =
      ref.watch(survey_state.surveyControllerFamilyProvider(survey_models.InspectionWorkspace.fireDoor)).surveys;
  final fireStoppingSurveys =
      ref.watch(survey_state.surveyControllerFamilyProvider(survey_models.InspectionWorkspace.fireStopping)).surveys;
  final snaggingProjects = ref.watch(snaggingModuleControllerProvider).projects;
  final remoteNotifications = ref.watch(workflowNotificationsProvider).valueOrNull ?? const [];

  final items = <HeaderNotificationItem>[
    ...remoteNotifications.map(
      (notification) => HeaderNotificationItem(
        title: notification.title,
        subtitle: notification.body,
        route: notification.routeTarget,
        requiresAction: notification.requiresAction,
        workspaceKey: notification.workspaceId,
        moduleKey: notification.module,
        surveyId: notification.projectId,
        doorId: notification.doorId.isNotEmpty ? notification.doorId : notification.itemId,
        notificationId: notification.id,
        isRead: notification.isRead,
        createdAt: notification.createdAt,
      ),
    ),
  ];

  if (kDebugMode) {
    debugPrint(
      'header_notifications role=${role.name} uid=${auth.uid} fdGroup=${fireDoorWorkerGroupId ?? ''} fsGroup=${fireStoppingWorkerGroupId ?? ''}',
    );
  }

  for (final survey in fireDoorSurveys) {
    if (!_workerCanAccessSurvey(
      isManagerLike: isManagerLike,
      workerGroupId: fireDoorWorkerGroupId,
      assignedGroupIds: survey.assignedGroupIds,
    )) {
      continue;
    }

    final projectLabel = _fdProjectLabel(survey);

    for (final door in survey.doors) {
      final hasRemedialTask = _hasWorkerRemedialTask(door);
      if (!hasRemedialTask) continue;

      final doorRef = door.doorIdTag.trim().isNotEmpty
          ? door.doorIdTag.trim()
          : 'D-${door.number.toString().padLeft(2, '0')}';
      if (isManagerLike && door.remedialStatus == survey_models.RemedialStatus.forApproval) {
        items.add(
          HeaderNotificationItem(
            title: 'Fire Door: $doorRef needs remedial approval',
            subtitle: projectLabel,
            route: '/workspace/fire-door/modules/remedials/projects',
            requiresAction: true,
            workspaceKey: 'fire-door',
            moduleKey: 'remedial',
            surveyId: survey.id,
            doorId: door.id,
          ),
        );
      }
      if (!isManagerLike && _workerDoorAction(door.remedialStatus)) {
        items.add(
          HeaderNotificationItem(
            title: 'Fire Door: $doorRef requires remedial update',
            subtitle: projectLabel,
            route: '/workspace/fire-door/modules/remedials/projects',
            requiresAction: true,
            workspaceKey: 'fire-door',
            moduleKey: 'remedial',
            surveyId: survey.id,
            doorId: door.id,
          ),
        );
      }
    }

    for (final item in survey.preInstallItems) {
      final opening = item.doorRef.trim().isNotEmpty ? item.doorRef.trim() : 'Opening';
      if (isManagerLike && item.status == survey_models.InstallationStatus.forApproval) {
        items.add(
          HeaderNotificationItem(
            title: 'Fire Door: $opening waiting for installation approval',
            subtitle: projectLabel,
            route: '/workspace/fire-door/modules/installation/projects',
            requiresAction: true,
            workspaceKey: 'fire-door',
            moduleKey: 'installation',
            surveyId: survey.id,
          ),
        );
      }
      if (!isManagerLike && _workerInstallAction(item.status)) {
        items.add(
          HeaderNotificationItem(
            title: 'Fire Door: $opening requires installation action',
            subtitle: projectLabel,
            route: '/workspace/fire-door/modules/installation/projects',
            requiresAction: true,
            workspaceKey: 'fire-door',
            moduleKey: 'installation',
            surveyId: survey.id,
          ),
        );
      }
    }
  }

  for (final survey in fireStoppingSurveys) {
    if (!_workerCanAccessSurvey(
      isManagerLike: isManagerLike,
      workerGroupId: fireStoppingWorkerGroupId,
      assignedGroupIds: survey.assignedGroupIds,
    )) {
      continue;
    }

    final projectLabel = _fsProjectLabel(survey);

    for (final door in survey.doors) {
      final hasRemedialTask = _hasWorkerRemedialTask(door);
      if (!hasRemedialTask) continue;

      final doorRef = door.doorIdTag.trim().isNotEmpty
          ? door.doorIdTag.trim()
          : 'Item-${door.number.toString().padLeft(2, '0')}';
      if (isManagerLike && door.remedialStatus == survey_models.RemedialStatus.forApproval) {
        items.add(
          HeaderNotificationItem(
            title: 'Fire Stopping: $doorRef needs remedial approval',
            subtitle: projectLabel,
            route: '/workspace/fire-stopping/modules/remedials/projects',
            requiresAction: true,
            workspaceKey: 'fire-stopping',
            moduleKey: 'remedial',
            surveyId: survey.id,
            doorId: door.id,
          ),
        );
      }
      if (!isManagerLike && _workerDoorAction(door.remedialStatus)) {
        items.add(
          HeaderNotificationItem(
            title: 'Fire Stopping: $doorRef requires remedial update',
            subtitle: projectLabel,
            route: '/workspace/fire-stopping/modules/remedials/projects',
            requiresAction: true,
            workspaceKey: 'fire-stopping',
            moduleKey: 'remedial',
            surveyId: survey.id,
            doorId: door.id,
          ),
        );
      }
    }

    for (final item in survey.preInstallItems) {
      final opening = item.doorRef.trim().isNotEmpty ? item.doorRef.trim() : 'Opening';
      if (isManagerLike && item.status == survey_models.InstallationStatus.forApproval) {
        items.add(
          HeaderNotificationItem(
            title: 'Fire Stopping: $opening waiting for installation approval',
            subtitle: projectLabel,
            route: '/workspace/fire-stopping/modules/installation/projects',
            requiresAction: true,
            workspaceKey: 'fire-stopping',
            moduleKey: 'installation',
            surveyId: survey.id,
          ),
        );
      }
      if (!isManagerLike && _workerInstallAction(item.status)) {
        items.add(
          HeaderNotificationItem(
            title: 'Fire Stopping: $opening requires installation action',
            subtitle: projectLabel,
            route: '/workspace/fire-stopping/modules/installation/projects',
            requiresAction: true,
            workspaceKey: 'fire-stopping',
            moduleKey: 'installation',
            surveyId: survey.id,
          ),
        );
      }
    }
  }

  final userName = auth.currentUser?.name.trim().toLowerCase() ?? '';
  for (final project in snaggingProjects) {
    final projectLabel = project.name.trim().isNotEmpty ? project.name.trim() : 'Snagging project';
    for (final issue in project.issues) {
      final assignedById = auth.uid.isNotEmpty && issue.assignedToUserId.trim() == auth.uid;
      final assignedByName = userName.isNotEmpty && issue.assignedToName.trim().toLowerCase() == userName;
      final isAssignedToWorker = assignedById || assignedByName;

      if (isManagerLike && issue.status == sg_models.SnaggingStatus.awaitingVerification) {
        items.add(
          HeaderNotificationItem(
            title: 'Snagging: issue awaiting verification',
            subtitle: projectLabel,
            route: '/workspace/snagging/verification/projects',
            requiresAction: true,
          ),
        );
      }

      if (!isManagerLike && isAssignedToWorker && _workerSnaggingAction(issue.status)) {
        items.add(
          HeaderNotificationItem(
            title: 'Snagging: assigned issue needs update',
            subtitle: projectLabel,
            route: '/workspace/snagging/inspection/projects/${project.id}/items',
            requiresAction: true,
            workspaceKey: 'snagging',
            moduleKey: 'snagging',
            surveyId: project.id,
            doorId: issue.id,
          ),
        );
      }
    }
  }

  final sortedItems = List<HeaderNotificationItem>.from(items);
  try {
    if (sortedItems.length > 1) {
      sortedItems.sort((a, b) {
        if (a.requiresAction != b.requiresAction) {
          return a.requiresAction ? -1 : 1;
        }
        final aCreated = a.createdAt;
        final bCreated = b.createdAt;
        if (aCreated != null && bCreated != null) {
          return bCreated.compareTo(aCreated);
        }
        return a.title.compareTo(b.title);
      });
    }
  } catch (e) {
    debugPrint('Sort error (header notifications): $e');
  }

  if (kDebugMode) {
    debugPrint('header_notifications result_count=${sortedItems.length} action_required=${sortedItems.where((n) => n.requiresAction).length}');
  }

  return HeaderNotificationSummary(sortedItems.take(24).toList());
});

bool _workerCanAccessSurvey({
  required bool isManagerLike,
  required String? workerGroupId,
  required List<String> assignedGroupIds,
}) {
  if (isManagerLike) return true;
  if (workerGroupId == null || workerGroupId.isEmpty) {
    return true;
  }
  return assignedGroupIds.isEmpty || assignedGroupIds.contains(workerGroupId);
}

bool _hasWorkerRemedialTask(survey_models.Door door) {
  if (door.replacementRequired) {
    return false;
  }
  if (door.remedialItems.any((i) => i.severity.toLowerCase() != 'advisory')) {
    return true;
  }
  if (door.issues.any(
    (i) =>
        i.severity == survey_models.IssueSeverity.fail ||
        i.severity == survey_models.IssueSeverity.criticalFail,
  )) {
    return true;
  }
  return door.result == survey_models.DoorResult.fail;
}

String _fdProjectLabel(survey_models.Survey survey) {
  final reportName = survey.reportName.trim();
  if (reportName.isNotEmpty) return reportName;
  final siteName = survey.siteName.trim();
  if (siteName.isNotEmpty) return siteName;
  final siteAddress = survey.siteAddress.trim();
  if (siteAddress.isNotEmpty) return siteAddress;
  return 'Fire Door project';
}

String _fsProjectLabel(survey_models.Survey survey) {
  final reportName = survey.reportName.trim();
  if (reportName.isNotEmpty) return reportName;
  final siteName = survey.siteName.trim();
  if (siteName.isNotEmpty) return siteName;
  final siteAddress = survey.siteAddress.trim();
  if (siteAddress.isNotEmpty) return siteAddress;
  return 'Fire Stopping project';
}

bool _workerDoorAction(survey_models.RemedialStatus status) {
  return status == survey_models.RemedialStatus.pending ||
      status == survey_models.RemedialStatus.inProgress ||
      status == survey_models.RemedialStatus.completedByWorker ||
      status == survey_models.RemedialStatus.rejectedNeedsRework;
}

bool _workerInstallAction(survey_models.InstallationStatus status) {
  return status == survey_models.InstallationStatus.pending ||
      status == survey_models.InstallationStatus.inProgress ||
      status == survey_models.InstallationStatus.completedByWorker ||
      status == survey_models.InstallationStatus.rejectedNeedsRework;
}

bool _workerSnaggingAction(sg_models.SnaggingStatus status) {
  return status == sg_models.SnaggingStatus.open ||
      status == sg_models.SnaggingStatus.returned;
}
