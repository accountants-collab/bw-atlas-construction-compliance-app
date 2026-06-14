import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../auth/auth_state.dart';
import '../../notifications/state/workflow_event_dispatcher.dart';
import '../domain/snagging_models.dart';

class SnaggingModuleState {
  final List<SnaggingProject> projects;
  const SnaggingModuleState({required this.projects});

  SnaggingModuleState copyWith({List<SnaggingProject>? projects}) {
    return SnaggingModuleState(projects: projects ?? this.projects);
  }
}

class SnaggingModuleController extends StateNotifier<SnaggingModuleState> {
  SnaggingModuleController(this._ref)
      : super(const SnaggingModuleState(projects: [])) {
    _restore();
    _ref.listen<AuthState>(authControllerProvider, (prev, next) {
      final prevCid = prev?.companyId;
      final nextCid = next.companyId;
      if (prevCid != nextCid && nextCid != null && nextCid.isNotEmpty) {
        _startFirestoreListener();
      }
    });
  }

  final Ref _ref;

  static const _boxName = 'snagging_module_store';
  static const _key = 'snagging_state_v1';
  bool _hydrating = false;
  Box? _box;
  Timer? _persistDebounce;

  // ── Firestore sync ──────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _firestoreSubscription;
  final Set<String> _firestoreDirty = {};

  String? get _resolvedCompanyId {
    try {
      return _ref.read(authControllerProvider).companyId;
    } catch (_) {
      return null;
    }
  }

  CollectionReference<Map<String, dynamic>>? get _firestoreCollection {
    final cid = _resolvedCompanyId;
    if (cid == null || cid.isEmpty) return null;
    try {
      return FirebaseFirestore.instance
          .collection('companies')
          .doc(cid)
          .collection('snaggingProjects');
    } catch (_) {
      return null;
    }
  }

  /// Strips large base64 fields from a SnaggingIssue map before Firestore write.
  static Map<String, dynamic> _stripIssueBase64(Map<String, dynamic> issue) {
    return {
      ...issue,
      'drawingBytesBase64': '',
      'originalPhotoBase64': <String>[],
      'completionPhotoBase64': <String>[],
    };
  }

  /// Merges base64 fields from local issue into the Firestore version.
  static Map<String, dynamic> _mergeIssueBase64(
      Map<String, dynamic> fromFs, Map<String, dynamic> fromLocal) {
    return {
      ...fromFs,
      'drawingBytesBase64':
          (fromFs['drawingBytesBase64'] as String?)?.isEmpty != false
              ? (fromLocal['drawingBytesBase64'] ?? '')
              : fromFs['drawingBytesBase64'],
      'originalPhotoBase64':
          (fromFs['originalPhotoBase64'] as List?)?.isEmpty != false
              ? (fromLocal['originalPhotoBase64'] ?? <String>[])
              : fromFs['originalPhotoBase64'],
      'completionPhotoBase64':
          (fromFs['completionPhotoBase64'] as List?)?.isEmpty != false
              ? (fromLocal['completionPhotoBase64'] ?? <String>[])
              : fromFs['completionPhotoBase64'],
    };
  }

  Map<String, dynamic> _projectToFirestoreMap(SnaggingProject project) {
    final m = project.toMap();
    final strippedIssues = (m['issues'] as List? ?? []).map((issue) {
      final im = Map<String, dynamic>.from(issue as Map);
      return _stripIssueBase64(im);
    }).toList();
    return {
      ...m,
      'issues': strippedIssues,
      '_syncedAt': FieldValue.serverTimestamp()
    };
  }

  SnaggingProject _mergeProjectBase64(
      Map<String, dynamic> fromFs, SnaggingProject? localProject) {
    if (localProject == null) {
      final cleanMap = Map<String, dynamic>.from(fromFs)..remove('_syncedAt');
      return SnaggingProject.fromMap(cleanMap);
    }
    final localById = <String, SnaggingIssue>{
      for (final i in localProject.issues) i.id: i,
    };
    final mergedIssues = (fromFs['issues'] as List? ?? []).map((issue) {
      final im = Map<String, dynamic>.from(issue as Map);
      final localIssue = localById[im['id']];
      if (localIssue != null) {
        return _mergeIssueBase64(im, localIssue.toMap());
      }
      return im;
    }).toList();
    final mergedMap = Map<String, dynamic>.from(fromFs)
      ..['issues'] = mergedIssues
      ..remove('_syncedAt');
    return SnaggingProject.fromMap(mergedMap);
  }

  Future<void> _syncProjectToFirestore(SnaggingProject project) async {
    final collection = _firestoreCollection;
    if (collection == null) return;
    try {
      await collection.doc(project.id).set(_projectToFirestoreMap(project));
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'snagging_firestore_write_error projectId=${project.id} error=$e');
      }
    }
  }

  Future<void> _deleteProjectFromFirestore(String projectId) async {
    final collection = _firestoreCollection;
    if (collection == null) return;
    try {
      await collection.doc(projectId).delete();
    } catch (_) {}
  }

  Future<void> _syncDirtyToFirestore() async {
    if (_firestoreDirty.isEmpty) return;
    final ids = Set<String>.from(_firestoreDirty);
    _firestoreDirty.clear();
    for (final id in ids) {
      SnaggingProject? project;
      for (final p in state.projects) {
        if (p.id == id) {
          project = p;
          break;
        }
      }
      if (project != null) await _syncProjectToFirestore(project);
    }
  }

  void _startFirestoreListener() {
    final collection = _firestoreCollection;
    if (collection == null) return;
    _firestoreSubscription?.cancel();
    _firestoreSubscription = collection
        .snapshots()
        .listen(_handleFirestoreSnapshot, onError: (_) {});
  }

  void _handleFirestoreSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!mounted || _hydrating) return;
    if (snapshot.docs.isEmpty) return;
    final localById = <String, SnaggingProject>{
      for (final p in state.projects) p.id: p,
    };
    final updatedProjects = <SnaggingProject>[...state.projects];
    bool changed = false;
    for (final doc in snapshot.docs) {
      final fsMap = Map<String, dynamic>.from(doc.data());
      final projectId = doc.id;
      if (_firestoreDirty.contains(projectId)) {
        continue;
      }
      final localProject = localById[projectId];
      final merged = _mergeProjectBase64(fsMap, localProject);
      final idx = updatedProjects.indexWhere((p) => p.id == projectId);
      if (idx == -1) {
        updatedProjects.add(merged);
        changed = true;
      } else {
        updatedProjects[idx] = merged;
        changed = true;
      }
    }
    if (changed) {
      _hydrating = true;
      state = state.copyWith(projects: updatedProjects);
      _hydrating = false;
      unawaited(_persist());
    }
  }
  // ── end Firestore sync ──────────────────────────────────────────────────

  @override
  set state(SnaggingModuleState value) {
    if (!_hydrating) {
      final oldIds = {for (final p in state.projects) p.id: p};
      for (final p in value.projects) {
        if (!identical(oldIds[p.id], p)) _firestoreDirty.add(p.id);
      }
      for (final p in value.projects) {
        if (!oldIds.containsKey(p.id)) _firestoreDirty.add(p.id);
      }
    }
    super.state = value;
    if (!_hydrating) {
      _schedulePersist();
    }
  }

  Future<Box> _ensureBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 350), () {
      _persist();
    });
  }

  SnaggingProject createProject() {
    final project = SnaggingProject.create();
    state = state.copyWith(projects: [...state.projects, project]);
    return project;
  }

  SnaggingProject? getProject(String projectId) {
    for (final p in state.projects) {
      if (p.id == projectId) return p;
    }
    return null;
  }

  void updateProject(String projectId,
      SnaggingProject Function(SnaggingProject current) update) {
    final projects = [...state.projects];
    final idx = projects.indexWhere((e) => e.id == projectId);
    if (idx == -1) return;
    projects[idx] = update(projects[idx]);
    state = state.copyWith(projects: projects);
  }

  void archiveProject({required String projectId, required String archivedBy}) {
    updateProject(
      projectId,
      (p) {
        if (p.isArchived) return p;
        return p.copyWith(
          isArchived: true,
          archivedAt: DateTime.now(),
          archivedBy: archivedBy.trim(),
          restoredAt: null,
          restoredBy: '',
        );
      },
    );
  }

  void restoreProject({required String projectId, String restoredBy = ''}) {
    updateProject(
      projectId,
      (p) {
        if (!p.isArchived) return p;
        return p.copyWith(
          isArchived: false,
          archivedAt: null,
          archivedBy: '',
          restoredAt: DateTime.now(),
          restoredBy: restoredBy.trim(),
        );
      },
    );
  }

  Future<void> deleteProjectPermanently({required String projectId}) async {
    final projects = [...state.projects];
    final idx = projects.indexWhere((e) => e.id == projectId);
    if (idx == -1) return;

    projects.removeAt(idx);
    _firestoreDirty.remove(projectId);
    state = state.copyWith(projects: projects);

    await _deleteProjectFromFirestore(projectId);
  }

  SnaggingIssue addIssue(String projectId) {
    final project = getProject(projectId);
    final nextSnagNumber = project == null || project.issues.isEmpty
        ? 1
        : (project.issues
                .map((e) => e.snagNumber)
                .fold<int>(0, (a, b) => a > b ? a : b) +
            1);
    final issue = SnaggingIssue.create(snagNumber: nextSnagNumber);
    updateProject(projectId, (p) => p.copyWith(issues: [...p.issues, issue]));
    return issue;
  }

  void updateIssue({
    required String projectId,
    required String issueId,
    required SnaggingIssue Function(SnaggingIssue current) update,
  }) {
    final projectBefore = getProject(projectId);
    SnaggingIssue? issueBefore;
    if (projectBefore != null) {
      for (final issue in projectBefore.issues) {
        if (issue.id == issueId) {
          issueBefore = issue;
          break;
        }
      }
    }
    updateProject(projectId, (p) {
      final issues = [...p.issues];
      final idx = issues.indexWhere((e) => e.id == issueId);
      if (idx == -1) return p;
      issues[idx] = update(issues[idx]);
      return p.copyWith(issues: issues);
    });

    final projectAfter = getProject(projectId);
    SnaggingIssue? issueAfter;
    if (projectAfter != null) {
      for (final issue in projectAfter.issues) {
        if (issue.id == issueId) {
          issueAfter = issue;
          break;
        }
      }
    }
    if (projectAfter == null || issueBefore == null || issueAfter == null) {
      return;
    }

    if (issueBefore.assignedToUserId != issueAfter.assignedToUserId &&
        issueAfter.assignedToUserId.trim().isNotEmpty) {
      unawaited(
        _ref
            .read(workflowEventDispatcherProvider)
            .dispatchSnaggingWorkflowEvent(
              project: projectAfter,
              issue: issueAfter,
              notificationType: 'snagging_issue_assigned',
              title: 'Snagging: issue assigned',
              body: 'A snagging issue was assigned and requires action.',
              toManagers: false,
              requiresAction: true,
            ),
      );
    }

    if (issueBefore.status != SnaggingStatus.awaitingVerification &&
        issueAfter.status == SnaggingStatus.awaitingVerification) {
      unawaited(
        _ref
            .read(workflowEventDispatcherProvider)
            .dispatchSnaggingWorkflowEvent(
              project: projectAfter,
              issue: issueAfter,
              notificationType: 'snagging_waiting_for_verification',
              title: 'Snagging: item awaiting verification',
              body:
                  'A completed snagging item is waiting for manager verification.',
              toManagers: true,
              requiresAction: true,
            ),
      );
    }

    if (issueBefore.status != SnaggingStatus.approved &&
        issueAfter.status == SnaggingStatus.approved) {
      unawaited(
        _ref
            .read(workflowEventDispatcherProvider)
            .dispatchSnaggingWorkflowEvent(
              project: projectAfter,
              issue: issueAfter,
              notificationType: 'item_approved',
              title: 'Snagging: item approved',
              body: 'The snagging item was approved after review.',
              toManagers: false,
              requiresAction: false,
            ),
      );
    }

    if (issueBefore.status != SnaggingStatus.returned &&
        issueAfter.status == SnaggingStatus.returned) {
      unawaited(
        _ref
            .read(workflowEventDispatcherProvider)
            .dispatchSnaggingWorkflowEvent(
              project: projectAfter,
              issue: issueAfter,
              notificationType: 'item_rejected_needs_update',
              title: 'Snagging: item returned for update',
              body:
                  'The snagging item needs an update and was returned for rework.',
              toManagers: false,
              requiresAction: true,
            ),
      );
    }
  }

  void removeIssue({
    required String projectId,
    required String issueId,
  }) {
    updateProject(projectId, (p) {
      final updatedIssues = p.issues.where((e) => e.id != issueId).toList();
      return p.copyWith(issues: updatedIssues);
    });
  }

  Future<void> _restore() async {
    try {
      final box = await _ensureBox();
      final raw = box.get(_key);
      if (raw is! String || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      _hydrating = true;
      state = SnaggingModuleState(
        projects: (decoded['projects'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => SnaggingProject.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
      _hydrating = false;
    } catch (_) {
      _hydrating = false;
    } finally {
      // Always start Firestore listener after local restore — even on a fresh
      // install with no local Hive data so cross-device sync works immediately.
      _startFirestoreListener();
    }
  }

  Future<void> _persist() async {
    try {
      final box = await _ensureBox();
      final payload = {
        'projects': state.projects.map((e) => e.toMap()).toList(),
      };
      await box.put(_key, jsonEncode(payload));
    } catch (_) {
      // keep UX responsive if local persistence fails
    }
    unawaited(_syncDirtyToFirestore());
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _firestoreSubscription?.cancel();
    super.dispose();
  }
}

final snaggingModuleControllerProvider =
    StateNotifierProvider<SnaggingModuleController, SnaggingModuleState>((ref) {
  return SnaggingModuleController(ref);
});
