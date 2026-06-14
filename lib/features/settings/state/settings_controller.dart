import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../auth/auth_state.dart';
import '../../../core/env/app_environment.dart';
import '../domain/app_settings.dart';

const _uuid = Uuid();

bool hasCompletedCompanySetup(AppSettings settings, {String? workspaceKey}) {
  final key = workspaceKey?.trim();
  final profile = key == null || key.isEmpty
      ? settings.companyProfile
      : settings.workspaceCompanyProfiles[key] ?? settings.companyProfile;
  return settings.onboardingCompleted ||
      (profile.companyName.trim().isNotEmpty &&
          profile.email.trim().isNotEmpty &&
          profile.phone.trim().isNotEmpty &&
          (profile.address.trim().isNotEmpty ||
              profile.addressLine1.trim().isNotEmpty));
}

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._ref) : super(const AppSettings()) {
    _restore();
    _ref.listen<AuthState>(authControllerProvider, (prev, next) {
      final prevCid = prev?.companyId?.trim() ?? '';
      final nextCid = next.companyId?.trim() ?? '';
      if (prevCid == nextCid) return;
      if (nextCid.isEmpty) {
        _firestoreSubscription?.cancel();
        _firestoreSubscription = null;
        return;
      }
      _startFirestoreSync();
    });
  }

  final Ref _ref;

  static const _boxName = 'fd_settings_box';
  static const _stateKey = 'app_settings_v1';
  static const _sharedSettingsDocId = 'settings';

  String get _namespacedBoxName =>
      '${_boxName}_${AppEnvironmentRuntime.current.hiveNamespace}';

  bool _hydrating = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _firestoreSubscription;
  static const _knownWorkspaceKeys = <String>{
    'fire-door',
    'fire-stopping',
    'snagging'
  };

  String? get _resolvedCompanyId {
    try {
      final authCompanyId = _ref.read(authControllerProvider).companyId?.trim();
      if (authCompanyId != null && authCompanyId.isNotEmpty) {
        return authCompanyId;
      }
    } catch (_) {
      // Fall back to local state below.
    }
    final localCompanyId = state.activeCompanyId.trim();
    return localCompanyId.isEmpty ? null : localCompanyId;
  }

  DocumentReference<Map<String, dynamic>>? get _firestoreSharedSettingsDoc {
    final companyId = _resolvedCompanyId;
    if (companyId == null || companyId.isEmpty) return null;
    try {
      return FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('app')
          .doc(_sharedSettingsDocId);
    } catch (_) {
      return null;
    }
  }

  DocumentReference<Map<String, dynamic>>? get _firestoreCompanyDoc {
    final companyId = _resolvedCompanyId;
    if (companyId == null || companyId.isEmpty) return null;
    try {
      return FirebaseFirestore.instance.collection('companies').doc(companyId);
    } catch (_) {
      return null;
    }
  }

  String _normalizeWorkspaceKey(String raw) {
    final trimmed = raw.trim();
    if (_knownWorkspaceKeys.contains(trimmed)) return trimmed;
    return 'fire-door';
  }

  CompanyProfile _profileForWorkspace(AppSettings s, String workspaceKey) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    final p = s.workspaceCompanyProfiles[key];
    if (p != null) return p;
    return CompanyProfile(companyId: s.activeCompanyId);
  }

  ReportBrandingSettings _brandingForWorkspace(
      AppSettings s, String workspaceKey) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    return s.workspaceReportBranding[key] ?? const ReportBrandingSettings();
  }

  bool _onboardingForWorkspace(AppSettings s, String workspaceKey) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    return s.workspaceOnboardingCompleted[key] ?? false;
  }

  List<WorkspaceWorkerGroup> _groupsForWorkspace(
      AppSettings s, String workspaceKey) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    return s.workspaceGroups[key] ?? const [];
  }

  Map<String, String> _workerAssignmentsForWorkspace(
      AppSettings s, String workspaceKey) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    return s.workspaceWorkerGroupAssignments[key] ?? const {};
  }

  @override
  set state(AppSettings value) {
    super.state = value;
    if (!_hydrating) {
      _persist();
      unawaited(_syncSharedSettingsToFirestore());
    }
  }

  Future<void> _restore() async {
    try {
      final box = await Hive.openBox(_namespacedBoxName);
      final raw = box.get(_stateKey);
      if (raw is! String || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      _hydrating = true;
      state = _fromMap(decoded);
      _hydrating = false;
    } catch (_) {
      _hydrating = false;
    } finally {
      _startFirestoreSync();
    }
  }

  Future<void> _persist() async {
    try {
      final box = await Hive.openBox(_namespacedBoxName);
      await box.put(_stateKey, jsonEncode(_toMap(state)));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  void _startFirestoreSync() {
    final doc = _firestoreSharedSettingsDoc;
    if (doc == null) return;
    _firestoreSubscription?.cancel();
    _firestoreSubscription = doc.snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        final data = snapshot.data();
        if (data == null) {
          if (_hasMeaningfulSharedData(state)) {
            unawaited(_syncSharedSettingsToFirestore());
          }
          return;
        }
        _applyRemoteSharedSettings(data);
      },
      onError: (_) {},
    );
  }

  bool _hasMeaningfulSharedData(AppSettings settings) {
    if (settings.workspaceOnboardingCompleted.values.any((v) => v)) return true;
    if (settings.workspaceGroups.values.any((groups) => groups.isNotEmpty)) {
      return true;
    }
    if (settings.workspaceWorkerGroupAssignments.values
        .any((m) => m.isNotEmpty)) {
      return true;
    }
    if (settings.workspaceCompanyProfiles.values.any((p) =>
        p.companyName.trim().isNotEmpty ||
        p.tradingName.trim().isNotEmpty ||
        p.address.trim().isNotEmpty ||
        p.email.trim().isNotEmpty ||
        p.phone.trim().isNotEmpty)) {
      return true;
    }
    if (settings.workspaceReportBranding.values.any((b) =>
        b.reportHeader.trim().isNotEmpty ||
        b.reportFooter.trim().isNotEmpty ||
        b.reportLogoBytes.isNotEmpty)) {
      return true;
    }
    return false;
  }

  Map<String, dynamic> _sharedSettingsToMap(AppSettings settings) {
    final full = _toMap(settings);
    full.remove('teamUsers');
    full.remove('subscriptionPlan');
    full.remove('customSeatCount');
    full.remove('billing');
    full['updatedAt'] = FieldValue.serverTimestamp();
    return full;
  }

  Future<void> _syncSharedSettingsToFirestore() async {
    final doc = _firestoreSharedSettingsDoc;
    if (doc == null) return;
    try {
      final profile = state.companyProfile;
      final companyDoc = _firestoreCompanyDoc;
      if (companyDoc != null && profile.companyName.trim().isNotEmpty) {
        await companyDoc.set({
          'companyId': _resolvedCompanyId,
          'companyName': profile.companyName.trim(),
          'tradingName': profile.tradingName.trim(),
          'address': profile.address.trim(),
          'email': profile.email.trim(),
          'phone': profile.phone.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await doc.set(_sharedSettingsToMap(state), SetOptions(merge: true));
    } catch (_) {
      // Best-effort Firestore sync.
    }
  }

  void _applyRemoteSharedSettings(Map<String, dynamic> remote) {
    final merged = Map<String, dynamic>.from(_toMap(state));
    merged.addAll(remote);
    merged.remove('updatedAt');

    final next = _fromMap(merged);
    _hydrating = true;
    state = next.copyWith(
      activeWorkspaceKey: _normalizeWorkspaceKey(state.activeWorkspaceKey),
      companyProfile: _profileForWorkspace(
          next, _normalizeWorkspaceKey(state.activeWorkspaceKey)),
      reportBranding: _brandingForWorkspace(
          next, _normalizeWorkspaceKey(state.activeWorkspaceKey)),
      onboardingCompleted: _onboardingForWorkspace(
          next, _normalizeWorkspaceKey(state.activeWorkspaceKey)),
    );
    _hydrating = false;
    _persist();
  }

  Future<void> flushSharedSettingsNow() async {
    await _persist();
    await _syncSharedSettingsToFirestore();
  }

  void updateCompanyProfile({
    required String companyId,
    required String companyName,
    required String tradingName,
    required String address,
    String? addressLine1,
    String? addressLine2,
    String? cityTown,
    String? postCode,
    required String email,
    required String phone,
  }) {
    final line1 = (addressLine1 ?? '').trim();
    final line2 = (addressLine2 ?? '').trim();
    final city = (cityTown ?? '').trim();
    final post = (postCode ?? '').trim();
    final hasStructuredAddress = line1.isNotEmpty ||
        line2.isNotEmpty ||
        city.isNotEmpty ||
        post.isNotEmpty;
    final composedAddress = hasStructuredAddress
        ? _composeAddress(
            line1: line1, line2: line2, cityTown: city, postCode: post)
        : address.trim();

    state = state.copyWith(
      activeCompanyId:
          companyId.trim().isEmpty ? state.activeCompanyId : companyId.trim(),
      companyProfile: state.companyProfile.copyWith(
        companyId: companyId.trim().isEmpty
            ? state.companyProfile.companyId
            : companyId.trim(),
        companyName: companyName.trim(),
        tradingName: tradingName.trim(),
        address: composedAddress,
        addressLine1:
            hasStructuredAddress ? line1 : state.companyProfile.addressLine1,
        addressLine2:
            hasStructuredAddress ? line2 : state.companyProfile.addressLine2,
        cityTown: hasStructuredAddress ? city : state.companyProfile.cityTown,
        postCode: hasStructuredAddress ? post : state.companyProfile.postCode,
        email: email.trim(),
        phone: phone.trim(),
      ),
      workspaceCompanyProfiles: {
        ...state.workspaceCompanyProfiles,
        _normalizeWorkspaceKey(state.activeWorkspaceKey):
            state.companyProfile.copyWith(
          companyId: companyId.trim().isEmpty
              ? state.companyProfile.companyId
              : companyId.trim(),
          companyName: companyName.trim(),
          tradingName: tradingName.trim(),
          address: composedAddress,
          addressLine1:
              hasStructuredAddress ? line1 : state.companyProfile.addressLine1,
          addressLine2:
              hasStructuredAddress ? line2 : state.companyProfile.addressLine2,
          cityTown: hasStructuredAddress ? city : state.companyProfile.cityTown,
          postCode: hasStructuredAddress ? post : state.companyProfile.postCode,
          email: email.trim(),
          phone: phone.trim(),
        ),
      },
    );
  }

  void setActiveWorkspace(String workspaceKey) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    if (state.activeWorkspaceKey == key &&
        state.workspaceCompanyProfiles.containsKey(key)) {
      return;
    }
    state = state.copyWith(
      activeWorkspaceKey: key,
      companyProfile: _profileForWorkspace(state, key),
      reportBranding: _brandingForWorkspace(state, key),
      onboardingCompleted: _onboardingForWorkspace(state, key),
    );
  }

  void syncCompanyFromAuth({
    required String companyId,
    required String companyName,
    required String tradingName,
    required String address,
    required String email,
    required String phone,
    required int seatLimit,
  }) {
    final normalizedCompanyId = companyId.trim();
    final normalizedWorkspace =
        _normalizeWorkspaceKey(state.activeWorkspaceKey);
    final profiles = <String, CompanyProfile>{
      ...state.workspaceCompanyProfiles
    };

    final parsedAddress = _splitLegacyAddress(address);

    for (final key in _knownWorkspaceKeys) {
      final current =
          profiles[key] ?? CompanyProfile(companyId: normalizedCompanyId);
      profiles[key] = current.copyWith(
        companyId: normalizedCompanyId,
        companyName: current.companyName.trim().isNotEmpty
            ? current.companyName
            : companyName.trim(),
        tradingName: current.tradingName.trim().isNotEmpty
            ? current.tradingName
            : tradingName.trim(),
        address: current.address.trim().isNotEmpty
            ? current.address
            : address.trim(),
        addressLine1: current.addressLine1.trim().isNotEmpty
            ? current.addressLine1
            : parsedAddress.line1,
        addressLine2: current.addressLine2.trim().isNotEmpty
            ? current.addressLine2
            : parsedAddress.line2,
        cityTown: current.cityTown.trim().isNotEmpty
            ? current.cityTown
            : parsedAddress.cityTown,
        postCode: current.postCode.trim().isNotEmpty
            ? current.postCode
            : parsedAddress.postCode,
        email: current.email.trim().isNotEmpty ? current.email : email.trim(),
        phone: current.phone.trim().isNotEmpty ? current.phone : phone.trim(),
      );
    }

    final activeProfile = profiles[normalizedWorkspace] ??
        CompanyProfile(companyId: normalizedCompanyId);

    state = state.copyWith(
      activeCompanyId: normalizedCompanyId,
      customSeatCount: seatLimit < 1 ? 1 : seatLimit,
      workspaceCompanyProfiles: profiles,
      companyProfile: activeProfile,
    );
  }

  String _composeAddress({
    required String line1,
    required String line2,
    required String cityTown,
    required String postCode,
  }) {
    return [line1, line2, cityTown, postCode]
        .where((p) => p.trim().isNotEmpty)
        .join(', ');
  }

  ({String line1, String line2, String cityTown, String postCode})
      _splitLegacyAddress(String address) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return (
      line1: parts.isNotEmpty ? parts[0] : '',
      line2: parts.length > 1 ? parts[1] : '',
      cityTown: parts.length > 2 ? parts[2] : '',
      postCode: parts.length > 3 ? parts[3] : '',
    );
  }

  void setCompanyLogo(List<int> bytes) {
    state = state.copyWith(
      companyProfile: state.companyProfile.copyWith(logoBytes: bytes),
      workspaceCompanyProfiles: {
        ...state.workspaceCompanyProfiles,
        _normalizeWorkspaceKey(state.activeWorkspaceKey):
            state.companyProfile.copyWith(logoBytes: bytes),
      },
    );
  }

  void clearCompanyLogo() {
    state = state.copyWith(
      companyProfile: state.companyProfile.copyWith(logoBytes: const []),
      workspaceCompanyProfiles: {
        ...state.workspaceCompanyProfiles,
        _normalizeWorkspaceKey(state.activeWorkspaceKey):
            state.companyProfile.copyWith(logoBytes: const []),
      },
    );
  }

  void addTeamUser({
    required String name,
    required String email,
    required TeamUserRole role,
  }) {
    if (state.isAtSeatLimit) return;

    final user = TeamUser(
      id: _uuid.v4(),
      companyId: state.activeCompanyId,
      name: name.trim(),
      email: email.trim(),
      role: role,
      inviteStatus: InviteStatus.active,
    );
    state = state.copyWith(teamUsers: [...state.teamUsers, user]);
  }

  void removeTeamUser(String id) {
    state = state.copyWith(
      teamUsers: state.teamUsers.where((u) => u.id != id).toList(),
    );
  }

  void setTeamUserActive({
    required String id,
    required bool isActive,
  }) {
    if (isActive && state.isAtSeatLimit) return;
    state = state.copyWith(
      teamUsers: state.teamUsers
          .map((u) => u.id == id
              ? u.copyWith(
                  isActive: isActive,
                  inviteStatus:
                      isActive ? InviteStatus.active : InviteStatus.disabled,
                )
              : u)
          .toList(),
    );
  }

  void setTeamUserInviteStatus({
    required String id,
    required InviteStatus status,
  }) {
    if (status == InviteStatus.active && state.isAtSeatLimit) return;
    state = state.copyWith(
      teamUsers: state.teamUsers
          .map((u) => u.id == id
              ? u.copyWith(
                  inviteStatus: status,
                  isActive: status == InviteStatus.active,
                )
              : u)
          .toList(),
    );
  }

  void updateTeamUserRole({
    required String id,
    required TeamUserRole role,
  }) {
    state = state.copyWith(
      teamUsers: state.teamUsers
          .map((u) => u.id == id ? u.copyWith(role: role) : u)
          .toList(),
    );
  }

  void setSubscriptionPlan(SubscriptionPlan plan) {
    state = state.copyWith(subscriptionPlan: plan);
  }

  void setCustomSeatCount(int count) {
    final n = count < 1 ? 1 : count;
    state = state.copyWith(customSeatCount: n);
  }

  void clearCustomSeatCount() {
    state = state.copyWith(customSeatCount: 0);
  }

  void updateBillingSettings({
    String? stripeCustomerId,
    String? stripeSubscriptionId,
    String? stripePriceId,
  }) {
    state = state.copyWith(
      billing: state.billing.copyWith(
        stripeCustomerId: stripeCustomerId,
        stripeSubscriptionId: stripeSubscriptionId,
        stripePriceId: stripePriceId,
      ),
    );
  }

  void updateReportBranding({
    required String reportHeader,
    required String reportFooter,
    required String pdfFileNameFormat,
    required bool useCompanyBrandingOnPdf,
  }) {
    final format = pdfFileNameFormat.trim().isEmpty
        ? '{company}_{type}_{report}_{date}'
        : pdfFileNameFormat.trim();

    state = state.copyWith(
      reportBranding: state.reportBranding.copyWith(
        reportHeader: reportHeader.trim(),
        reportFooter: reportFooter.trim(),
        pdfFileNameFormat: format,
        useCompanyBrandingOnPdf: useCompanyBrandingOnPdf,
      ),
      workspaceReportBranding: {
        ...state.workspaceReportBranding,
        _normalizeWorkspaceKey(state.activeWorkspaceKey):
            state.reportBranding.copyWith(
          reportHeader: reportHeader.trim(),
          reportFooter: reportFooter.trim(),
          pdfFileNameFormat: format,
          useCompanyBrandingOnPdf: useCompanyBrandingOnPdf,
        ),
      },
    );
  }

  void setReportLogo(List<int> bytes) {
    state = state.copyWith(
      reportBranding: state.reportBranding.copyWith(reportLogoBytes: bytes),
      workspaceReportBranding: {
        ...state.workspaceReportBranding,
        _normalizeWorkspaceKey(state.activeWorkspaceKey):
            state.reportBranding.copyWith(reportLogoBytes: bytes),
      },
    );
  }

  void clearReportLogo() {
    state = state.copyWith(
      reportBranding: state.reportBranding.copyWith(reportLogoBytes: const []),
      workspaceReportBranding: {
        ...state.workspaceReportBranding,
        _normalizeWorkspaceKey(state.activeWorkspaceKey):
            state.reportBranding.copyWith(reportLogoBytes: const []),
      },
    );
  }

  void completeOnboarding() {
    state = state.copyWith(
      onboardingCompleted: true,
      workspaceOnboardingCompleted: {
        ...state.workspaceOnboardingCompleted,
        'fire-door': true,
        'fire-stopping': true,
        'snagging': true,
      },
    );
  }

  void resetOnboarding() {
    state = state.copyWith(
      onboardingCompleted: false,
      workspaceOnboardingCompleted: {
        ...state.workspaceOnboardingCompleted,
        _normalizeWorkspaceKey(state.activeWorkspaceKey): false,
      },
    );
  }

  void createWorkspaceGroup({
    required String workspaceKey,
    required String name,
  }) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final groups = [..._groupsForWorkspace(state, key)];
    final exists =
        groups.any((g) => g.name.trim().toLowerCase() == trimmed.toLowerCase());
    if (exists) return;

    groups.add(
      WorkspaceWorkerGroup(
        id: _uuid.v4(),
        name: trimmed,
        createdAt: DateTime.now(),
      ),
    );

    state = state.copyWith(
      workspaceGroups: {
        ...state.workspaceGroups,
        key: groups,
      },
    );
  }

  void renameWorkspaceGroup({
    required String workspaceKey,
    required String groupId,
    required String name,
  }) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final groups = _groupsForWorkspace(state, key)
        .map((g) => g.id == groupId ? g.copyWith(name: trimmed) : g)
        .toList();

    state = state.copyWith(
      workspaceGroups: {
        ...state.workspaceGroups,
        key: groups,
      },
    );
  }

  void deleteWorkspaceGroup({
    required String workspaceKey,
    required String groupId,
  }) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    final groups =
        _groupsForWorkspace(state, key).where((g) => g.id != groupId).toList();

    final assignments = {..._workerAssignmentsForWorkspace(state, key)};
    assignments.removeWhere((_, assignedGroupId) => assignedGroupId == groupId);

    state = state.copyWith(
      workspaceGroups: {
        ...state.workspaceGroups,
        key: groups,
      },
      workspaceWorkerGroupAssignments: {
        ...state.workspaceWorkerGroupAssignments,
        key: assignments,
      },
    );
  }

  void assignWorkerToGroup({
    required String workspaceKey,
    required String userId,
    String? groupId,
  }) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;

    final assignments = {..._workerAssignmentsForWorkspace(state, key)};
    final nextGroupId = groupId?.trim() ?? '';
    if (nextGroupId.isEmpty) {
      assignments.remove(normalizedUserId);
    } else {
      assignments[normalizedUserId] = nextGroupId;
    }

    state = state.copyWith(
      workspaceWorkerGroupAssignments: {
        ...state.workspaceWorkerGroupAssignments,
        key: assignments,
      },
    );
  }

  String? workerGroupIdForWorkspace({
    required String workspaceKey,
    required String userId,
  }) {
    final key = _normalizeWorkspaceKey(workspaceKey);
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return null;
    return _workerAssignmentsForWorkspace(state, key)[normalizedUserId];
  }

  AppSettings _fromMap(Map<String, dynamic> m) {
    final company = m['companyProfile'] is Map
        ? Map<String, dynamic>.from(m['companyProfile'] as Map)
        : <String, dynamic>{};

    final branding = m['reportBranding'] is Map
        ? Map<String, dynamic>.from(m['reportBranding'] as Map)
        : <String, dynamic>{};

    final billing = m['billing'] is Map
        ? Map<String, dynamic>.from(m['billing'] as Map)
        : <String, dynamic>{};

    final team = (m['teamUsers'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(
          (u) => TeamUser(
            id: u['id'] as String? ?? _uuid.v4(),
            companyId: u['companyId'] as String? ??
                (m['activeCompanyId'] as String? ?? ''),
            name: u['name'] as String? ?? '',
            email: u['email'] as String? ?? '',
            role: TeamUserRole.values.firstWhere(
              (r) => r.name == (u['role'] as String? ?? ''),
              orElse: () => TeamUserRole.inspector,
            ),
            isActive: u['isActive'] as bool? ?? true,
            inviteStatus: InviteStatus.values.firstWhere(
              (s) => s.name == (u['inviteStatus'] as String? ?? ''),
              orElse: () => (u['isActive'] as bool? ?? true)
                  ? InviteStatus.active
                  : InviteStatus.disabled,
            ),
          ),
        )
        .toList();

    final companyId = company['companyId'] as String? ??
        m['activeCompanyId'] as String? ??
        '';

    final activeWorkspaceKey = _normalizeWorkspaceKey(
        m['activeWorkspaceKey'] as String? ?? 'fire-door');
    final workspaceProfilesRaw = m['workspaceCompanyProfiles'] is Map
        ? Map<String, dynamic>.from(m['workspaceCompanyProfiles'] as Map)
        : <String, dynamic>{};
    final workspaceBrandingRaw = m['workspaceReportBranding'] is Map
        ? Map<String, dynamic>.from(m['workspaceReportBranding'] as Map)
        : <String, dynamic>{};
    final workspaceOnboardingRaw = m['workspaceOnboardingCompleted'] is Map
        ? Map<String, dynamic>.from(m['workspaceOnboardingCompleted'] as Map)
        : <String, dynamic>{};
    final workspaceGroupsRaw = m['workspaceGroups'] is Map
        ? Map<String, dynamic>.from(m['workspaceGroups'] as Map)
        : <String, dynamic>{};
    final workspaceWorkerAssignmentsRaw = m['workspaceWorkerGroupAssignments']
            is Map
        ? Map<String, dynamic>.from(m['workspaceWorkerGroupAssignments'] as Map)
        : <String, dynamic>{};

    CompanyProfile parseProfile(
        Map<String, dynamic> raw, String fallbackCompanyId) {
      final legacyAddr = raw['address'] as String? ?? '';
      final split = _splitLegacyAddress(legacyAddr);
      final p1 = (raw['addressLine1'] as String? ?? split.line1).trim();
      final p2 = (raw['addressLine2'] as String? ?? split.line2).trim();
      final city = (raw['cityTown'] as String? ?? split.cityTown).trim();
      final post = (raw['postCode'] as String? ?? split.postCode).trim();
      return CompanyProfile(
        companyId: (raw['companyId'] as String? ?? fallbackCompanyId).trim(),
        companyName: raw['companyName'] as String? ?? '',
        tradingName: raw['tradingName'] as String? ?? '',
        address: _composeAddress(
            line1: p1, line2: p2, cityTown: city, postCode: post),
        addressLine1: p1,
        addressLine2: p2,
        cityTown: city,
        postCode: post,
        email: raw['email'] as String? ?? '',
        phone: raw['phone'] as String? ?? '',
        logoBytes: (raw['logoBytes'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
      );
    }

    ReportBrandingSettings parseBranding(Map<String, dynamic> raw) {
      return ReportBrandingSettings(
        reportHeader: raw['reportHeader'] as String? ?? '',
        reportFooter: raw['reportFooter'] as String? ?? '',
        pdfFileNameFormat: raw['pdfFileNameFormat'] as String? ??
            '{company}_{type}_{report}_{date}',
        useCompanyBrandingOnPdf:
            raw['useCompanyBrandingOnPdf'] as bool? ?? true,
        reportLogoBytes: (raw['reportLogoBytes'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
      );
    }

    final parsedWorkspaceProfiles = <String, CompanyProfile>{};
    for (final entry in workspaceProfilesRaw.entries) {
      final key = _normalizeWorkspaceKey(entry.key);
      if (entry.value is! Map) continue;
      parsedWorkspaceProfiles[key] = parseProfile(
        Map<String, dynamic>.from(entry.value as Map),
        companyId,
      );
    }

    final parsedWorkspaceBranding = <String, ReportBrandingSettings>{};
    for (final entry in workspaceBrandingRaw.entries) {
      final key = _normalizeWorkspaceKey(entry.key);
      if (entry.value is! Map) continue;
      parsedWorkspaceBranding[key] =
          parseBranding(Map<String, dynamic>.from(entry.value as Map));
    }

    final parsedWorkspaceOnboarding = <String, bool>{};
    for (final entry in workspaceOnboardingRaw.entries) {
      final key = _normalizeWorkspaceKey(entry.key);
      parsedWorkspaceOnboarding[key] = entry.value == true;
    }

    final parsedWorkspaceGroups = <String, List<WorkspaceWorkerGroup>>{};
    for (final entry in workspaceGroupsRaw.entries) {
      final key = _normalizeWorkspaceKey(entry.key);
      if (entry.value is! List) continue;
      final groups = (entry.value as List)
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map(
            (g) => WorkspaceWorkerGroup(
              id: (g['id'] as String? ?? _uuid.v4()).trim(),
              name: (g['name'] as String? ?? '').trim(),
              createdAt: DateTime.tryParse(g['createdAt'] as String? ?? '') ??
                  DateTime.now(),
            ),
          )
          .where((g) => g.name.isNotEmpty)
          .toList();
      parsedWorkspaceGroups[key] = groups;
    }

    final parsedWorkerAssignments = <String, Map<String, String>>{};
    for (final entry in workspaceWorkerAssignmentsRaw.entries) {
      final key = _normalizeWorkspaceKey(entry.key);
      if (entry.value is! Map) continue;
      final assignments = <String, String>{};
      for (final assignEntry in (entry.value as Map).entries) {
        final userId = (assignEntry.key as String? ?? '').trim();
        final groupId = (assignEntry.value as String? ?? '').trim();
        if (userId.isEmpty || groupId.isEmpty) continue;
        assignments[userId] = groupId;
      }
      parsedWorkerAssignments[key] = assignments;
    }

    final legacyProfile = parseProfile(company, companyId);
    final legacyBranding = parseBranding(branding);
    final legacyOnboarding = m['onboardingCompleted'] as bool? ?? false;

    if (parsedWorkspaceProfiles.isEmpty && legacyOnboarding) {
      parsedWorkspaceProfiles['fire-door'] = legacyProfile;
    }
    if (parsedWorkspaceBranding.isEmpty) {
      parsedWorkspaceBranding['fire-door'] = legacyBranding;
    }
    if (parsedWorkspaceOnboarding.isEmpty) {
      parsedWorkspaceOnboarding['fire-door'] = legacyOnboarding;
    }

    final activeProfile = parsedWorkspaceProfiles[activeWorkspaceKey] ??
        CompanyProfile(companyId: companyId);
    final activeBranding = parsedWorkspaceBranding[activeWorkspaceKey] ??
        const ReportBrandingSettings();
    final activeOnboarding =
        parsedWorkspaceOnboarding[activeWorkspaceKey] ?? false;

    return AppSettings(
      activeCompanyId: companyId,
      activeWorkspaceKey: activeWorkspaceKey,
      workspaceCompanyProfiles: parsedWorkspaceProfiles,
      workspaceReportBranding: parsedWorkspaceBranding,
      workspaceOnboardingCompleted: parsedWorkspaceOnboarding,
      workspaceGroups: parsedWorkspaceGroups,
      workspaceWorkerGroupAssignments: parsedWorkerAssignments,
      companyProfile: activeProfile,
      teamUsers: team,
      subscriptionPlan: SubscriptionPlan.values.firstWhere(
        (p) => p.name == (m['subscriptionPlan'] as String? ?? ''),
        orElse: () => SubscriptionPlan.users5,
      ),
      customSeatCount: (m['customSeatCount'] as num?)?.toInt() ?? 0,
      billing: BillingSettings(
        stripeCustomerId: billing['stripeCustomerId'] as String? ?? '',
        stripeSubscriptionId: billing['stripeSubscriptionId'] as String? ?? '',
        stripePriceId: billing['stripePriceId'] as String? ?? '',
      ),
      reportBranding: activeBranding,
      onboardingCompleted: activeOnboarding,
    );
  }

  Map<String, dynamic> _toMap(AppSettings s) {
    return {
      'activeCompanyId': s.activeCompanyId,
      'activeWorkspaceKey': s.activeWorkspaceKey,
      'companyProfile': {
        'companyId': s.companyProfile.companyId,
        'companyName': s.companyProfile.companyName,
        'tradingName': s.companyProfile.tradingName,
        'address': s.companyProfile.address,
        'addressLine1': s.companyProfile.addressLine1,
        'addressLine2': s.companyProfile.addressLine2,
        'cityTown': s.companyProfile.cityTown,
        'postCode': s.companyProfile.postCode,
        'email': s.companyProfile.email,
        'phone': s.companyProfile.phone,
        'logoBytes': s.companyProfile.logoBytes,
      },
      'workspaceCompanyProfiles': {
        for (final entry in s.workspaceCompanyProfiles.entries)
          entry.key: {
            'companyId': entry.value.companyId,
            'companyName': entry.value.companyName,
            'tradingName': entry.value.tradingName,
            'address': entry.value.address,
            'addressLine1': entry.value.addressLine1,
            'addressLine2': entry.value.addressLine2,
            'cityTown': entry.value.cityTown,
            'postCode': entry.value.postCode,
            'email': entry.value.email,
            'phone': entry.value.phone,
            'logoBytes': entry.value.logoBytes,
          },
      },
      'teamUsers': s.teamUsers
          .map(
            (u) => {
              'id': u.id,
              'companyId': u.companyId,
              'name': u.name,
              'email': u.email,
              'role': u.role.name,
              'isActive': u.isActive,
              'inviteStatus': u.inviteStatus.name,
            },
          )
          .toList(),
      'subscriptionPlan': s.subscriptionPlan.name,
      'customSeatCount': s.customSeatCount,
      'billing': {
        'stripeCustomerId': s.billing.stripeCustomerId,
        'stripeSubscriptionId': s.billing.stripeSubscriptionId,
        'stripePriceId': s.billing.stripePriceId,
      },
      'reportBranding': {
        'reportHeader': s.reportBranding.reportHeader,
        'reportFooter': s.reportBranding.reportFooter,
        'pdfFileNameFormat': s.reportBranding.pdfFileNameFormat,
        'useCompanyBrandingOnPdf': s.reportBranding.useCompanyBrandingOnPdf,
        'reportLogoBytes': s.reportBranding.reportLogoBytes,
      },
      'workspaceReportBranding': {
        for (final entry in s.workspaceReportBranding.entries)
          entry.key: {
            'reportHeader': entry.value.reportHeader,
            'reportFooter': entry.value.reportFooter,
            'pdfFileNameFormat': entry.value.pdfFileNameFormat,
            'useCompanyBrandingOnPdf': entry.value.useCompanyBrandingOnPdf,
            'reportLogoBytes': entry.value.reportLogoBytes,
          },
      },
      'workspaceGroups': {
        for (final entry in s.workspaceGroups.entries)
          entry.key: entry.value
              .map((g) => {
                    'id': g.id,
                    'name': g.name,
                    'createdAt': g.createdAt.toIso8601String(),
                  })
              .toList(),
      },
      'workspaceWorkerGroupAssignments': {
        for (final entry in s.workspaceWorkerGroupAssignments.entries)
          entry.key: entry.value,
      },
      'onboardingCompleted': s.onboardingCompleted,
      'workspaceOnboardingCompleted': s.workspaceOnboardingCompleted,
    };
  }
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) {
  return SettingsController(ref);
});
