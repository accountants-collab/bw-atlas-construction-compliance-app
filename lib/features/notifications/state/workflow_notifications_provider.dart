import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_state.dart';
import 'push_notification_service.dart';
import '../domain/workflow_notification.dart';

final workflowNotificationsProvider = StreamProvider<List<WorkflowNotification>>((ref) {
  final auth = ref.watch(authControllerProvider);
  final companyId = auth.companyId;
  if (!auth.isLoggedIn || companyId == null || companyId.isEmpty || auth.uid.isEmpty) {
    return const Stream<List<WorkflowNotification>>.empty();
  }
  return ref.read(workflowNotificationRepositoryProvider).watchUserNotifications(
        companyId: companyId,
        userId: auth.uid,
      );
});
