import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import '../domain/workflow_notification.dart';

class WorkflowNotificationRepository {
  WorkflowNotificationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _notificationCollection(String companyId) {
    return _firestore.collection('companies').doc(companyId).collection('notifications');
  }

  CollectionReference<Map<String, dynamic>> _queueCollection(String companyId) {
    return _firestore.collection('companies').doc(companyId).collection('notificationQueue');
  }

  CollectionReference<Map<String, dynamic>> _deviceCollection(String companyId) {
    return _firestore.collection('companies').doc(companyId).collection('deviceTokens');
  }

  String deviceIdForToken(String token) {
    return sha1.convert(token.codeUnits).toString();
  }

  Stream<List<WorkflowNotification>> watchUserNotifications({
    required String companyId,
    required String userId,
  }) {
    return _notificationCollection(companyId)
        .where('recipientUserId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(24)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => WorkflowNotification.fromMap(doc.id, doc.data())).toList());
  }

  Future<void> markRead({
    required String companyId,
    required String notificationId,
  }) async {
    await _notificationCollection(companyId).doc(notificationId).set({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> registerDeviceToken({
    required String companyId,
    required String userId,
    required String role,
    required String token,
    required String platform,
    required String workspaceId,
  }) async {
    final deviceId = deviceIdForToken(token);
    await _deviceCollection(companyId).doc(deviceId).set({
      'companyId': companyId,
      'userId': userId,
      'role': role,
      'token': token,
      'platform': platform,
      'workspaceId': workspaceId,
      'lastUpdated': FieldValue.serverTimestamp(),
      'active': true,
    }, SetOptions(merge: true));
  }

  Future<void> unregisterDeviceToken({
    required String companyId,
    required String token,
  }) async {
    await _deviceCollection(companyId).doc(deviceIdForToken(token)).delete();
  }

  Future<void> publishNotifications({
    required String companyId,
    required List<WorkflowNotification> notifications,
  }) async {
    if (notifications.isEmpty) return;
    final batch = _firestore.batch();
    final queueRef = _queueCollection(companyId);
    final notificationRef = _notificationCollection(companyId);

    for (final notification in notifications) {
      final doc = notificationRef.doc();
      batch.set(doc, {
        ...notification.toMap(),
        'companyId': companyId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(queueRef.doc(), {
        'companyId': companyId,
        'notificationId': doc.id,
        'recipientUserId': notification.recipientUserId,
        'actorUserId': notification.actorUserId,
        'payload': {
          'companyId': companyId,
          'notificationId': doc.id,
          'workspaceId': notification.workspaceId,
          'module': notification.module,
          'projectId': notification.projectId,
          'taskId': notification.taskId,
          'itemId': notification.itemId,
          'doorId': notification.doorId,
          'routeTarget': notification.routeTarget,
          'status': notification.status,
          'notificationType': notification.notificationType,
          'title': notification.title,
          'body': notification.body,
          'requiresAction': notification.requiresAction.toString(),
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> listRecipientsByRole({
    required String companyId,
    required Set<String> roles,
  }) async {
    if (roles.isEmpty) return const [];
    final snapshot = await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('members')
        .where('role', whereIn: roles.toList())
        .get();
    return snapshot.docs.map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> listAllMembers({required String companyId}) async {
    final snapshot = await _firestore.collection('companies').doc(companyId).collection('members').get();
    return snapshot.docs.map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()}).toList();
  }
}
