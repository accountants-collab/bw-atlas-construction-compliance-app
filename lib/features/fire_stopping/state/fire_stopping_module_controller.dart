import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../auth/auth_state.dart';
import '../../../core/env/app_environment.dart';
import '../domain/fire_stopping_models.dart';

class FireStoppingModuleState {
  final List<FireStoppingProject> projects;
  const FireStoppingModuleState({required this.projects});

  FireStoppingModuleState copyWith({List<FireStoppingProject>? projects}) {
    return FireStoppingModuleState(projects: projects ?? this.projects);
  }
}

class FireStoppingModuleController extends StateNotifier<FireStoppingModuleState> {
  FireStoppingModuleController(this._ref) : super(const FireStoppingModuleState(projects: [])) {
    _restore();
  }

  final Ref _ref;

  static const _boxName = 'fire_stopping_module_store';
  static const _key = 'fire_stopping_state_v1';
  static const _legacySurveyBoxBase = 'fd_app_state';
  static const _legacySurveyStateKey = 'survey_state_v2';
  bool _hydrating = false;

  // ── Firestore sync ────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSubscription;
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
          .collection('fireStoppingProjects');
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncProjectToFirestore(FireStoppingProject project) async {
    final collection = _firestoreCollection;
    if (collection == null) return;
    try {
      final m = project.toMap();
      m['_syncedAt'] = FieldValue.serverTimestamp();
      await collection.doc(project.id).set(m);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('fire_stopping_firestore_write_error projectId=${project.id} error=$e');
      }
    }
  }

  Future<void> _syncDirtyToFirestore() async {
    if (_firestoreDirty.isEmpty) return;
    final ids = Set<String>.from(_firestoreDirty);
    _firestoreDirty.clear();
    for (final id in ids) {
      FireStoppingProject? project;
      for (final p in state.projects) {
        if (p.id == id) { project = p; break; }
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
    final updatedProjects = <FireStoppingProject>[...state.projects];
    bool changed = false;
    for (final doc in snapshot.docs) {
      if (_firestoreDirty.contains(doc.id)) {
        continue;
      }
      final fsMap = Map<String, dynamic>.from(doc.data())..remove('_syncedAt');
      final merged = FireStoppingProject.fromMap(fsMap);
      final idx = updatedProjects.indexWhere((p) => p.id == doc.id);
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
  // ── end Firestore sync ────────────────────────────────────────────────

  @override
  set state(FireStoppingModuleState value) {
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
      _persist();
    }
  }

  FireStoppingProject createProject() {
    final project = FireStoppingProject.create();
    state = state.copyWith(projects: [...state.projects, project]);
    return project;
  }

  FireStoppingProject? getProject(String projectId) {
    for (final p in state.projects) {
      if (p.id == projectId) return p;
    }
    return null;
  }

  void updateProject(String projectId, FireStoppingProject Function(FireStoppingProject current) update) {
    final projects = [...state.projects];
    final idx = projects.indexWhere((e) => e.id == projectId);
    if (idx == -1) return;
    projects[idx] = update(projects[idx]);
    state = state.copyWith(projects: projects);
  }

  FireStoppingItem addItem(String projectId) {
    final item = FireStoppingItem.create();
    updateProject(projectId, (p) => p.copyWith(items: [...p.items, item]));
    return item;
  }

  void updateItem({
    required String projectId,
    required String itemId,
    required FireStoppingItem Function(FireStoppingItem current) update,
  }) {
    updateProject(projectId, (p) {
      final items = [...p.items];
      final idx = items.indexWhere((e) => e.id == itemId);
      if (idx == -1) return p;
      items[idx] = update(items[idx]);
      return p.copyWith(items: items);
    });
  }

  Future<void> _restore() async {
    try {
      final box = await Hive.openBox(_boxName);
      dynamic raw = box.get(_key);
      if (_shouldTryLegacyMigration(raw)) {
        final migrated = await _migrateFromLegacySurveyState(targetBox: box);
        if (migrated) {
          raw = box.get(_key);
        }
      }
      if (raw is! String || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      _hydrating = true;
      state = FireStoppingModuleState(
        projects: (decoded['projects'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => FireStoppingProject.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
      _hydrating = false;
    } catch (_) {
      _hydrating = false;
    }
    _startFirestoreListener();
  }

  bool _shouldTryLegacyMigration(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return true;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return true;
      final projects = decoded['projects'];
      if (projects is! List) return true;
      return projects.isEmpty;
    } catch (_) {
      return true;
    }
  }

  List<String> _legacySurveyBoxNames() {
    final ns = AppEnvironmentRuntime.current.hiveNamespace.trim();
    final names = <String>[];
    if (ns.isNotEmpty) {
      names.add('${_legacySurveyBoxBase}_${ns}_fire_stopping');
      names.add('${_legacySurveyBoxBase}_$ns');
    }
    names.add('${_legacySurveyBoxBase}_fire_stopping');
    names.add(_legacySurveyBoxBase);
    return names;
  }

  FireStoppingStatus _parseStatus({dynamic result, dynamic remedialStatus}) {
    final normalizedRemedial = (remedialStatus as String? ?? '').trim().toLowerCase();
    if (normalizedRemedial == 'completed') return FireStoppingStatus.completed;
    if (normalizedRemedial == 'inprogress' || normalizedRemedial == 'in_progress') {
      return FireStoppingStatus.inProgress;
    }

    final normalizedResult = (result as String? ?? '').trim().toLowerCase();
    if (normalizedResult == 'pass') return FireStoppingStatus.completed;
    if (normalizedResult == 'fail' || normalizedResult == 'advisory') {
      return FireStoppingStatus.inProgress;
    }
    return FireStoppingStatus.pending;
  }

  Future<bool> _migrateFromLegacySurveyState({required Box targetBox}) async {
    for (final boxName in _legacySurveyBoxNames()) {
      try {
        final legacyBox = await Hive.openBox(boxName);
        final raw = legacyBox.get(_legacySurveyStateKey);
        if (raw is! String || raw.trim().isEmpty) continue;

        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) continue;
        final surveys = decoded['surveys'];
        if (surveys is! List) continue;

        final projects = <FireStoppingProject>[];
        for (final item in surveys.whereType<Map>()) {
          final survey = Map<String, dynamic>.from(item);
          final surveyType = (survey['type'] as String? ?? '').trim().toLowerCase();
          final workspace = (survey['workspace'] as String? ?? '').trim().toLowerCase();
          if (surveyType != 'firestopping' && workspace != 'firestopping') {
            continue;
          }

          final surveyDoors = (survey['doors'] as List? ?? const []).whereType<Map>();
          final mappedItems = surveyDoors.map((doorRaw) {
            final door = Map<String, dynamic>.from(doorRaw);
            final findings = <FireStoppingFinding>[];

            final defects = (door['fireStoppingDefects'] as List? ?? const []).whereType<Map>();
            findings.addAll(defects.map((defectRaw) {
              final defect = Map<String, dynamic>.from(defectRaw);
              return FireStoppingFinding(
                id: (defect['id'] as String?)?.trim().isNotEmpty == true
                    ? (defect['id'] as String).trim()
                    : FireStoppingFinding.create().id,
                title: (defect['title'] as String? ?? defect['defect'] as String? ?? '').trim(),
                comment: (defect['comment'] as String? ?? defect['notes'] as String? ?? '').trim(),
              );
            }));

            final issues = (door['issues'] as List? ?? const []).whereType<Map>();
            findings.addAll(issues.map((issueRaw) {
              final issue = Map<String, dynamic>.from(issueRaw);
              return FireStoppingFinding(
                id: (issue['id'] as String?)?.trim().isNotEmpty == true
                    ? (issue['id'] as String).trim()
                    : FireStoppingFinding.create().id,
                title: (issue['title'] as String? ?? issue['checkLabel'] as String? ?? '').trim(),
                comment: (issue['comment'] as String? ?? issue['notes'] as String? ?? '').trim(),
              );
            }));

            return FireStoppingItem(
              id: (door['id'] as String?)?.trim().isNotEmpty == true
                  ? (door['id'] as String).trim()
                  : FireStoppingItem.create().id,
              reference: (door['doorIdTag'] as String?)?.trim().isNotEmpty == true
                  ? (door['doorIdTag'] as String).trim()
                  : '#${door['number'] ?? ''}',
              level: (door['floor'] as String? ?? '').trim(),
              location: (door['area'] as String? ?? '').trim(),
              status: _parseStatus(result: door['result'], remedialStatus: door['remedialStatus']),
              findings: findings,
            );
          }).toList();

          projects.add(
            FireStoppingProject(
              id: (survey['id'] as String?)?.trim().isNotEmpty == true
                  ? (survey['id'] as String).trim()
                  : FireStoppingProject.create().id,
              name: (survey['reportName'] as String?)?.trim().isNotEmpty == true
                  ? (survey['reportName'] as String).trim()
                  : (survey['siteName'] as String? ?? '').trim(),
              reference: (survey['reference'] as String? ?? '').trim(),
              date: DateTime.tryParse(
                    (survey['reportDate'] as String?) ?? (survey['createdAt'] as String?) ?? '',
                  ) ??
                  DateTime.now(),
              items: mappedItems,
            ),
          );
        }

        if (projects.isEmpty) continue;

        _hydrating = true;
        state = state.copyWith(projects: projects);
        _hydrating = false;
        await _persist();
        return true;
      } catch (_) {
        // Continue with next legacy source candidate.
      }
    }

    return false;
  }

  Future<void> _persist() async {
    try {
      final box = await Hive.openBox(_boxName);
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
    _firestoreSubscription?.cancel();
    super.dispose();
  }
}

final fireStoppingModuleControllerProvider =
    StateNotifierProvider<FireStoppingModuleController, FireStoppingModuleState>((ref) {
  return FireStoppingModuleController(ref);
});
