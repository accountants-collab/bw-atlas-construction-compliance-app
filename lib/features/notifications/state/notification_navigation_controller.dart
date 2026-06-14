import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationNavigationRequest {
  final String route;
  final String companyId;
  final String notificationId;

  const NotificationNavigationRequest({
    required this.route,
    required this.companyId,
    required this.notificationId,
  });
}

class NotificationNavigationController extends StateNotifier<NotificationNavigationRequest?> {
  NotificationNavigationController() : super(null);

  void setPending(NotificationNavigationRequest request) {
    state = request;
  }

  void clear() {
    state = null;
  }
}

final notificationNavigationControllerProvider =
    StateNotifierProvider<NotificationNavigationController, NotificationNavigationRequest?>(
  (ref) => NotificationNavigationController(),
);
