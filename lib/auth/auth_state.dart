import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env/app_environment.dart';
import '../features/notifications/data/workflow_notification_repository.dart';
import '../features/settings/state/settings_controller.dart';
import 'auth_service.dart';
import 'quick_login_service.dart';
import 'auth_user.dart';

export 'auth_user.dart';

class AuthState {
  final AppUser? currentUser;
  final String? selectedCompanyId;
  final bool isLoading;
  final String? error;

  const AuthState({
    required this.currentUser,
    required this.selectedCompanyId,
    required this.isLoading,
    required this.error,
  });

  const AuthState.signedOut()
      : currentUser = null,
        selectedCompanyId = null,
        isLoading = false,
        error = null;

  bool get isLoggedIn => currentUser != null;
  bool get isSuperAdmin => currentUser?.role == UserRole.superAdmin;
  String get uid => currentUser?.id ?? '';
  String get email => currentUser?.email ?? '';
  String? get companyId =>
      isSuperAdmin ? selectedCompanyId : currentUser?.companyId;
  UserRole? get role => currentUser?.role;
  UserRole? get actualRole => currentUser?.role;
  UserRole? get userRole {
    final role = currentUser?.role;
    if (role == UserRole.owner) return UserRole.manager;
    if (role == UserRole.admin) return UserRole.manager;
    if (role == UserRole.superAdmin) return UserRole.manager;
    return role;
  }

  AuthState copyWith({
    AppUser? currentUser,
    String? selectedCompanyId,
    bool clearSelectedCompanyId = false,
    bool clearUser = false,
    bool? isLoading,
    String? error,
    bool errorToNull = false,
  }) {
    return AuthState(
      currentUser: clearUser ? null : (currentUser ?? this.currentUser),
      selectedCompanyId: clearSelectedCompanyId
          ? null
          : (selectedCompanyId ?? this.selectedCompanyId),
      isLoading: isLoading ?? this.isLoading,
      error: errorToNull ? null : (error ?? this.error),
    );
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final quickLoginServiceProvider = Provider<QuickLoginService>((ref) {
  return QuickLoginService();
});

final _authDataRevisionProvider = StateProvider<int>((ref) => 0);

final companyUsersProvider = FutureProvider<List<AppUser>>((ref) async {
  ref.watch(_authDataRevisionProvider);
  final auth = ref.watch(authControllerProvider);
  final companyId = auth.companyId;
  if (companyId == null || companyId.isEmpty) return const [];
  final service = ref.read(authServiceProvider);
  return service.listCompanyUsers(companyId);
});

final companyInvitesProvider = FutureProvider<List<InviteRecord>>((ref) async {
  ref.watch(_authDataRevisionProvider);
  final auth = ref.watch(authControllerProvider);
  final companyId = auth.companyId;
  if (companyId == null || companyId.isEmpty) return const [];
  final service = ref.read(authServiceProvider);
  return service.listCompanyInvites(companyId);
});

final companySeatSummaryProvider =
    FutureProvider<CompanySeatSummary?>((ref) async {
  ref.watch(_authDataRevisionProvider);
  final auth = ref.watch(authControllerProvider);
  final companyId = auth.companyId;
  if (companyId == null || companyId.isEmpty) return null;
  final service = ref.read(authServiceProvider);
  return service.getCompanySeatSummary(companyId);
});

final allCompaniesProvider =
    FutureProvider<List<CompanyWorkspace>>((ref) async {
  ref.watch(_authDataRevisionProvider);
  final auth = ref.watch(authControllerProvider);
  if (!auth.isSuperAdmin) return const [];
  final service = ref.read(authServiceProvider);
  return service.listAllCompanies();
});

final allUsersProvider = FutureProvider<List<AppUser>>((ref) async {
  ref.watch(_authDataRevisionProvider);
  final auth = ref.watch(authControllerProvider);
  if (!auth.isSuperAdmin) return const [];
  final service = ref.read(authServiceProvider);
  return service.listAllUsers();
});

class AuthController extends StateNotifier<AuthState> {
  final Ref _ref;

  AuthController(this._ref) : super(const AuthState.signedOut()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    state = state.copyWith(isLoading: true, errorToNull: true);
    final service = _ref.read(authServiceProvider);
    final user = await service.restoreSession();
    String? selectedCompanyId;
    if (user != null) {
      selectedCompanyId = await _resolveCompanyContext(user, service);
      await _syncWorkspaceContextByCompanyId(selectedCompanyId, service);
    }
    state = state.copyWith(
      currentUser: user,
      selectedCompanyId: selectedCompanyId,
      clearSelectedCompanyId: user == null,
      isLoading: false,
      errorToNull: true,
    );
  }

  Future<String?> _resolveCompanyContext(
      AppUser user, AuthService service) async {
    if (user.role != UserRole.superAdmin) return user.companyId;
    final companies = await service.listAllCompanies();
    if (companies.isEmpty) return null;

    final nonPlatform =
        companies.where((c) => c.companyId != user.companyId).toList();
    if (nonPlatform.isNotEmpty) return nonPlatform.first.companyId;
    return companies.first.companyId;
  }

  Future<void> _syncWorkspaceContextByCompanyId(
      String? companyId, AuthService service) async {
    if (companyId == null || companyId.isEmpty) return;
    final company = await service.getCompanyWorkspace(companyId);
    if (company == null) return;

    final settings = _ref.read(settingsControllerProvider.notifier);
    settings.syncCompanyFromAuth(
      companyId: company.companyId,
      companyName: company.companyName,
      tradingName: company.tradingName,
      address: company.address,
      email: company.email,
      phone: company.phone,
      seatLimit: company.seatLimit,
    );
  }

  Future<void> signIn(
      {required String email,
      required String password,
      required bool rememberMe}) async {
    final normalizedEmail = email.trim();
    final normalizedPassword = password.trim();
    if (normalizedEmail.isEmpty || normalizedPassword.isEmpty) {
      state = state.copyWith(
          error: 'Email and password are required.', isLoading: false);
      return;
    }

    state = state.copyWith(isLoading: true, errorToNull: true);
    final service = _ref.read(authServiceProvider);
    try {
      final user = await service.login(
        email: normalizedEmail,
        password: normalizedPassword,
        rememberMe: rememberMe,
      );
      if (user == null) {
        state = state.copyWith(
            isLoading: false, error: 'Incorrect email or password.');
        return;
      }
      String? selectedCompanyId;
      try {
        selectedCompanyId = await _resolveCompanyContext(user, service);
      } catch (e) {
        debugPrint('[AuthController] Company context resolution failed: $e');
        selectedCompanyId = user.companyId;
      }
      try {
        await _syncWorkspaceContextByCompanyId(selectedCompanyId, service);
      } catch (e) {
        debugPrint('[AuthController] Workspace sync failed after sign-in: $e');
      }
      state = state.copyWith(
        currentUser: user,
        selectedCompanyId: selectedCompanyId,
        isLoading: false,
        errorToNull: true,
      );
    } on AuthFailure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      debugPrint('[AuthController] Sign-in error: $e');
      state = state.copyWith(
          isLoading: false, error: 'Sign in failed. ${e.toString()}');
    }
  }

  Future<void> signInWithQuickLogin() async {
    state = state.copyWith(isLoading: true, errorToNull: true);
    final service = _ref.read(authServiceProvider);
    final quickLogin = _ref.read(quickLoginServiceProvider);

    try {
      final expectedUserId = await quickLogin.getLinkedUserId();
      final user = await service.restoreQuickLoginSession(
          expectedUserId: expectedUserId);
      if (user == null) {
        state = state.copyWith(
          isLoading: false,
          error:
              'Quick login is not available. Please sign in with email and password.',
        );
        return;
      }

      String? selectedCompanyId;
      try {
        selectedCompanyId = await _resolveCompanyContext(user, service);
      } catch (e) {
        debugPrint(
            '[AuthController] Quick login company context resolution failed: $e');
        selectedCompanyId = user.companyId;
      }

      try {
        await _syncWorkspaceContextByCompanyId(selectedCompanyId, service);
      } catch (e) {
        debugPrint('[AuthController] Quick login workspace sync failed: $e');
      }

      state = state.copyWith(
        currentUser: user,
        selectedCompanyId: selectedCompanyId,
        isLoading: false,
        errorToNull: true,
      );
    } on AuthFailure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      debugPrint('[AuthController] Quick login error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Quick login failed. Please sign in with email and password.',
      );
    }
  }

  Future<void> registerCompany({
    required String companyName,
    required String tradingName,
    required String address,
    required String adminFullName,
    required String adminEmail,
    required String password,
    required String confirmPassword,
    required String phone,
    required int seats,
  }) async {
    final normalizedEmail = adminEmail.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      state = state.copyWith(error: 'Email is required.', isLoading: false);
      return;
    }
    if (password != confirmPassword) {
      state = state.copyWith(
          error: 'Password and Confirm Password do not match.',
          isLoading: false);
      return;
    }

    state = state.copyWith(isLoading: true, errorToNull: true);
    final service = _ref.read(authServiceProvider);
    try {
      final result = await service.registerCompany(
        RegisterCompanyInput(
          companyName: companyName,
          tradingName: tradingName,
          address: address,
          adminFullName: adminFullName,
          adminEmail: normalizedEmail,
          password: password,
          phone: phone,
          seatLimit: seats,
        ),
      );
      await _syncWorkspaceContextByCompanyId(result.user.companyId, service);
      state = state.copyWith(
        currentUser: result.user,
        selectedCompanyId: result.user.companyId,
        isLoading: false,
        errorToNull: true,
      );
    } on AuthFailure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'Registration failed. Please try again.');
    }
  }

  Future<void> registerWithInvite({
    required String inviteCode,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorToNull: true);
    final service = _ref.read(authServiceProvider);
    try {
      final result = await service.acceptInvite(
        token: inviteCode,
        email: email,
        password: password,
      );
      await _syncWorkspaceContextByCompanyId(result.user.companyId, service);
      final acceptedInvite = result.acceptedInvite;
      if (acceptedInvite != null &&
          acceptedInvite.workspaceKey.trim().isNotEmpty &&
          acceptedInvite.targetGroupId.trim().isNotEmpty) {
        _ref.read(settingsControllerProvider.notifier).assignWorkerToGroup(
              workspaceKey: acceptedInvite.workspaceKey,
              userId: result.user.id,
              groupId: acceptedInvite.targetGroupId,
            );
      }
      state = state.copyWith(
        currentUser: result.user,
        selectedCompanyId: result.user.companyId,
        isLoading: false,
        errorToNull: true,
      );
      _ref.read(_authDataRevisionProvider.notifier).state++;
    } on AuthFailure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'Invitation acceptance failed.');
    }
  }

  Future<String> createInviteLink({
    required String invitedName,
    required String invitedEmail,
    required InviteRole role,
    String workspaceKey = '',
    String targetGroupId = '',
    String? appBaseUrl,
    Duration expiresIn = const Duration(days: 7),
  }) async {
    final actualRole = state.actualRole;
    if (actualRole != UserRole.manager &&
        actualRole != UserRole.admin &&
        actualRole != UserRole.owner &&
        actualRole != UserRole.superAdmin) {
      throw const AuthFailure('Only manager/admin can create invites.');
    }

    final companyId = state.companyId;
    if (companyId == null || companyId.isEmpty) {
      throw const AuthFailure('Company workspace is missing.');
    }

    final service = _ref.read(authServiceProvider);
    final invite = await service.createInvite(
      companyId: companyId,
      invitedName: invitedName,
      invitedEmail: invitedEmail,
      invitedRole: role,
      createdByUserId: state.uid,
      workspaceKey: workspaceKey,
      targetGroupId: targetGroupId,
      expiresIn: expiresIn,
    );

    _ref.read(_authDataRevisionProvider.notifier).state++;
    final webBase = '${Uri.base.origin}/#';
    final fallbackBase =
        kIsWeb && Uri.base.host != 'localhost' && Uri.base.host != '127.0.0.1'
            ? webBase
            : AppEnvironmentRuntime.current.inviteBaseUrl;
    final resolvedBase = appBaseUrl ?? fallbackBase;
    final normalizedBase = resolvedBase.endsWith('/')
        ? resolvedBase.substring(0, resolvedBase.length - 1)
        : resolvedBase;
    final encodedToken = Uri.encodeComponent(invite.token);
    return '$normalizedBase/invite/$encodedToken';
  }

  Future<void> revokeInvite(String inviteId) async {
    final actualRole = state.actualRole;
    if (actualRole != UserRole.manager &&
        actualRole != UserRole.admin &&
        actualRole != UserRole.owner &&
        actualRole != UserRole.superAdmin) {
      throw const AuthFailure('Only manager/admin can revoke invites.');
    }
    final companyId = state.companyId;
    if (companyId == null || companyId.isEmpty) {
      throw const AuthFailure('Company workspace is missing.');
    }
    final service = _ref.read(authServiceProvider);
    await service.revokeInvite(inviteId: inviteId, companyId: companyId);
    _ref.read(_authDataRevisionProvider.notifier).state++;
  }

  Future<void> setUserStatus({
    required String userId,
    required UserAccountStatus status,
  }) async {
    final actualRole = state.actualRole;
    if (actualRole != UserRole.manager &&
        actualRole != UserRole.admin &&
        actualRole != UserRole.owner &&
        actualRole != UserRole.superAdmin) {
      throw const AuthFailure('Only manager/admin can manage users.');
    }
    final companyId = state.companyId;
    if (companyId == null || companyId.isEmpty) {
      throw const AuthFailure('Company workspace is missing.');
    }

    final service = _ref.read(authServiceProvider);
    final updated = await service.setCompanyUserStatus(
      companyId: companyId,
      userId: userId,
      status: status,
    );

    if (state.uid == updated.id && !updated.isActive) {
      state =
          state.copyWith(clearUser: true, isLoading: false, errorToNull: true);
    }

    _ref.read(_authDataRevisionProvider.notifier).state++;
  }

  Future<InviteAcceptanceContext> getInviteContext(String token) {
    final service = _ref.read(authServiceProvider);
    return service.getInviteAcceptanceContext(token);
  }

  Future<void> acceptInviteToken({
    required String token,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    if (password != confirmPassword) {
      state = state.copyWith(
          error: 'Password and Confirm Password do not match.',
          isLoading: false);
      return;
    }

    state = state.copyWith(isLoading: true, errorToNull: true);
    final service = _ref.read(authServiceProvider);
    try {
      final result = await service.acceptInvite(
        token: token,
        email: email,
        password: password,
      );
      await _syncWorkspaceContextByCompanyId(result.user.companyId, service);
      state = state.copyWith(
        currentUser: result.user,
        selectedCompanyId: result.user.companyId,
        isLoading: false,
        errorToNull: true,
      );
      _ref.read(_authDataRevisionProvider.notifier).state++;
    } on AuthFailure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'Invitation acceptance failed.');
    }
  }

  Future<void> logout() async {
    final companyId = state.companyId;
    try {
      if (companyId != null && companyId.isNotEmpty) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await WorkflowNotificationRepository().unregisterDeviceToken(
            companyId: companyId,
            token: token,
          );
        }
      }
    } catch (_) {
      // Best effort token unregister; logout must still complete.
    }

    final service = _ref.read(authServiceProvider);
    final quickLogin = _ref.read(quickLoginServiceProvider);
    try {
      final preserveQuickLoginSession = await quickLogin.isQuickLoginEnabled();
      await service.logout(
        preserveQuickLoginSession: preserveQuickLoginSession,
      );
    } finally {
      state = state.copyWith(
        clearUser: true,
        clearSelectedCompanyId: true,
        errorToNull: true,
        isLoading: false,
      );
    }
  }

  Future<void> requestPasswordReset({required String email}) async {
    final service = _ref.read(authServiceProvider);
    await service.sendPasswordResetEmail(email: email);
  }

  Future<void> switchCompanyContext(String companyId) async {
    if (!state.isSuperAdmin) {
      throw const AuthFailure('Only super admin can switch company context.');
    }
    final targetCompanyId = companyId.trim();
    if (targetCompanyId.isEmpty) {
      throw const AuthFailure('Company workspace is missing.');
    }

    final service = _ref.read(authServiceProvider);
    final company = await service.getCompanyWorkspace(targetCompanyId);
    if (company == null || company.status != 'active') {
      throw const AuthFailure('Company workspace is not active.');
    }

    await _syncWorkspaceContextByCompanyId(company.companyId, service);
    state =
        state.copyWith(selectedCompanyId: company.companyId, errorToNull: true);
    _ref.read(_authDataRevisionProvider.notifier).state++;
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});
