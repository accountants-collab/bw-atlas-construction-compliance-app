import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';

final userRoleProvider = Provider<UserRole?>((ref) {
  return ref.watch(authControllerProvider).userRole;
});

final currentUserRoleProvider = Provider<UserRole>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.actualRole ?? auth.userRole ?? UserRole.worker;
});

final usingMockRoleProvider = Provider<bool>((ref) {
  return false;
});
