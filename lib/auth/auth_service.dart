import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/env/app_environment.dart';
import 'quick_login_service.dart';
import 'auth_user.dart';

class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => message;
}

class CompanyWorkspace {
  final String companyId;
  final String companyName;
  final String tradingName;
  final String address;
  final String email;
  final String phone;
  final int seatLimit;
  final DateTime createdAt;
  final String status;

  const CompanyWorkspace({
    required this.companyId,
    required this.companyName,
    required this.tradingName,
    required this.address,
    required this.email,
    required this.phone,
    required this.seatLimit,
    required this.createdAt,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'companyId': companyId,
      'companyName': companyName,
      'tradingName': tradingName,
      'address': address,
      'email': email,
      'phone': phone,
      'seatLimit': seatLimit,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
    };
  }

  factory CompanyWorkspace.fromMap(Map<String, dynamic> map) {
    final createdAtRaw = map['createdAt'];
    DateTime createdAt;
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    } else {
      createdAt =
          DateTime.tryParse(createdAtRaw as String? ?? '') ?? DateTime.now();
    }
    return CompanyWorkspace(
      companyId: map['companyId'] as String? ?? '',
      companyName: map['companyName'] as String? ?? '',
      tradingName: map['tradingName'] as String? ?? '',
      address: map['address'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      seatLimit: (map['seatLimit'] as num?)?.toInt() ?? 1,
      createdAt: createdAt,
      status: map['status'] as String? ?? 'active',
    );
  }
}

class RegisterCompanyInput {
  final String companyName;
  final String tradingName;
  final String address;
  final String adminFullName;
  final String adminEmail;
  final String password;
  final String phone;
  final int seatLimit;

  const RegisterCompanyInput({
    required this.companyName,
    required this.tradingName,
    required this.address,
    required this.adminFullName,
    required this.adminEmail,
    required this.password,
    required this.phone,
    required this.seatLimit,
  });
}

class RegisterCompanyResult {
  final AppUser user;
  final CompanyWorkspace company;
  final InviteRecord? acceptedInvite;

  const RegisterCompanyResult({
    required this.user,
    required this.company,
    this.acceptedInvite,
  });
}

class CompanySeatSummary {
  final int seatLimit;
  final int activeUsers;
  final int availableSeats;

  const CompanySeatSummary({
    required this.seatLimit,
    required this.activeUsers,
    required this.availableSeats,
  });
}

enum InviteStatus { pending, accepted, expired, revoked }

enum InviteRole { admin, manager, worker }

class InviteRecord {
  final String inviteId;
  final String companyId;
  final String invitedName;
  final String invitedEmail;
  final InviteRole invitedRole;
  final String workspaceKey;
  final String targetGroupId;
  final String token;
  final String createdByUserId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final InviteStatus status;
  final DateTime? acceptedAt;

  const InviteRecord({
    required this.inviteId,
    required this.companyId,
    required this.invitedName,
    required this.invitedEmail,
    required this.invitedRole,
    this.workspaceKey = '',
    this.targetGroupId = '',
    required this.token,
    required this.createdByUserId,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.acceptedAt,
  });

  InviteRecord copyWith({InviteStatus? status, DateTime? acceptedAt}) {
    return InviteRecord(
      inviteId: inviteId,
      companyId: companyId,
      invitedName: invitedName,
      invitedEmail: invitedEmail,
      invitedRole: invitedRole,
      workspaceKey: workspaceKey,
      targetGroupId: targetGroupId,
      token: token,
      createdByUserId: createdByUserId,
      createdAt: createdAt,
      expiresAt: expiresAt,
      status: status ?? this.status,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'inviteId': inviteId,
      'companyId': companyId,
      'invitedName': invitedName,
      'invitedEmail': invitedEmail,
      'invitedRole': invitedRole.name,
      'workspaceKey': workspaceKey,
      'targetGroupId': targetGroupId,
      'token': token,
      'createdByUserId': createdByUserId,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'status': status.name,
      'acceptedAt': acceptedAt?.toIso8601String(),
    };
  }

  factory InviteRecord.fromMap(Map<String, dynamic> map) {
    return InviteRecord(
      inviteId: map['inviteId'] as String? ?? '',
      companyId: map['companyId'] as String? ?? '',
      invitedName: map['invitedName'] as String? ?? '',
      invitedEmail: map['invitedEmail'] as String? ?? '',
      invitedRole: InviteRole.values.firstWhere(
        (r) => r.name == (map['invitedRole'] as String? ?? ''),
        orElse: () => InviteRole.worker,
      ),
      workspaceKey: (map['workspaceKey'] as String? ?? '').trim(),
      targetGroupId: (map['targetGroupId'] as String? ?? '').trim(),
      token: map['token'] as String? ?? '',
      createdByUserId: map['createdByUserId'] as String? ?? '',
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse(map['expiresAt'] as String? ?? '') ??
          DateTime.now(),
      status: InviteStatus.values.firstWhere(
        (s) => s.name == (map['status'] as String? ?? ''),
        orElse: () => InviteStatus.pending,
      ),
      acceptedAt: DateTime.tryParse(map['acceptedAt'] as String? ?? ''),
    );
  }
}

class InviteAcceptanceContext {
  final InviteRecord invite;
  final CompanyWorkspace company;

  const InviteAcceptanceContext({required this.invite, required this.company});
}

class AuthService {
  static const _authBoxName = 'auth_session_box';
  static const _authSessionKey = 'current_user';
  static const _rememberMeKey = 'remember_me';
  static const _rememberedEmailKey = 'remembered_email';
  static const _authDataBoxName = 'auth_data_box';
  static const _usersKey = 'users_v1';
  static const _companiesKey = 'companies_v1';
  static const _invitesKey = 'invites_v1';
  // Removed internal email for public repository.
  static const _superAdminEmail = 'superadmin@example.com';
  static const _superAdminName = 'Platform Super Admin';
  static const _superAdminCompanyId = 'platform_super_admin';
  static const _superAdminPassword = String.fromEnvironment(
    'SUPER_ADMIN_PASSWORD',
    // Removed real default value for public repository.
    defaultValue: 'SUPER_ADMIN_PASSWORD_REMOVED',
  );
  static const _bootstrapOwnerPassword = String.fromEnvironment(
    'BOOTSTRAP_OWNER_PASSWORD',
    // Removed bootstrap local secret for public repository.
    defaultValue: 'BOOTSTRAP_OWNER_PASSWORD_REMOVED',
  );

  static const _uuid = Uuid();

  final FirebaseAuth? _firebaseAuth;
  final FirebaseFirestore? _firestore;

  AuthService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _firebaseAuth =
          firebaseAuth ??
          (Firebase.apps.isNotEmpty ? FirebaseAuth.instance : null),
      _firestore =
          firestore ??
          (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  bool get _hasFirebase => _firebaseAuth != null && _firestore != null;

  String get _namespacedAuthBoxName =>
      '${_authBoxName}_${AppEnvironmentRuntime.current.hiveNamespace}';
  String get _namespacedAuthDataBoxName =>
      '${_authDataBoxName}_${AppEnvironmentRuntime.current.hiveNamespace}';
  String get _legacyAuthBoxName => _authBoxName;
  String get _legacyAuthDataBoxName => _authDataBoxName;

  Future<Box> _authBox() async {
    final box = await Hive.openBox(_namespacedAuthBoxName);
    await _migrateLegacyBoxIfNeeded(
      targetBox: box,
      legacyBoxName: _legacyAuthBoxName,
      keys: const [_authSessionKey, _rememberMeKey, _rememberedEmailKey],
    );
    return box;
  }

  Future<Box> _dataBox() async {
    final box = await Hive.openBox(_namespacedAuthDataBoxName);
    await _migrateLegacyBoxIfNeeded(
      targetBox: box,
      legacyBoxName: _legacyAuthDataBoxName,
      keys: const [_usersKey, _companiesKey, _invitesKey],
    );
    return box;
  }

  Future<void> _migrateLegacyBoxIfNeeded({
    required Box targetBox,
    required String legacyBoxName,
    required List<String> keys,
  }) async {
    if (targetBox.name == legacyBoxName) return;

    final hasAnyTargetData = keys.any(targetBox.containsKey);
    if (hasAnyTargetData) return;

    try {
      final legacyBox = await Hive.openBox(legacyBoxName);
      var changed = false;

      for (final key in keys) {
        if (!legacyBox.containsKey(key)) continue;
        await targetBox.put(key, legacyBox.get(key));
        changed = true;
      }

      if (changed && AppEnvironmentRuntime.current.verboseLogging) {
        // ignore: avoid_print
        print(
          'AuthService migrated legacy Hive data from $legacyBoxName to ${targetBox.name}',
        );
      }
    } catch (_) {
      // Ignore migration failures and continue with clean namespaced storage.
    }
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  String _passwordHash({required String password, required String salt}) {
    return sha256.convert(utf8.encode('$password::$salt')).toString();
  }

  bool _isValidEmail(String email) {
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(email);
  }

  String _firebaseErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'This email is already registered. Please sign in or use another email.';
      case 'weak-password':
        return 'Password must be at least 6 characters long.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }

  UserRole _parseUserRole(String? rawRole) {
    final normalized = (rawRole ?? '').trim().toLowerCase();
    if (normalized == 'owner') return UserRole.owner;
    if (normalized == 'admin') return UserRole.admin;
    if (normalized == 'manager' || normalized == 'inspector') {
      return UserRole.manager;
    }
    if (normalized == 'superadmin' || normalized == 'super_admin') {
      return UserRole.superAdmin;
    }
    return UserRole.worker;
  }

  UserAccountStatus _parseUserStatus(Map<String, dynamic> data) {
    final raw = (data['status'] as String?)?.trim().toLowerCase();
    if (raw == 'inactive') return UserAccountStatus.inactive;
    if (raw == 'suspended') return UserAccountStatus.suspended;
    final active = data['active'];
    if (active is bool && !active) return UserAccountStatus.inactive;
    return UserAccountStatus.active;
  }

  DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  Future<CompanyWorkspace?> _getFirestoreCompany(String companyId) async {
    if (!_hasFirebase || companyId.trim().isEmpty) return null;
    final snap = await _firestore!.collection('companies').doc(companyId).get();
    final data = snap.data();
    if (data == null) return null;
    return CompanyWorkspace(
      companyId: snap.id,
      companyName: (data['companyName'] as String?)?.trim() ?? '',
      tradingName: (data['tradingName'] as String?)?.trim() ?? '',
      address: (data['address'] as String?)?.trim() ?? '',
      email: (data['email'] as String?)?.trim() ?? '',
      phone: (data['phone'] as String?)?.trim() ?? '',
      seatLimit: (data['seatLimit'] as num?)?.toInt() ?? 1,
      createdAt: _toDateTime(data['createdAt']),
      status: (data['status'] as String?)?.trim() ?? 'active',
    );
  }

  Future<AppUser?> _firebaseAppUserFromUid(String uid) async {
    if (!_hasFirebase || uid.trim().isEmpty) return null;
    final user = _firebaseAuth!.currentUser;
    if (user == null || user.uid != uid) return null;

    final tenantSnap = await _firestore!
        .collection('userTenants')
        .doc(uid)
        .get();
    final companyId = (tenantSnap.data()?['companyId'] as String?)?.trim();
    if (companyId == null || companyId.isEmpty) return null;

    final memberRef = _firestore!
        .collection('companies')
        .doc(companyId)
        .collection('members')
        .doc(uid);
    final memberSnap = await memberRef.get();
    final member = memberSnap.data();
    if (member == null) return null;

    final status = _parseUserStatus(member);
    if (status != UserAccountStatus.active) return null;

    final resolvedEmail = _normalizeEmail(
      user.email ?? (member['email'] as String? ?? ''),
    );
    var parsedRole = _parseUserRole(member['role'] as String?);

    // Targeted fix: the founding account for this platform always gets owner-level access.
    // If Firestore still holds 'manager' for this account (written by the old registerCompany
    // flow), upgrade it here at login time and self-heal the Firestore document.
    if (resolvedEmail == _normalizeEmail(_superAdminEmail)) {
      if (parsedRole != UserRole.owner && parsedRole != UserRole.superAdmin) {
        parsedRole = UserRole.owner;
        try {
          await memberRef.set({'role': 'owner'}, SetOptions(merge: true));
        } catch (_) {
          // Self-heal is best-effort; role override above is still applied in memory.
        }
      }
    }

    return AppUser(
      id: uid,
      name: ((member['name'] as String?)?.trim().isNotEmpty ?? false)
          ? (member['name'] as String).trim()
          : ((user.displayName?.trim().isNotEmpty ?? false)
                ? user.displayName!.trim()
                : 'User'),
      email: resolvedEmail,
      passwordHash: '',
      passwordSalt: '',
      role: parsedRole,
      companyId: companyId,
      status: status,
      isInternalAdmin: (member['isInternalAdmin'] as bool?) ?? false,
      createdAt: _toDateTime(member['createdAt']),
    );
  }

  AppUser _superAdminFallbackUser({
    required String uid,
    required String email,
    String? displayName,
  }) {
    return AppUser(
      id: uid,
      name: (displayName?.trim().isNotEmpty ?? false)
          ? displayName!.trim()
          : _superAdminName,
      email: _normalizeEmail(email),
      passwordHash: '',
      passwordSalt: '',
      role: UserRole.superAdmin,
      companyId: _superAdminCompanyId,
      status: UserAccountStatus.active,
      isInternalAdmin: true,
      createdAt: DateTime.now(),
    );
  }

  bool _countsTowardSeat(AppUser user) {
    if (user.isInternalAdmin || user.role == UserRole.superAdmin) return false;
    return user.status == UserAccountStatus.active;
  }

  int _activeSeatCountForCompany({
    required String companyId,
    required List<AppUser> users,
  }) {
    return users
        .where((u) => u.companyId == companyId && _countsTowardSeat(u))
        .length;
  }

  Future<List<AppUser>> _loadUsers() async {
    final box = await _dataBox();
    final raw = box.get(_usersKey);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => AppUser.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<List<CompanyWorkspace>> _loadCompanies() async {
    final box = await _dataBox();
    final raw = box.get(_companiesKey);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => CompanyWorkspace.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> _ensureSuperAdminExists({
    required List<AppUser> users,
    required List<CompanyWorkspace> companies,
  }) async {
    var companyList = [...companies];
    var userList = [...users];
    var changed = false;

    final hasSuperCompany = companyList.any(
      (c) => c.companyId == _superAdminCompanyId,
    );
    if (!hasSuperCompany) {
      companyList.add(
        CompanyWorkspace(
          companyId: _superAdminCompanyId,
          companyName: 'Platform Administration',
          tradingName: 'Platform Administration',
          address: '',
          email: _superAdminEmail,
          phone: '',
          seatLimit: 999999,
          createdAt: DateTime.now(),
          status: 'active',
        ),
      );
      changed = true;
    }

    final normalizedSuperEmail = _normalizeEmail(_superAdminEmail);
    final existingByEmail = userList
        .where((u) => _normalizeEmail(u.email) == normalizedSuperEmail)
        .toList();

    if (existingByEmail.isEmpty) {
      final salt = _uuid.v4();
      userList.add(
        AppUser(
          id: _uuid.v4(),
          name: _superAdminName,
          email: normalizedSuperEmail,
          passwordHash: _passwordHash(
            password: _superAdminPassword,
            salt: salt,
          ),
          passwordSalt: salt,
          role: UserRole.superAdmin,
          companyId: _superAdminCompanyId,
          status: UserAccountStatus.active,
          isInternalAdmin: true,
          createdAt: DateTime.now(),
        ),
      );
      changed = true;
    } else {
      final current = existingByEmail.first;
      if (current.role != UserRole.superAdmin || !current.isInternalAdmin) {
        final index = userList.indexWhere((u) => u.id == current.id);
        if (index != -1) {
          userList[index] = AppUser(
            id: current.id,
            name: current.name,
            email: current.email,
            passwordHash: current.passwordHash,
            passwordSalt: current.passwordSalt,
            role: UserRole.superAdmin,
            companyId: _superAdminCompanyId,
            status: UserAccountStatus.active,
            isInternalAdmin: true,
            createdAt: current.createdAt,
          );
          changed = true;
        }
      }
    }

    if (changed) {
      await _saveCompanies(companyList);
      await _saveUsers(userList);
    }
  }

  Future<void> _saveUsers(List<AppUser> users) async {
    final box = await _dataBox();
    await box.put(_usersKey, users.map((u) => u.toMap()).toList());
  }

  Future<void> _saveCompanies(List<CompanyWorkspace> companies) async {
    final box = await _dataBox();
    await box.put(_companiesKey, companies.map((c) => c.toMap()).toList());
  }

  Future<List<InviteRecord>> _loadInvites() async {
    final box = await _dataBox();
    final raw = box.get(_invitesKey);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => InviteRecord.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> _saveInvites(List<InviteRecord> invites) async {
    final box = await _dataBox();
    await box.put(_invitesKey, invites.map((i) => i.toMap()).toList());
  }

  InviteRecord _withEffectiveStatus(InviteRecord invite) {
    if (invite.status == InviteStatus.pending &&
        invite.expiresAt.isBefore(DateTime.now())) {
      return invite.copyWith(status: InviteStatus.expired);
    }
    return invite;
  }

  static const _inviteSecret = String.fromEnvironment(
    'INVITE_HMAC_SECRET',
    defaultValue: 'bw-staging-invite-key-2026',
  );

  String _buildEncodedToken({
    required String inviteId,
    required String companyId,
    required String companyName,
    required String invitedEmail,
    required String invitedName,
    required InviteRole invitedRole,
    String workspaceKey = '',
    String targetGroupId = '',
    required DateTime expiresAt,
    required DateTime createdAt,
  }) {
    final payloadMap = {
      'v': '1',
      'id': inviteId,
      'cid': companyId,
      'cname': companyName,
      'em': invitedEmail,
      'nm': invitedName,
      'rl': invitedRole.name,
      'wk': workspaceKey,
      'gid': targetGroupId,
      'exp': expiresAt.millisecondsSinceEpoch,
      'iat': createdAt.millisecondsSinceEpoch,
    };
    final payloadB64 = base64Url
        .encode(utf8.encode(jsonEncode(payloadMap)))
        .replaceAll('=', '');
    final hmac = Hmac(sha256, utf8.encode(_inviteSecret));
    final sig = hmac
        .convert(utf8.encode(payloadB64))
        .toString()
        .substring(0, 32);
    return 'v1.$payloadB64.$sig';
  }

  String _normalizeInviteTokenInput(String token) {
    var normalized = token.trim();
    if (normalized.isEmpty) return normalized;

    try {
      normalized = Uri.decodeComponent(normalized);
    } catch (_) {
      // Keep original token when decode fails.
    }

    normalized = normalized
        .replaceAll(RegExp(r'^[\s<>\(\)\[\]]+'), '')
        .replaceAll(RegExp(r'[\s<>\(\)\[\]]+$'), '')
        .replaceAll(RegExp(r'[\.,;:!?]+$'), '');
    return normalized;
  }

  InviteRecord? _tryDecodeToken(String token) {
    if (!token.startsWith('v1.')) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payloadB64 = parts[1];
    final sig = parts[2];
    final hmac = Hmac(sha256, utf8.encode(_inviteSecret));
    final expected = hmac
        .convert(utf8.encode(payloadB64))
        .toString()
        .substring(0, 32);
    if (sig != expected) return null;
    try {
      final raw = utf8.decode(
        base64Url.decode(base64Url.normalize(payloadB64)),
      );
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return InviteRecord(
        inviteId: m['id'] as String? ?? '',
        companyId: m['cid'] as String? ?? '',
        invitedName: m['nm'] as String? ?? '',
        invitedEmail: m['em'] as String? ?? '',
        invitedRole: InviteRole.values.firstWhere(
          (r) => r.name == (m['rl'] as String? ?? ''),
          orElse: () => InviteRole.worker,
        ),
        workspaceKey: (m['wk'] as String? ?? '').trim(),
        targetGroupId: (m['gid'] as String? ?? '').trim(),
        token: token,
        createdByUserId: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['iat'] as int? ?? 0),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(m['exp'] as int? ?? 0),
        status: InviteStatus.pending,
        acceptedAt: null,
      );
    } catch (_) {
      return null;
    }
  }

  String? _readCompanyNameFromToken(String token) {
    if (!token.startsWith('v1.')) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final raw = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m['cname'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<CompanyWorkspace?> getCompanyWorkspace(String companyId) async {
    if (_hasFirebase) {
      final company = await _getFirestoreCompany(companyId);
      if (company != null) return company;
    }
    await _ensureBootstrapData();
    final companies = await _loadCompanies();
    final found = companies.where((c) => c.companyId == companyId).toList();
    if (found.isEmpty) return null;
    return found.first;
  }

  Future<List<CompanyWorkspace>> listAllCompanies() async {
    if (_hasFirebase) {
      final snap = await _firestore!.collection('companies').get();
      final companies = snap.docs
          .map(
            (d) => CompanyWorkspace(
              companyId: d.id,
              companyName: (d.data()['companyName'] as String?)?.trim() ?? '',
              tradingName: (d.data()['tradingName'] as String?)?.trim() ?? '',
              address: (d.data()['address'] as String?)?.trim() ?? '',
              email: (d.data()['email'] as String?)?.trim() ?? '',
              phone: (d.data()['phone'] as String?)?.trim() ?? '',
              seatLimit: (d.data()['seatLimit'] as num?)?.toInt() ?? 1,
              createdAt: _toDateTime(d.data()['createdAt']),
              status: (d.data()['status'] as String?)?.trim() ?? 'active',
            ),
          )
          .toList();
      return _safeSortedCopy(
        companies,
        (a, b) =>
            a.companyName.toLowerCase().compareTo(b.companyName.toLowerCase()),
        context: 'listAllCompanies(firebase)',
      );
    }
    await _ensureBootstrapData();
    final companies = await _loadCompanies();
    return _safeSortedCopy(
      companies,
      (a, b) =>
          a.companyName.toLowerCase().compareTo(b.companyName.toLowerCase()),
      context: 'listAllCompanies(local)',
    );
  }

  List<T> _safeSortedCopy<T>(
    Iterable<T>? source,
    int Function(T a, T b) comparator, {
    String context = '',
  }) {
    final safeList = source == null ? <T>[] : List<T>.from(source);
    if (safeList.length < 2) return safeList;

    try {
      safeList.sort((a, b) {
        try {
          return comparator(a, b);
        } catch (_) {
          return a.toString().compareTo(b.toString());
        }
      });
    } catch (e) {
      // ignore: avoid_print
      print('Sort error${context.isEmpty ? '' : ' ($context)'}: $e');
    }
    return safeList;
  }

  Future<List<AppUser>> listAllUsers() async {
    if (_hasFirebase) {
      final snap = await _firestore!.collectionGroup('members').get();
      final users = <AppUser>[];
      for (final doc in snap.docs) {
        final companyRef = doc.reference.parent.parent;
        if (companyRef == null) continue;
        final data = doc.data();
        users.add(
          AppUser(
            id: doc.id,
            name: (data['name'] as String?)?.trim() ?? 'User',
            email: _normalizeEmail((data['email'] as String?) ?? ''),
            passwordHash: '',
            passwordSalt: '',
            role: _parseUserRole(data['role'] as String?),
            companyId: companyRef.id,
            status: _parseUserStatus(data),
            isInternalAdmin: (data['isInternalAdmin'] as bool?) ?? false,
            createdAt: _toDateTime(data['createdAt']),
          ),
        );
      }
      return _safeSortedCopy(
        users,
        (a, b) => b.createdAt.compareTo(a.createdAt),
        context: 'listAllUsers(firebase)',
      );
    }
    await _ensureBootstrapData();
    final users = await _loadUsers();
    return _safeSortedCopy(
      users,
      (a, b) => b.createdAt.compareTo(a.createdAt),
      context: 'listAllUsers(local)',
    );
  }

  Future<List<AppUser>> listCompanyUsers(String companyId) async {
    if (_hasFirebase) {
      final snap = await _firestore!
          .collection('companies')
          .doc(companyId)
          .collection('members')
          .get();
      final users = snap.docs.map((d) {
        final data = d.data();
        return AppUser(
          id: d.id,
          name: (data['name'] as String?)?.trim() ?? 'User',
          email: _normalizeEmail((data['email'] as String?) ?? ''),
          passwordHash: '',
          passwordSalt: '',
          role: _parseUserRole(data['role'] as String?),
          companyId: companyId,
          status: _parseUserStatus(data),
          isInternalAdmin: (data['isInternalAdmin'] as bool?) ?? false,
          createdAt: _toDateTime(data['createdAt']),
        );
      }).toList();
      return _safeSortedCopy(
        users,
        (a, b) => b.createdAt.compareTo(a.createdAt),
        context: 'listCompanyUsers(firebase)',
      );
    }
    await _ensureBootstrapData();
    final users = await _loadUsers();
    return _safeSortedCopy(
      users.where((u) => u.companyId == companyId),
      (a, b) => b.createdAt.compareTo(a.createdAt),
      context: 'listCompanyUsers(local)',
    );
  }

  Future<CompanySeatSummary> getCompanySeatSummary(String companyId) async {
    if (_hasFirebase) {
      final company = await _getFirestoreCompany(companyId);
      if (company == null) {
        throw const AuthFailure('Company workspace was not found.');
      }
      final users = await listCompanyUsers(companyId);
      final activeUsers = users.where(_countsTowardSeat).length;
      final availableSeats = (company.seatLimit - activeUsers).clamp(
        0,
        company.seatLimit,
      );
      return CompanySeatSummary(
        seatLimit: company.seatLimit,
        activeUsers: activeUsers,
        availableSeats: availableSeats,
      );
    }
    await _ensureBootstrapData();
    final company = await getCompanyWorkspace(companyId);
    if (company == null) {
      throw const AuthFailure('Company workspace was not found.');
    }
    final users = await _loadUsers();
    final activeUsers = _activeSeatCountForCompany(
      companyId: companyId,
      users: users,
    );
    final availableSeats = (company.seatLimit - activeUsers).clamp(
      0,
      company.seatLimit,
    );
    return CompanySeatSummary(
      seatLimit: company.seatLimit,
      activeUsers: activeUsers,
      availableSeats: availableSeats,
    );
  }

  Future<AppUser> setCompanyUserStatus({
    required String companyId,
    required String userId,
    required UserAccountStatus status,
  }) async {
    if (_hasFirebase) {
      final company = await _getFirestoreCompany(companyId);
      if (company == null || company.status != 'active') {
        throw const AuthFailure('Company workspace is not active.');
      }

      final memberRef = _firestore!
          .collection('companies')
          .doc(companyId)
          .collection('members')
          .doc(userId);
      final snap = await memberRef.get();
      final data = snap.data();
      if (data == null) {
        throw const AuthFailure('User not found.');
      }

      if ((data['isInternalAdmin'] as bool?) == true) {
        throw const AuthFailure('Internal accounts cannot be managed here.');
      }

      if (status == UserAccountStatus.active) {
        final users = await listCompanyUsers(companyId);
        final activeUsers = users.where(_countsTowardSeat).length;
        if (activeUsers >= company.seatLimit) {
          throw const AuthFailure(
            'No available seats. Increase seat limit or deactivate another user.',
          );
        }
      }

      final statusName = status.name;
      await memberRef.set({
        'active': status == UserAccountStatus.active,
        'status': statusName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return AppUser(
        id: userId,
        name: (data['name'] as String?)?.trim() ?? 'User',
        email: _normalizeEmail((data['email'] as String?) ?? ''),
        passwordHash: '',
        passwordSalt: '',
        role: _parseUserRole(data['role'] as String?),
        companyId: companyId,
        status: status,
        isInternalAdmin: (data['isInternalAdmin'] as bool?) ?? false,
        createdAt: _toDateTime(data['createdAt']),
      );
    }

    await _ensureBootstrapData();
    final users = await _loadUsers();
    final companies = await _loadCompanies();

    final company = companies.where((c) => c.companyId == companyId).toList();
    if (company.isEmpty || company.first.status != 'active') {
      throw const AuthFailure('Company workspace is not active.');
    }

    final index = users.indexWhere(
      (u) => u.id == userId && u.companyId == companyId,
    );
    if (index == -1) {
      throw const AuthFailure('User not found.');
    }

    final target = users[index];
    if (target.isInternalAdmin) {
      throw const AuthFailure('Internal accounts cannot be managed here.');
    }

    if (target.status == status) {
      return target;
    }

    if (status == UserAccountStatus.active) {
      final activeUsers = _activeSeatCountForCompany(
        companyId: companyId,
        users: users,
      );
      if (activeUsers >= company.first.seatLimit) {
        throw const AuthFailure(
          'No available seats. Increase seat limit or deactivate another user.',
        );
      }
    }

    final updated = AppUser(
      id: target.id,
      name: target.name,
      email: target.email,
      passwordHash: target.passwordHash,
      passwordSalt: target.passwordSalt,
      role: target.role,
      companyId: target.companyId,
      status: status,
      isInternalAdmin: target.isInternalAdmin,
      createdAt: target.createdAt,
    );

    users[index] = updated;
    await _saveUsers(users);

    final sessionBox = await _authBox();
    final rawSession = sessionBox.get(_authSessionKey);
    if (rawSession is Map) {
      final sessionUser = AppUser.fromMap(
        Map<String, dynamic>.from(rawSession),
      );
      if (sessionUser.id == updated.id) {
        if (updated.status == UserAccountStatus.active) {
          await sessionBox.put(_authSessionKey, updated.toMap());
        } else {
          await sessionBox.delete(_authSessionKey);
        }
      }
    }

    return updated;
  }

  Future<List<InviteRecord>> listCompanyInvites(String companyId) async {
    if (_hasFirebase) {
      final snap = await _firestore!
          .collection('invites')
          .where('companyId', isEqualTo: companyId)
          .orderBy('createdAt', descending: true)
          .get();

      final invites = snap.docs.map((doc) {
        final data = doc.data();
        return InviteRecord(
          inviteId: (data['inviteId'] as String?)?.trim().isNotEmpty == true
              ? (data['inviteId'] as String)
              : doc.id,
          companyId: (data['companyId'] as String?)?.trim() ?? '',
          invitedName: (data['invitedName'] as String?)?.trim() ?? '',
          invitedEmail: (data['invitedEmail'] as String?)?.trim() ?? '',
          invitedRole: InviteRole.values.firstWhere(
            (r) => r.name == (data['invitedRole'] as String? ?? ''),
            orElse: () => InviteRole.worker,
          ),
          workspaceKey: (data['workspaceKey'] as String? ?? '').trim(),
          targetGroupId: (data['targetGroupId'] as String? ?? '').trim(),
          token: (data['token'] as String?)?.trim() ?? '',
          createdByUserId: (data['createdByUserId'] as String?)?.trim() ?? '',
          createdAt: _toDateTime(data['createdAt']),
          expiresAt: _toDateTime(data['expiresAt']),
          status: InviteStatus.values.firstWhere(
            (s) => s.name == (data['status'] as String? ?? ''),
            orElse: () => InviteStatus.pending,
          ),
          acceptedAt: data['acceptedAt'] == null
              ? null
              : _toDateTime(data['acceptedAt']),
        );
      }).toList();

      return _safeSortedCopy(
        invites.map(_withEffectiveStatus),
        (a, b) => b.createdAt.compareTo(a.createdAt),
        context: 'listCompanyInvites(firebase)',
      );
    }

    await _ensureBootstrapData();
    final invites = await _loadInvites();
    final normalized = invites.map(_withEffectiveStatus).toList();
    if (!_equalInviteLists(invites, normalized)) {
      await _saveInvites(normalized);
    }
    return _safeSortedCopy(
      normalized.where((i) => i.companyId == companyId),
      (a, b) => b.createdAt.compareTo(a.createdAt),
      context: 'listCompanyInvites(local)',
    );
  }

  bool _equalInviteLists(List<InviteRecord> a, List<InviteRecord> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].status != b[i].status) return false;
    }
    return true;
  }

  Future<InviteRecord> createInvite({
    required String companyId,
    required String invitedName,
    required String invitedEmail,
    required InviteRole invitedRole,
    required String createdByUserId,
    String workspaceKey = '',
    String targetGroupId = '',
    Duration expiresIn = const Duration(days: 7),
  }) async {
    await _ensureBootstrapData();

    final name = invitedName.trim();
    final email = _normalizeEmail(invitedEmail);
    if (name.isEmpty) {
      throw const AuthFailure('Full Name is required.');
    }
    if (!_isValidEmail(email)) {
      throw const AuthFailure('Please enter a valid email.');
    }

    if (_hasFirebase) {
      final company = await _getFirestoreCompany(companyId);
      if (company == null || company.status != 'active') {
        throw const AuthFailure('Company workspace is not active.');
      }

      final existingMembers = await _firestore!
          .collection('companies')
          .doc(companyId)
          .collection('members')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (existingMembers.docs.isNotEmpty) {
        throw const AuthFailure(
          'This email already belongs to an existing account.',
        );
      }

      final pendingInvites = await _firestore!
          .collection('invites')
          .where('companyId', isEqualTo: companyId)
          .where('invitedEmail', isEqualTo: email)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (pendingInvites.docs.isNotEmpty) {
        throw const AuthFailure(
          'A pending invite already exists for this email.',
        );
      }

      final users = await listCompanyUsers(companyId);
      final activeUsers = users.where(_countsTowardSeat).length;
      if (activeUsers >= company.seatLimit) {
        throw const AuthFailure(
          'No available seats. Increase seat limit or deactivate an existing user.',
        );
      }

      final inviteId = _uuid.v4();
      final now = DateTime.now();
      final expiresAt = now.add(expiresIn);
      final normalizedWorkspaceKey = workspaceKey.trim();
      final normalizedTargetGroupId = targetGroupId.trim();
      final token = _buildEncodedToken(
        inviteId: inviteId,
        companyId: companyId,
        companyName: company.companyName,
        invitedEmail: email,
        invitedName: name,
        invitedRole: invitedRole,
        workspaceKey: normalizedWorkspaceKey,
        targetGroupId: normalizedTargetGroupId,
        expiresAt: expiresAt,
        createdAt: now,
      );

      final invite = InviteRecord(
        inviteId: inviteId,
        companyId: companyId,
        invitedName: name,
        invitedEmail: email,
        invitedRole: invitedRole,
        workspaceKey: normalizedWorkspaceKey,
        targetGroupId: normalizedTargetGroupId,
        token: token,
        createdByUserId: createdByUserId,
        createdAt: now,
        expiresAt: expiresAt,
        status: InviteStatus.pending,
        acceptedAt: null,
      );

      await _firestore!.collection('invites').doc(inviteId).set({
        'inviteId': inviteId,
        'companyId': companyId,
        'invitedName': name,
        'invitedEmail': email,
        'invitedRole': invitedRole.name,
        'workspaceKey': normalizedWorkspaceKey,
        'targetGroupId': normalizedTargetGroupId,
        'token': token,
        'createdByUserId': createdByUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'status': 'pending',
        'acceptedAt': null,
      });

      final hivedInvites = (await _loadInvites())
          .map(_withEffectiveStatus)
          .toList();
      await _saveInvites([...hivedInvites, invite]);
      return invite;
    }

    final companies = await _loadCompanies();
    final company = companies.where((c) => c.companyId == companyId).toList();
    if (company.isEmpty || company.first.status != 'active') {
      throw const AuthFailure('Company workspace is not active.');
    }

    final users = await _loadUsers();
    final invites = (await _loadInvites()).map(_withEffectiveStatus).toList();

    final existingUser = users
        .where((u) => _normalizeEmail(u.email) == email)
        .toList();
    if (existingUser.isNotEmpty) {
      throw const AuthFailure(
        'This email already belongs to an existing account.',
      );
    }

    final pendingSameEmail = invites
        .where(
          (i) =>
              i.status == InviteStatus.pending &&
              _normalizeEmail(i.invitedEmail) == email,
        )
        .toList();
    if (pendingSameEmail.isNotEmpty) {
      throw const AuthFailure(
        'A pending invite already exists for this email.',
      );
    }

    final activeUsers = _activeSeatCountForCompany(
      companyId: companyId,
      users: users,
    );
    final seatLimit = company.first.seatLimit;

    if (activeUsers >= seatLimit) {
      throw const AuthFailure(
        'No available seats. Increase seat limit or deactivate an existing user.',
      );
    }

    final inviteId = _uuid.v4();
    final now = DateTime.now();
    final expiresAt = now.add(expiresIn);
    final normalizedWorkspaceKey = workspaceKey.trim();
    final normalizedTargetGroupId = targetGroupId.trim();
    final token = _buildEncodedToken(
      inviteId: inviteId,
      companyId: companyId,
      companyName: company.first.companyName,
      invitedEmail: email,
      invitedName: name,
      invitedRole: invitedRole,
      workspaceKey: normalizedWorkspaceKey,
      targetGroupId: normalizedTargetGroupId,
      expiresAt: expiresAt,
      createdAt: now,
    );
    final invite = InviteRecord(
      inviteId: inviteId,
      companyId: companyId,
      invitedName: name,
      invitedEmail: email,
      invitedRole: invitedRole,
      workspaceKey: normalizedWorkspaceKey,
      targetGroupId: normalizedTargetGroupId,
      token: token,
      createdByUserId: createdByUserId,
      createdAt: now,
      expiresAt: expiresAt,
      status: InviteStatus.pending,
      acceptedAt: null,
    );

    await _saveInvites([...invites, invite]);
    return invite;
  }

  Future<void> revokeInvite({
    required String inviteId,
    required String companyId,
  }) async {
    if (_hasFirebase) {
      DocumentReference<Map<String, dynamic>>? inviteRef;

      final byDocId = await _firestore!
          .collection('invites')
          .doc(inviteId)
          .get();
      if (byDocId.exists) {
        final data = byDocId.data();
        if ((data?['companyId'] as String?)?.trim() == companyId) {
          inviteRef = byDocId.reference;
        }
      }

      if (inviteRef == null) {
        final query = await _firestore!
            .collection('invites')
            .where('companyId', isEqualTo: companyId)
            .where('inviteId', isEqualTo: inviteId)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          inviteRef = query.docs.first.reference;
        }
      }

      if (inviteRef == null) {
        throw const AuthFailure('Invite not found.');
      }

      final snap = await inviteRef.get();
      final data = snap.data();
      if (data == null) {
        throw const AuthFailure('Invite not found.');
      }

      final effective = _withEffectiveStatus(
        InviteRecord(
          inviteId: (data['inviteId'] as String?)?.trim().isNotEmpty == true
              ? (data['inviteId'] as String)
              : snap.id,
          companyId: (data['companyId'] as String?)?.trim() ?? '',
          invitedName: (data['invitedName'] as String?)?.trim() ?? '',
          invitedEmail: (data['invitedEmail'] as String?)?.trim() ?? '',
          invitedRole: InviteRole.values.firstWhere(
            (r) => r.name == (data['invitedRole'] as String? ?? ''),
            orElse: () => InviteRole.worker,
          ),
          workspaceKey: (data['workspaceKey'] as String? ?? '').trim(),
          targetGroupId: (data['targetGroupId'] as String? ?? '').trim(),
          token: (data['token'] as String?)?.trim() ?? '',
          createdByUserId: (data['createdByUserId'] as String?)?.trim() ?? '',
          createdAt: _toDateTime(data['createdAt']),
          expiresAt: _toDateTime(data['expiresAt']),
          status: InviteStatus.values.firstWhere(
            (s) => s.name == (data['status'] as String? ?? ''),
            orElse: () => InviteStatus.pending,
          ),
          acceptedAt: data['acceptedAt'] == null
              ? null
              : _toDateTime(data['acceptedAt']),
        ),
      );

      if (effective.status == InviteStatus.accepted) {
        throw const AuthFailure('Accepted invite cannot be revoked.');
      }

      await inviteRef.set({
        'status': InviteStatus.revoked.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return;
    }

    await _ensureBootstrapData();
    final invites = await _loadInvites();
    final index = invites.indexWhere(
      (i) => i.inviteId == inviteId && i.companyId == companyId,
    );
    if (index == -1) {
      throw const AuthFailure('Invite not found.');
    }

    final effective = _withEffectiveStatus(invites[index]);
    if (effective.status == InviteStatus.accepted) {
      throw const AuthFailure('Accepted invite cannot be revoked.');
    }

    invites[index] = effective.copyWith(status: InviteStatus.revoked);
    await _saveInvites(invites);
  }

  Future<InviteAcceptanceContext> getInviteAcceptanceContext(
    String token,
  ) async {
    final normalizedToken = _normalizeInviteTokenInput(token);

    if (_hasFirebase) {
      InviteRecord? fireInvite;
      try {
        final inviteSnap = await _firestore!
            .collection('invites')
            .where('token', isEqualTo: normalizedToken)
            .limit(1)
            .get();
        if (inviteSnap.docs.isNotEmpty) {
          final d = inviteSnap.docs.first.data();
          fireInvite = InviteRecord(
            inviteId: (d['inviteId'] as String?)?.trim().isNotEmpty == true
                ? (d['inviteId'] as String)
                : inviteSnap.docs.first.id,
            companyId: (d['companyId'] as String?)?.trim() ?? '',
            invitedName: (d['invitedName'] as String?)?.trim() ?? '',
            invitedEmail: (d['invitedEmail'] as String?)?.trim() ?? '',
            invitedRole: InviteRole.values.firstWhere(
              (r) => r.name == (d['invitedRole'] as String? ?? ''),
              orElse: () => InviteRole.worker,
            ),
            workspaceKey: (d['workspaceKey'] as String? ?? '').trim(),
            targetGroupId: (d['targetGroupId'] as String? ?? '').trim(),
            token: (d['token'] as String?)?.trim() ?? normalizedToken,
            createdByUserId: (d['createdByUserId'] as String?)?.trim() ?? '',
            createdAt: _toDateTime(d['createdAt']),
            expiresAt: _toDateTime(d['expiresAt']),
            status: InviteStatus.values.firstWhere(
              (s) => s.name == (d['status'] as String? ?? ''),
              orElse: () => InviteStatus.pending,
            ),
            acceptedAt: d['acceptedAt'] == null
                ? null
                : _toDateTime(d['acceptedAt']),
          );
        }
      } on FirebaseException {
        // Public invite links can still be validated from the signed token payload.
      }

      final invite = _withEffectiveStatus(
        fireInvite ??
            _tryDecodeToken(normalizedToken) ??
            (throw const AuthFailure('Invalid invite link.')),
      );

      if (invite.status == InviteStatus.expired) {
        throw const AuthFailure('Invitation expired.');
      }
      if (invite.status == InviteStatus.accepted) {
        throw const AuthFailure('Invitation already used.');
      }
      if (invite.status == InviteStatus.revoked) {
        throw const AuthFailure('Invalid invite link.');
      }

      CompanyWorkspace? company = await _getFirestoreCompany(invite.companyId);
      if (company == null) {
        final companyName =
            _readCompanyNameFromToken(normalizedToken) ?? invite.companyId;
        company = CompanyWorkspace(
          companyId: invite.companyId,
          companyName: companyName,
          tradingName: companyName,
          address: '',
          email: '',
          phone: '',
          seatLimit: 9999,
          createdAt: invite.createdAt,
          status: 'active',
        );
      } else if (company.status != 'active') {
        throw const AuthFailure('Company workspace is not active.');
      }

      return InviteAcceptanceContext(invite: invite, company: company);
    }

    await _ensureBootstrapData();
    final invites = await _loadInvites();
    final hivedMatch = invites
        .where((i) => i.token == normalizedToken)
        .toList();

    InviteRecord invite;
    if (hivedMatch.isNotEmpty) {
      invite = _withEffectiveStatus(hivedMatch.first);
    } else {
      final decoded = _tryDecodeToken(normalizedToken);
      if (decoded == null) throw const AuthFailure('Invalid invite link.');
      invite = _withEffectiveStatus(decoded);
    }

    if (invite.status == InviteStatus.expired) {
      if (hivedMatch.isNotEmpty) {
        await _saveInvites(
          invites
              .map((i) => i.inviteId == invite.inviteId ? invite : i)
              .toList(),
        );
      }
      throw const AuthFailure('Invitation expired.');
    }
    if (invite.status == InviteStatus.accepted) {
      throw const AuthFailure('Invitation already used.');
    }
    if (invite.status == InviteStatus.revoked) {
      throw const AuthFailure('Invalid invite link.');
    }

    CompanyWorkspace? company = await getCompanyWorkspace(invite.companyId);
    if (company == null) {
      final companyName =
          _readCompanyNameFromToken(normalizedToken) ?? invite.companyId;
      company = CompanyWorkspace(
        companyId: invite.companyId,
        companyName: companyName,
        tradingName: companyName,
        address: '',
        email: '',
        phone: '',
        seatLimit: 9999,
        createdAt: invite.createdAt,
        status: 'active',
      );
    } else if (company.status != 'active') {
      throw const AuthFailure('Company workspace is not active.');
    }

    return InviteAcceptanceContext(invite: invite, company: company);
  }

  Future<RegisterCompanyResult> acceptInvite({
    required String token,
    required String email,
    required String password,
  }) async {
    final normalizedToken = _normalizeInviteTokenInput(token);

    if (_hasFirebase) {
      final normalizedEmail = _normalizeEmail(email);
      if (password.trim().length < 6) {
        throw const AuthFailure('Password must be at least 6 characters long.');
      }

      final context = await getInviteAcceptanceContext(normalizedToken);
      final invite = context.invite;
      if (_normalizeEmail(invite.invitedEmail) != normalizedEmail) {
        throw const AuthFailure(
          'Invited email does not match this invitation.',
        );
      }

      final company = await _getFirestoreCompany(invite.companyId);
      if (company == null || company.status != 'active') {
        throw const AuthFailure('Company workspace is not active.');
      }

      UserCredential cred;
      var createdNewAccount = false;
      try {
        cred = await _firebaseAuth!.createUserWithEmailAndPassword(
          email: normalizedEmail,
          password: password.trim(),
        );
        createdNewAccount = true;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use' ||
            e.code == 'account-exists-with-different-credential') {
          try {
            cred = await _firebaseAuth!.signInWithEmailAndPassword(
              email: normalizedEmail,
              password: password.trim(),
            );
          } on FirebaseAuthException catch (signInError) {
            if (signInError.code == 'wrong-password' ||
                signInError.code == 'invalid-credential') {
              throw const AuthFailure(
                'This email already has an account. Use the existing password, or reset it with Forgot Password, then open the invite link again.',
              );
            }
            throw AuthFailure(_firebaseErrorMessage(signInError));
          }
        } else {
          throw AuthFailure(_firebaseErrorMessage(e));
        }
      }

      if (createdNewAccount) {
        try {
          await cred.user?.sendEmailVerification();
        } catch (_) {}
      }

      final uid = cred.user?.uid;
      if (uid == null) {
        throw const AuthFailure('Registration failed. Please try again.');
      }

      final tenantSnap = await _firestore!
          .collection('userTenants')
          .doc(uid)
          .get();
      final existingCompanyId =
          (tenantSnap.data()?['companyId'] as String?)?.trim() ?? '';
      if (existingCompanyId.isNotEmpty &&
          existingCompanyId != invite.companyId) {
        throw const AuthFailure(
          'This account is already linked to another company workspace. Please use a different email for this invite.',
        );
      }

      final existingMemberSnap = await _firestore!
          .collection('companies')
          .doc(invite.companyId)
          .collection('members')
          .doc(uid)
          .get();
      final alreadyMember = existingMemberSnap.exists;

      if (!alreadyMember) {
        final users = await listCompanyUsers(invite.companyId);
        final activeUsers = users.where(_countsTowardSeat).length;
        if (activeUsers >= company.seatLimit) {
          throw const AuthFailure(
            'No available seats. Increase seat limit or deactivate another user.',
          );
        }
      }

      final roleName = invite.invitedRole == InviteRole.admin
          ? 'admin'
          : invite.invitedRole == InviteRole.manager
          ? 'manager'
          : 'worker';
      final batch = _firestore!.batch();
      batch.set(_firestore!.collection('userTenants').doc(uid), {
        'companyId': invite.companyId,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(
        _firestore!
            .collection('companies')
            .doc(invite.companyId)
            .collection('members')
            .doc(uid),
        {
          'name': invite.invitedName,
          'email': normalizedEmail,
          'role': roleName,
          'active': true,
          'status': 'active',
          'isInternalAdmin': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();

      try {
        final inviteDocs = await _firestore!
            .collection('invites')
            .where('token', isEqualTo: normalizedToken)
            .limit(1)
            .get();
        if (inviteDocs.docs.isNotEmpty) {
          await inviteDocs.docs.first.reference.set({
            'status': 'accepted',
            'acceptedAt': FieldValue.serverTimestamp(),
            'acceptedByUid': uid,
          }, SetOptions(merge: true));
        }
      } on FirebaseException {
        // Invite status update is best-effort; account creation already succeeded.
      }

      final role = invite.invitedRole == InviteRole.admin
          ? UserRole.admin
          : invite.invitedRole == InviteRole.manager
          ? UserRole.manager
          : UserRole.worker;
      final acceptedInvite = invite.copyWith(
        status: InviteStatus.accepted,
        acceptedAt: DateTime.now(),
      );
      final user = AppUser(
        id: uid,
        name: invite.invitedName,
        email: normalizedEmail,
        passwordHash: '',
        passwordSalt: '',
        role: role,
        companyId: invite.companyId,
        status: UserAccountStatus.active,
        isInternalAdmin: false,
        createdAt: DateTime.now(),
      );

      final hivedUsers = await _loadUsers();
      await _saveUsers([...hivedUsers.where((u) => u.id != uid), user]);

      final sessionBox = await _authBox();
      await sessionBox.put(_rememberMeKey, true);
      await sessionBox.put(_rememberedEmailKey, normalizedEmail);
      await sessionBox.put(_authSessionKey, user.toMap());

      return RegisterCompanyResult(
        user: user,
        company: company,
        acceptedInvite: acceptedInvite,
      );
    }

    await _ensureBootstrapData();
    final normalizedEmail = _normalizeEmail(email);

    final invites = await _loadInvites();
    final index = invites.indexWhere((i) => i.token == normalizedToken);
    final isCrossDevice = index == -1;

    InviteRecord invite;
    if (!isCrossDevice) {
      invite = _withEffectiveStatus(invites[index]);
    } else {
      final decoded = _tryDecodeToken(normalizedToken);
      if (decoded == null) throw const AuthFailure('Invalid invite link.');
      invite = _withEffectiveStatus(decoded);
    }

    if (invite.status == InviteStatus.expired) {
      if (!isCrossDevice) {
        invites[index] = invite;
        await _saveInvites(invites);
      }
      throw const AuthFailure('Invitation expired.');
    }
    if (invite.status == InviteStatus.accepted) {
      throw const AuthFailure('Invitation already used.');
    }
    if (invite.status == InviteStatus.revoked) {
      throw const AuthFailure('Invalid invite link.');
    }
    if (_normalizeEmail(invite.invitedEmail) != normalizedEmail) {
      throw const AuthFailure('Invited email does not match this invitation.');
    }
    if (password.trim().length < 6) {
      throw const AuthFailure('Password must be at least 6 characters long.');
    }

    final users = await _loadUsers();
    var companies = await _loadCompanies();
    final companyMatches = companies
        .where((c) => c.companyId == invite.companyId)
        .toList();
    CompanyWorkspace company;
    if (companyMatches.isEmpty) {
      if (!isCrossDevice) {
        throw const AuthFailure('Company workspace is not active.');
      }
      final companyName =
          _readCompanyNameFromToken(normalizedToken) ?? invite.companyId;
      company = CompanyWorkspace(
        companyId: invite.companyId,
        companyName: companyName,
        tradingName: companyName,
        address: '',
        email: '',
        phone: '',
        seatLimit: 9999,
        createdAt: invite.createdAt,
        status: 'active',
      );
      companies = [...companies, company];
      await _saveCompanies(companies);
    } else {
      company = companyMatches.first;
      if (company.status != 'active') {
        throw const AuthFailure('Company workspace is not active.');
      }
    }

    final existingEmail = users
        .where((u) => _normalizeEmail(u.email) == normalizedEmail)
        .toList();
    if (existingEmail.isNotEmpty) {
      throw const AuthFailure('This email is already registered.');
    }

    if (!isCrossDevice) {
      final activeUsers = _activeSeatCountForCompany(
        companyId: invite.companyId,
        users: users,
      );
      if (activeUsers >= company.seatLimit) {
        throw const AuthFailure(
          'No available seats. Increase seat limit or deactivate another user.',
        );
      }
    }

    final role = invite.invitedRole == InviteRole.admin
        ? UserRole.admin
        : invite.invitedRole == InviteRole.manager
        ? UserRole.manager
        : UserRole.worker;
    final salt = _uuid.v4();
    final user = AppUser(
      id: _uuid.v4(),
      name: invite.invitedName,
      email: normalizedEmail,
      passwordHash: _passwordHash(password: password.trim(), salt: salt),
      passwordSalt: salt,
      role: role,
      companyId: invite.companyId,
      status: UserAccountStatus.active,
      isInternalAdmin: false,
      createdAt: DateTime.now(),
    );

    await _saveUsers([...users, user]);

    if (!isCrossDevice) {
      final accepted = invite.copyWith(
        status: InviteStatus.accepted,
        acceptedAt: DateTime.now(),
      );
      invites[index] = accepted;
      await _saveInvites(invites);
    }

    final sessionBox = await _authBox();
    await sessionBox.put(_rememberMeKey, true);
    await sessionBox.put(_rememberedEmailKey, normalizedEmail);
    await sessionBox.put(_authSessionKey, user.toMap());

    final acceptedInvite = invite.copyWith(
      status: InviteStatus.accepted,
      acceptedAt: DateTime.now(),
    );
    return RegisterCompanyResult(
      user: user,
      company: company,
      acceptedInvite: acceptedInvite,
    );
  }

  Future<void> _ensureBootstrapData() async {
    final users = await _loadUsers();
    final companies = await _loadCompanies();
    if (users.isNotEmpty || companies.isNotEmpty) {
      await _ensureSuperAdminExists(users: users, companies: companies);
      return;
    }

    final internalCompany = CompanyWorkspace(
      companyId: 'internal_owner_company',
      companyName: 'BW Atlas Internal',
      tradingName: 'BW Atlas Internal',
      address: '',
      email: 'internal@example.com',
      phone: '',
      seatLimit: 9999,
      createdAt: DateTime.now(),
      status: 'active',
    );

    final salt = _uuid.v4();
    final owner = AppUser(
      id: _uuid.v4(),
      name: 'Internal Owner',
      email: 'owner@example.com',
      passwordHash: _passwordHash(
        password: _bootstrapOwnerPassword,
        salt: salt,
      ),
      passwordSalt: salt,
      role: UserRole.owner,
      companyId: internalCompany.companyId,
      status: UserAccountStatus.active,
      isInternalAdmin: true,
      createdAt: DateTime.now(),
    );

    final bootstrapCompanies = [internalCompany];
    final bootstrapUsers = [owner];
    await _saveCompanies(bootstrapCompanies);
    await _saveUsers(bootstrapUsers);
    await _ensureSuperAdminExists(
      users: bootstrapUsers,
      companies: bootstrapCompanies,
    );
  }

  Future<AppUser?> restoreSession() async {
    if (_hasFirebase) {
      final box = await _authBox();
      final shouldRemember = box.get(_rememberMeKey) == true;
      if (!shouldRemember) {
        final quickLoginEnabled = await QuickLoginService()
            .isQuickLoginEnabled();
        if (!quickLoginEnabled) {
          await _firebaseAuth!.signOut();
        }
        return null;
      }

      final current = _firebaseAuth!.currentUser;
      if (current == null) return null;

      final appUser = await _firebaseAppUserFromUid(current.uid);
      if (appUser == null) {
        await _firebaseAuth!.signOut();
        await box.delete(_authSessionKey);
        return null;
      }

      await box.put(_authSessionKey, appUser.toMap());
      return appUser;
    }

    await _ensureBootstrapData();
    final box = await _authBox();
    final shouldRemember = box.get(_rememberMeKey) == true;
    if (!shouldRemember) {
      return null;
    }
    final raw = box.get(_authSessionKey);
    if (raw is! Map) return null;
    final sessionUser = AppUser.fromMap(Map<String, dynamic>.from(raw));

    final users = await _loadUsers();
    final companies = await _loadCompanies();

    final user = users.where((u) => u.id == sessionUser.id).toList();
    if (user.isEmpty) {
      await box.delete(_authSessionKey);
      return null;
    }

    final activeUser = user.first;
    if (!activeUser.isActive) {
      await box.delete(_authSessionKey);
      return null;
    }

    final company = companies
        .where((c) => c.companyId == activeUser.companyId)
        .toList();
    if (company.isEmpty || company.first.status != 'active') {
      await box.delete(_authSessionKey);
      return null;
    }

    return activeUser;
  }

  Future<AppUser?> restoreQuickLoginSession({String? expectedUserId}) async {
    if (!_hasFirebase) return null;

    final current = _firebaseAuth!.currentUser;
    if (current == null) return null;

    final expected = (expectedUserId ?? '').trim();
    if (expected.isNotEmpty && current.uid != expected) {
      return null;
    }

    final appUser = await _firebaseAppUserFromUid(current.uid);
    if (appUser == null) {
      return null;
    }

    if (appUser.role != UserRole.superAdmin) {
      final company = await _getFirestoreCompany(appUser.companyId);
      if (company == null || company.status != 'active') {
        return null;
      }
    }

    final box = await _authBox();
    await box.put(_rememberedEmailKey, appUser.email);
    await box.put(_rememberMeKey, false);

    return appUser;
  }

  Future<AppUser?> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    if (_hasFirebase) {
      final e = _normalizeEmail(email);
      final p = password.trim();
      if (e.isEmpty || p.isEmpty) {
        throw const AuthFailure('Email and password are required.');
      }

      UserCredential credential;
      try {
        credential = await _firebaseAuth!.signInWithEmailAndPassword(
          email: e,
          password: p,
        );
      } on FirebaseAuthException catch (authError) {
        throw AuthFailure(_firebaseErrorMessage(authError));
      }

      // Email verification gate is intentionally disabled for this app flow.

      final uid = credential.user?.uid;
      if (uid == null) {
        throw const AuthFailure('Sign in failed. Please try again.');
      }

      AppUser? appUser;
      try {
        appUser = await _firebaseAppUserFromUid(uid);
      } catch (e) {
        final signedInEmail = _normalizeEmail(
          credential.user?.email ?? e.toString(),
        );
        if (signedInEmail == _normalizeEmail(_superAdminEmail)) {
          appUser = _superAdminFallbackUser(
            uid: uid,
            email: signedInEmail,
            displayName: credential.user?.displayName,
          );
        } else {
          rethrow;
        }
      }

      if (appUser == null) {
        final signedInEmail = _normalizeEmail(credential.user?.email ?? e);
        if (signedInEmail == _normalizeEmail(_superAdminEmail)) {
          appUser = _superAdminFallbackUser(
            uid: uid,
            email: signedInEmail,
            displayName: credential.user?.displayName,
          );
        }
      }

      if (appUser == null) {
        await _firebaseAuth!.signOut();
        throw const AuthFailure(
          'No company profile found for this account. Please contact your administrator.',
        );
      }

      if (appUser.role != UserRole.superAdmin) {
        final company = await _getFirestoreCompany(appUser.companyId);
        if (company == null || company.status != 'active') {
          await _firebaseAuth!.signOut();
          throw const AuthFailure('This company workspace is not active.');
        }
      }

      final box = await _authBox();
      await box.put(_rememberMeKey, rememberMe);
      await box.put(_rememberedEmailKey, e);
      if (rememberMe) {
        await box.put(_authSessionKey, appUser.toMap());
      } else {
        await box.delete(_authSessionKey);
      }

      return appUser;
    }

    await _ensureBootstrapData();
    final e = _normalizeEmail(email);
    final p = password.trim();
    final users = await _loadUsers();
    final companies = await _loadCompanies();

    final found = users.where((u) => _normalizeEmail(u.email) == e).toList();
    if (found.isEmpty) {
      throw const AuthFailure('Account not found for this email.');
    }

    final user = found.first;
    if (user.status == UserAccountStatus.inactive) {
      throw const AuthFailure(
        'Your account is inactive. Please contact your company administrator.',
      );
    }
    if (user.status == UserAccountStatus.suspended) {
      throw const AuthFailure(
        'Your account is suspended. Please contact your company administrator.',
      );
    }

    final company = companies
        .where((c) => c.companyId == user.companyId)
        .toList();
    if (company.isEmpty) {
      throw const AuthFailure(
        'Company workspace was not found for this account.',
      );
    }
    if (company.first.status != 'active') {
      throw const AuthFailure('This company workspace is not active.');
    }

    final hash = _passwordHash(password: p, salt: user.passwordSalt);
    if (hash != user.passwordHash) {
      throw const AuthFailure('Incorrect email or password.');
    }

    final box = await _authBox();
    await box.put(_rememberMeKey, rememberMe);
    await box.put(_rememberedEmailKey, e);
    if (rememberMe) {
      await box.put(_authSessionKey, user.toMap());
    } else {
      await box.delete(_authSessionKey);
    }
    return user;
  }

  Future<RegisterCompanyResult> registerCompany(
    RegisterCompanyInput input,
  ) async {
    if (_hasFirebase) {
      final companyName = input.companyName.trim();
      final tradingName = input.tradingName.trim();
      final address = input.address.trim();
      final adminName = input.adminFullName.trim();
      final adminEmail = _normalizeEmail(input.adminEmail);
      final password = input.password.trim();
      final phone = input.phone.trim();
      final seatLimit = input.seatLimit;

      if (companyName.isEmpty) {
        throw const AuthFailure('Company name is required.');
      }
      if (adminName.isEmpty) {
        throw const AuthFailure('Admin / Manager full name is required.');
      }
      if (!_isValidEmail(adminEmail)) {
        throw const AuthFailure('Please enter a valid email address.');
      }
      if (password.length < 6) {
        throw const AuthFailure('Password must be at least 6 characters long.');
      }
      if (phone.isEmpty) throw const AuthFailure('Phone number is required.');
      if (seatLimit < 1) {
        throw const AuthFailure('Number of users / seats must be at least 1.');
      }

      UserCredential credential;
      try {
        credential = await _firebaseAuth!.createUserWithEmailAndPassword(
          email: adminEmail,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        throw AuthFailure(_firebaseErrorMessage(e));
      }

      try {
        await credential.user?.sendEmailVerification();
      } catch (_) {}

      final uid = credential.user?.uid;
      if (uid == null) {
        throw const AuthFailure('Registration failed. Please try again.');
      }

      final companyId = _uuid.v4();
      final companyRef = _firestore!.collection('companies').doc(companyId);
      final memberRef = companyRef.collection('members').doc(uid);
      final tenantRef = _firestore!.collection('userTenants').doc(uid);

      final batch = _firestore!.batch();
      batch.set(companyRef, {
        'companyId': companyId,
        'companyName': companyName,
        'tradingName': tradingName,
        'address': address,
        'email': adminEmail,
        'phone': phone,
        'seatLimit': seatLimit,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(memberRef, {
        'name': adminName,
        'email': adminEmail,
        'role': 'owner',
        'active': true,
        'status': 'active',
        'isInternalAdmin': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(tenantRef, {
        'companyId': companyId,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      final company = CompanyWorkspace(
        companyId: companyId,
        companyName: companyName,
        tradingName: tradingName,
        address: address,
        email: adminEmail,
        phone: phone,
        seatLimit: seatLimit,
        createdAt: DateTime.now(),
        status: 'active',
      );

      final user = AppUser(
        id: uid,
        name: adminName,
        email: adminEmail,
        passwordHash: '',
        passwordSalt: '',
        role: UserRole.owner,
        companyId: companyId,
        status: UserAccountStatus.active,
        isInternalAdmin: false,
        createdAt: DateTime.now(),
      );

      final sessionBox = await _authBox();
      await sessionBox.put(_rememberMeKey, true);
      await sessionBox.put(_rememberedEmailKey, adminEmail);
      await sessionBox.put(_authSessionKey, user.toMap());

      final companies = await _loadCompanies();
      final users = await _loadUsers();
      await _saveCompanies([
        ...companies.where((c) => c.companyId != companyId),
        company,
      ]);
      await _saveUsers([...users.where((u) => u.id != uid), user]);

      return RegisterCompanyResult(user: user, company: company);
    }

    await _ensureBootstrapData();

    final companyName = input.companyName.trim();
    final tradingName = input.tradingName.trim();
    final address = input.address.trim();
    final adminName = input.adminFullName.trim();
    final adminEmail = _normalizeEmail(input.adminEmail);
    final password = input.password.trim();
    final phone = input.phone.trim();
    final seatLimit = input.seatLimit;

    if (companyName.isEmpty) {
      throw const AuthFailure('Company name is required.');
    }
    if (adminName.isEmpty) {
      throw const AuthFailure('Admin / Manager full name is required.');
    }
    if (!_isValidEmail(adminEmail)) {
      throw const AuthFailure('Please enter a valid email address.');
    }
    if (password.length < 6) {
      throw const AuthFailure('Password must be at least 6 characters long.');
    }
    if (phone.isEmpty) {
      throw const AuthFailure('Phone number is required.');
    }
    if (seatLimit < 1) {
      throw const AuthFailure('Number of users / seats must be at least 1.');
    }

    final users = await _loadUsers();
    final companies = await _loadCompanies();

    final existingEmail = users
        .where((u) => _normalizeEmail(u.email) == adminEmail)
        .toList();
    if (existingEmail.isNotEmpty) {
      throw const AuthFailure(
        'This email is already registered. Please sign in or use another email.',
      );
    }

    final companyId = _uuid.v4();
    final company = CompanyWorkspace(
      companyId: companyId,
      companyName: companyName,
      tradingName: tradingName,
      address: address,
      email: adminEmail,
      phone: phone,
      seatLimit: seatLimit,
      createdAt: DateTime.now(),
      status: 'active',
    );

    final salt = _uuid.v4();
    final user = AppUser(
      id: _uuid.v4(),
      name: adminName,
      email: adminEmail,
      passwordHash: _passwordHash(password: password, salt: salt),
      passwordSalt: salt,
      role: UserRole.manager,
      companyId: companyId,
      status: UserAccountStatus.active,
      isInternalAdmin: false,
      createdAt: DateTime.now(),
    );

    await _saveCompanies([...companies, company]);
    await _saveUsers([...users, user]);

    final sessionBox = await _authBox();
    await sessionBox.put(_rememberMeKey, true);
    await sessionBox.put(_rememberedEmailKey, adminEmail);
    await sessionBox.put(_authSessionKey, user.toMap());

    return RegisterCompanyResult(user: user, company: company);
  }

  Future<void> logout({bool preserveQuickLoginSession = false}) async {
    if (_hasFirebase && !preserveQuickLoginSession) {
      await _firebaseAuth!.signOut();
    }
    final box = await _authBox();
    await box.put(_rememberMeKey, false);
    await box.delete(_rememberedEmailKey);
    await box.delete(_authSessionKey);
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    final normalized = _normalizeEmail(email);
    if (!_isValidEmail(normalized)) {
      throw const AuthFailure('Please enter a valid email address.');
    }
    if (!_hasFirebase) {
      throw const AuthFailure(
        'Password reset requires Firebase authentication to be configured.',
      );
    }
    try {
      await _firebaseAuth!.sendPasswordResetEmail(email: normalized);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_firebaseErrorMessage(e));
    }
  }

  Future<bool> isRememberMeEnabled() async {
    final box = await _authBox();
    return box.get(_rememberMeKey) == true;
  }

  Future<String> getRememberedEmail() async {
    final box = await _authBox();
    return (box.get(_rememberedEmailKey) as String? ?? '').trim();
  }
}
