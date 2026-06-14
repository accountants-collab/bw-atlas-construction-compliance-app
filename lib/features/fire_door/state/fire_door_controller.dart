import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../auth/auth_state.dart';
import '../../../core/env/app_environment.dart';
import '../domain/fire_door_models.dart';

class FireDoorState {
  final List<FireDoorProject> projects;
  const FireDoorState({required this.projects});

  FireDoorState copyWith({List<FireDoorProject>? projects}) {
    return FireDoorState(projects: projects ?? this.projects);
  }
}

class FireDoorController extends StateNotifier<FireDoorState> {
  FireDoorController(this._ref) : super(const FireDoorState(projects: [])) {
    _restore();
  }

  final Ref _ref;

  static const _boxName = 'fire_door_module_store';
  static const _key = 'fire_door_state_v1';
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
          .collection('fireDoorProjects');
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncProjectToFirestore(FireDoorProject project) async {
    final collection = _firestoreCollection;
    if (collection == null) return;
    try {
      final m = project.toMap();
      m['_syncedAt'] = FieldValue.serverTimestamp();
      await collection.doc(project.id).set(m);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('fire_door_firestore_write_error projectId=${project.id} error=$e');
      }
    }
  }

  Future<void> _syncDirtyToFirestore() async {
    if (_firestoreDirty.isEmpty) return;
    final ids = Set<String>.from(_firestoreDirty);
    _firestoreDirty.clear();
    for (final id in ids) {
      FireDoorProject? project;
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
    final updatedProjects = <FireDoorProject>[...state.projects];
    bool changed = false;
    for (final doc in snapshot.docs) {
      if (_firestoreDirty.contains(doc.id)) {
        continue;
      }
      final fsMap = Map<String, dynamic>.from(doc.data())..remove('_syncedAt');
      final merged = FireDoorProject.fromMap(fsMap);
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
  set state(FireDoorState value) {
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

  FireDoorProject createProject() {
    final project = FireDoorProject.create();
    state = state.copyWith(projects: [...state.projects, project]);
    return project;
  }

  FireDoorProject? getProject(String projectId) {
    for (final p in state.projects) {
      if (p.id == projectId) return p;
    }
    return null;
  }

  void updateProject(String projectId, FireDoorProject Function(FireDoorProject current) update) {
    final projects = [...state.projects];
    final idx = projects.indexWhere((e) => e.id == projectId);
    if (idx == -1) return;
    projects[idx] = update(projects[idx]);
    state = state.copyWith(projects: projects);
  }

  FireDoorItem addItem(String projectId) {
    final item = FireDoorItem.create();
    updateProject(projectId, (p) => p.copyWith(items: [...p.items, item]));
    return item;
  }

  void updateItem({
    required String projectId,
    required String itemId,
    required FireDoorItem Function(FireDoorItem current) update,
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
      state = FireDoorState(
        projects: (decoded['projects'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => FireDoorProject.fromMap(Map<String, dynamic>.from(e)))
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
      names.add('${_legacySurveyBoxBase}_$ns');
    }
    names.add(_legacySurveyBoxBase);
    return names;
  }

  FireDoorResult _parseResult(dynamic raw) {
    final normalized = (raw as String? ?? '').trim().toLowerCase();
    if (normalized == 'pass') return FireDoorResult.pass;
    if (normalized == 'advisory') return FireDoorResult.advisory;
    if (normalized == 'fail') return FireDoorResult.fail;
    return FireDoorResult.notInspected;
  }

  FireDoorIssueSeverity _parseSeverity(dynamic raw) {
    final normalized = (raw as String? ?? '').trim().toLowerCase();
    if (normalized == 'critical') return FireDoorIssueSeverity.critical;
    if (normalized == 'advisory') return FireDoorIssueSeverity.advisory;
    return FireDoorIssueSeverity.fail;
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

        final projects = <FireDoorProject>[];
        for (final item in surveys.whereType<Map>()) {
          final survey = Map<String, dynamic>.from(item);
          final surveyType = (survey['type'] as String? ?? '').trim().toLowerCase();
          final workspace = (survey['workspace'] as String? ?? '').trim().toLowerCase();
          if (surveyType != 'survey' && workspace != 'firedoor') {
            continue;
          }

          final surveyDoors = (survey['doors'] as List? ?? const []).whereType<Map>();
          final mappedItems = surveyDoors.map((doorRaw) {
            final door = Map<String, dynamic>.from(doorRaw);
            final issuesRaw = (door['issues'] as List? ?? const []).whereType<Map>();
            return FireDoorItem(
              id: (door['id'] as String?)?.trim().isNotEmpty == true
                  ? (door['id'] as String).trim()
                  : FireDoorItem.create().id,
              doorRef: (door['doorIdTag'] as String?)?.trim().isNotEmpty == true
                  ? (door['doorIdTag'] as String).trim()
                  : '#${door['number'] ?? ''}',
              level: (door['floor'] as String? ?? '').trim(),
              location: (door['area'] as String? ?? '').trim(),
              inspectionDate: DateTime.tryParse(door['inspectionDate'] as String? ?? '') ?? DateTime.now(),
              result: _parseResult(door['result']),
              issues: issuesRaw
                  .map((issueRaw) {
                    final issue = Map<String, dynamic>.from(issueRaw);
                    return FireDoorIssue(
                      id: (issue['id'] as String?)?.trim().isNotEmpty == true
                          ? (issue['id'] as String).trim()
                          : FireDoorIssue.create().id,
                      title: (issue['title'] as String? ?? issue['checkLabel'] as String? ?? '').trim(),
                      comment: (issue['comment'] as String? ?? issue['notes'] as String? ?? '').trim(),
                      severity: _parseSeverity(issue['severity']),
                    );
                  })
                  .toList(),
            );
          }).toList();

          projects.add(
            FireDoorProject(
              id: (survey['id'] as String?)?.trim().isNotEmpty == true
                  ? (survey['id'] as String).trim()
                  : FireDoorProject.create().id,
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

final fireDoorControllerProvider =
    StateNotifierProvider<FireDoorController, FireDoorState>((ref) {
  return FireDoorController(ref);
});
