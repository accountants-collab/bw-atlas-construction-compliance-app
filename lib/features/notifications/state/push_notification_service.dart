import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_state.dart';
import '../../settings/state/settings_controller.dart';
import '../data/workflow_notification_repository.dart';
import 'notification_navigation_controller.dart';

const _androidNotificationChannel = AndroidNotificationChannel(
  'workflow_updates',
  'Workflow updates',
  description: 'Actionable workflow notifications for assignments and approvals.',
  importance: Importance.high,
);

class PushNotificationService {
  PushNotificationService(this._ref)
      : _messaging = FirebaseMessaging.instance,
        _local = FlutterLocalNotificationsPlugin(),
        _repository = _ref.read(workflowNotificationRepositoryProvider);

  final Ref _ref;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _local;
  final WorkflowNotificationRepository _repository;

  bool _initialized = false;

  static String get _webVapidKey => const String.fromEnvironment('FCM_WEB_VAPID_KEY');

  Future<void> initializeForCurrentUser() async {
    if (_initialized) return;
    _initialized = true;

    await _initializeLocalNotifications();
    await _requestPermissions();
    await _syncCurrentToken();

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    _messaging.onTokenRefresh.listen(_syncRefreshedToken);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }
  }

  Future<void> unregisterCurrentUser() async {
    final auth = _ref.read(authControllerProvider);
    final companyId = auth.companyId;
    if (companyId == null || companyId.isEmpty) return;
    final token = await _currentToken();
    if (token == null || token.isEmpty) return;
    await _repository.unregisterDeviceToken(companyId: companyId, token: token);
    _initialized = false;
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings, iOS: DarwinInitializationSettings());
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final data = jsonDecode(payload) as Map<String, dynamic>;
        _routeFromPayload(data);
      },
    );
    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidNotificationChannel);
  }

  Future<void> _requestPermissions() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true, provisional: true);
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<String?> _currentToken() async {
    if (kIsWeb) {
      if (_webVapidKey.isEmpty) return null;
      return _messaging.getToken(vapidKey: _webVapidKey);
    }
    return _messaging.getToken();
  }

  Future<void> _syncCurrentToken() async {
    final token = await _currentToken();
    if (token == null || token.isEmpty) return;
    await _syncRefreshedToken(token);
  }

  Future<void> _syncRefreshedToken(String token) async {
    final auth = _ref.read(authControllerProvider);
    final companyId = auth.companyId;
    if (!auth.isLoggedIn || companyId == null || companyId.isEmpty) return;
    final role = (auth.actualRole ?? auth.userRole)?.name ?? 'worker';
    final workspaceId = _ref.read(settingsControllerProvider).activeWorkspaceKey;
    await _repository.registerDeviceToken(
      companyId: companyId,
      userId: auth.uid,
      role: role,
      token: token,
      platform: defaultTargetPlatform.name,
      workspaceId: workspaceId,
    );
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? (message.data['title'] as String? ?? 'Workflow update');
    final body = message.notification?.body ?? (message.data['body'] as String? ?? 'Open the app for details.');
    await _local.show(
      title.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'workflow_updates',
          'Workflow updates',
          channelDescription: 'Actionable workflow notifications for assignments and approvals.',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    _routeFromPayload(message.data);
  }

  void _routeFromPayload(Map<String, dynamic> data) {
    final route = (data['routeTarget'] as String? ?? '').trim();
    final companyId = (data['companyId'] as String? ?? _ref.read(authControllerProvider).companyId ?? '').trim();
    final notificationId = (data['notificationId'] as String? ?? '').trim();
    if (route.isEmpty || companyId.isEmpty) return;
    _ref.read(notificationNavigationControllerProvider.notifier).setPending(
          NotificationNavigationRequest(route: route, companyId: companyId, notificationId: notificationId),
        );
  }
}

final workflowNotificationRepositoryProvider = Provider<WorkflowNotificationRepository>((ref) {
  return WorkflowNotificationRepository();
});

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});
