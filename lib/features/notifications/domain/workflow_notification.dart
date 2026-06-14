class WorkflowNotification {
  final String id;
  final String companyId;
  final String recipientUserId;
  final String actorUserId;
  final String title;
  final String body;
  final String workspaceId;
  final String module;
  final String projectId;
  final String taskId;
  final String itemId;
  final String doorId;
  final String routeTarget;
  final String status;
  final String notificationType;
  final bool requiresAction;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? readAt;

  const WorkflowNotification({
    required this.id,
    required this.companyId,
    required this.recipientUserId,
    required this.actorUserId,
    required this.title,
    required this.body,
    required this.workspaceId,
    required this.module,
    required this.projectId,
    this.taskId = '',
    this.itemId = '',
    this.doorId = '',
    required this.routeTarget,
    required this.status,
    required this.notificationType,
    required this.requiresAction,
    required this.isRead,
    required this.createdAt,
    required this.readAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'companyId': companyId,
      'recipientUserId': recipientUserId,
      'actorUserId': actorUserId,
      'title': title,
      'body': body,
      'workspaceId': workspaceId,
      'module': module,
      'projectId': projectId,
      'taskId': taskId,
      'itemId': itemId,
      'doorId': doorId,
      'routeTarget': routeTarget,
      'status': status,
      'notificationType': notificationType,
      'requiresAction': requiresAction,
      'isRead': isRead,
      'createdAt': createdAt,
      'readAt': readAt,
    };
  }

  factory WorkflowNotification.fromMap(String id, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      try {
        return (raw as dynamic).toDate() as DateTime;
      } catch (_) {
        return null;
      }
    }

    return WorkflowNotification(
      id: id,
      companyId: map['companyId'] as String? ?? '',
      recipientUserId: map['recipientUserId'] as String? ?? '',
      actorUserId: map['actorUserId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      workspaceId: map['workspaceId'] as String? ?? '',
      module: map['module'] as String? ?? '',
      projectId: map['projectId'] as String? ?? '',
      taskId: map['taskId'] as String? ?? '',
      itemId: map['itemId'] as String? ?? '',
      doorId: map['doorId'] as String? ?? '',
      routeTarget: map['routeTarget'] as String? ?? '',
      status: map['status'] as String? ?? '',
      notificationType: map['notificationType'] as String? ?? '',
      requiresAction: map['requiresAction'] as bool? ?? true,
      isRead: map['isRead'] as bool? ?? false,
      createdAt: parseDate(map['createdAt']),
      readAt: parseDate(map['readAt']),
    );
  }
}
