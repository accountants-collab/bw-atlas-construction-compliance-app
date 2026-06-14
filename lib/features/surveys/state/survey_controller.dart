import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../auth/auth_state.dart';
import '../../../core/env/app_environment.dart';
import '../../disclaimer/domain/disclaimer_models.dart';
import '../../notifications/state/workflow_event_dispatcher.dart';
import '../domain/inspection_definitions.dart';
import '../domain/models.dart';

final _uuid = Uuid();

class SurveyState {
  final List<Survey> surveys;
  final int lastGeneratedJobNumber;

  const SurveyState({
    required this.surveys,
    this.lastGeneratedJobNumber = 0,
  });

  SurveyState copyWith({List<Survey>? surveys, int? lastGeneratedJobNumber}) =>
      SurveyState(
        surveys: surveys ?? this.surveys,
        lastGeneratedJobNumber:
            lastGeneratedJobNumber ?? this.lastGeneratedJobNumber,
      );
}

class SurveyController extends StateNotifier<SurveyState>
    with WidgetsBindingObserver {
  SurveyController(this._ref, [this._workspace = InspectionWorkspace.fireDoor])
      : super(const SurveyState(surveys: [])) {
    WidgetsBinding.instance.addObserver(this);
    _restoreState();
    // Watch auth so we can attach the Firestore listener as soon as
    // companyId is available (auth may not be fully loaded at init time).
    _ref.listen<AuthState>(authControllerProvider, (prev, next) {
      final prevCid = prev?.companyId;
      final nextCid = next.companyId;
      if (prevCid != nextCid && nextCid != null && nextCid.isNotEmpty) {
        _startFirestoreListener();
      }
    });
  }

  // ── Firestore sync ──────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _firestoreSubscription;

  /// IDs of surveys that have been modified since the last Firestore sync.
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
          .collection('surveys');
    } catch (_) {
      return null;
    }
  }

  /// Recursively strips binary fields (bytes / signatureImageBytes) from a map
  /// so it can be safely written to Firestore within the 1 MB document limit.
  static dynamic _stripBinary(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final k = entry.key as String;
        if ((k == 'bytes' || k == 'signatureImageBytes') &&
            entry.value is List) {
          out[k] = <int>[];
        } else {
          out[k] = _stripBinary(entry.value);
        }
      }
      return out;
    }
    if (value is List) return value.map(_stripBinary).toList();
    return value;
  }

  /// Recursively merges binary fields from [fromLocal] into [fromFs].
  /// Used to restore bytes after loading metadata from Firestore.
  static dynamic _restoreBinary(dynamic fromFs, dynamic fromLocal) {
    if (fromFs is Map && fromLocal is Map) {
      final result = Map<String, dynamic>.from(fromFs);
      for (final key in result.keys.toList()) {
        final fsVal = result[key];
        final localVal = (fromLocal)[key];
        if ((key == 'bytes' || key == 'signatureImageBytes') &&
            fsVal is List &&
            fsVal.isEmpty &&
            localVal is List &&
            localVal.isNotEmpty) {
          result[key] = localVal;
        } else if (fsVal is Map || fsVal is List) {
          result[key] = _restoreBinary(fsVal, localVal);
        }
      }
      return result;
    }
    if (fromFs is List && fromLocal is List) {
      return fromFs.map((item) {
        if (item is Map && item.containsKey('id')) {
          final localItem = fromLocal.firstWhere(
            (l) => l is Map && l['id'] == item['id'],
            orElse: () => <String, dynamic>{},
          );
          return _restoreBinary(item, localItem);
        }
        return item;
      }).toList();
    }
    return fromFs;
  }

  Future<void> _syncSurveyToFirestore(Survey survey) async {
    final collection = _firestoreCollection;
    if (collection == null) return;
    try {
      final raw = _stripBinary(_surveyToMap(survey)) as Map<String, dynamic>;
      raw['_workspace'] = _workspace.name;
      raw['_syncedAt'] = FieldValue.serverTimestamp();
      // Ensure companyId is always populated (backfill for surveys created
      // before this field was set at creation time).
      if ((raw['companyId'] as String? ?? '').isEmpty) {
        final cid = _resolvedCompanyId;
        if (cid != null && cid.isNotEmpty) raw['companyId'] = cid;
      }
      // Embed sidecar pins so other devices get them without a separate read.
      final pinsBySurvey = _pinsBySurveyDrawing[survey.id];
      if (pinsBySurvey != null) {
        raw['_pinsSidecar'] = pinsBySurvey.map(
          (drawingId, pins) =>
              MapEntry(drawingId, pins.map(_floorPlanPinToMap).toList()),
        );
      }
      await collection.doc(survey.id).set(raw);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'survey_firestore_write_error workspace=${_workspace.name} surveyId=${survey.id} error=$e');
      }
    }
  }

  Future<void> _deleteSurveyFromFirestore(String surveyId) async {
    final collection = _firestoreCollection;
    if (collection == null) return;
    try {
      await collection.doc(surveyId).delete();
    } catch (_) {}
  }

  Future<void> _syncDirtyToFirestore() async {
    if (_firestoreDirty.isEmpty) return;
    final ids = Set<String>.from(_firestoreDirty);
    _firestoreDirty.clear();
    for (final id in ids) {
      Survey? survey;
      for (final s in state.surveys) {
        if (s.id == id) {
          survey = s;
          break;
        }
      }
      if (survey != null) {
        await _syncSurveyToFirestore(survey);
      }
    }
  }

  void _startFirestoreListener() {
    final collection = _firestoreCollection;
    if (collection == null) return;
    _firestoreSubscription?.cancel();
    _firestoreSubscription = collection
        .where('_workspace', isEqualTo: _workspace.name)
        .snapshots()
        .listen(_handleFirestoreSnapshot, onError: (_) {});
  }

  void _handleFirestoreSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!mounted || _isHydrating) return;
    if (snapshot.docs.isEmpty) return;
    _mergeFirestoreDocs(snapshot.docs);
  }

  void _mergeFirestoreDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final currentById = <String, Survey>{};
    for (final s in state.surveys) {
      currentById[s.id] = s;
    }
    final currentMapById = <String, Map<String, dynamic>>{};
    for (final s in state.surveys) {
      currentMapById[s.id] = _surveyToMap(s);
    }

    final updatedSurveys = <Survey>[...state.surveys];
    bool changed = false;

    for (final doc in docs) {
      final fsMap = Map<String, dynamic>.from(doc.data());
      final surveyId = doc.id;

      // Do not overwrite local edits that are queued for upload.
      if (_firestoreDirty.contains(surveyId)) {
        continue;
      }

      // Strip internal Firestore-only fields before deserialising.
      final rawPins = fsMap.remove('_pinsSidecar');
      fsMap.remove('_syncedAt');
      fsMap.remove('_workspace');

      final localMap = currentMapById[surveyId];
      final mergedMap = localMap != null
          ? Map<String, dynamic>.from(_restoreBinary(fsMap, localMap) as Map)
          : Map<String, dynamic>.from(fsMap);

      // Restore pins sidecar into in-memory pin store.
      if (rawPins is Map) {
        final surveyPins = <String, List<FloorPlanPin>>{};
        rawPins.forEach((drawingId, pins) {
          if (pins is List) {
            surveyPins[drawingId as String] = pins
                .whereType<Map>()
                .map((p) => _floorPlanPinFromMap(Map<String, dynamic>.from(p)))
                .toList();
          }
        });
        if (surveyPins.isNotEmpty) {
          _pinsBySurveyDrawing[surveyId] = surveyPins;
        }
      }

      final mergedSurvey = _surveyFromMap(mergedMap);
      final idx = updatedSurveys.indexWhere((s) => s.id == surveyId);
      if (idx == -1) {
        updatedSurveys.add(mergedSurvey);
        changed = true;
      } else {
        // Firestore is authoritative for metadata; always update to pick up
        // changes from other devices, but keep our locally-typed bytes.
        updatedSurveys[idx] = mergedSurvey;
        changed = true;
      }
    }

    if (changed) {
      _isHydrating = true;
      state = state.copyWith(surveys: updatedSurveys);
      _isHydrating = false;
      // Persist merged state back to Hive so it is available offline.
      unawaited(_persistState());
      unawaited(_persistPinsState(reason: 'firestore_merge', force: true));
    }
  }

  final Ref _ref;
  final InspectionWorkspace _workspace;

  static const int minimumInstallationPhotoCount = 5;
  static const _boxName = 'fd_app_state';
  static const _stateKey = 'survey_state_v2';
  static const _pinStateKey = 'survey_pins_v1';
  String get _legacyBoxName {
    final suffix = switch (_workspace) {
      InspectionWorkspace.fireDoor => '',
      InspectionWorkspace.fireStopping => '_fire_stopping',
      InspectionWorkspace.snagging => '_snagging',
    };
    return '$_boxName$suffix';
  }

  String get _namespacedBoxName {
    final suffix = switch (_workspace) {
      InspectionWorkspace.fireDoor => '',
      InspectionWorkspace.fireStopping => '_fire_stopping',
      InspectionWorkspace.snagging => '_snagging',
    };
    return '${_boxName}_${AppEnvironmentRuntime.current.hiveNamespace}$suffix';
  }

  // Fire-door keeps legacy state key for backward compatibility.
  String get _storageStateKey {
    switch (_workspace) {
      case InspectionWorkspace.fireDoor:
        return _stateKey;
      case InspectionWorkspace.fireStopping:
        return _stateKey;
      case InspectionWorkspace.snagging:
        return _stateKey;
    }
  }

  bool _isHydrating = false;
  static const Duration _persistDebounceDelay = Duration(milliseconds: 500);
  static const Duration _pinsPersistDebounceDelay = Duration(milliseconds: 220);
  Timer? _persistDebounceTimer;
  Timer? _pinsPersistDebounceTimer;
  int _coalescedPersistUpdates = 0;
  final Map<String, Map<String, List<FloorPlanPin>>> _pinsBySurveyDrawing = {};

  @override
  set state(SurveyState value) {
    // Track which surveys changed so we can sync only those to Firestore.
    if (!_isHydrating) {
      final oldById = <String, Survey>{};
      for (final s in state.surveys) {
        oldById[s.id] = s;
      }
      for (final s in value.surveys) {
        if (!identical(oldById[s.id], s)) {
          _firestoreDirty.add(s.id);
        }
      }
      // Also mark brand-new surveys.
      final oldIds = oldById.keys.toSet();
      for (final s in value.surveys) {
        if (!oldIds.contains(s.id)) {
          _firestoreDirty.add(s.id);
        }
      }
    }
    super.state = value;
    if (!_isHydrating) {
      _schedulePersist(reason: 'state_change');
    }
  }

  Future<void> flushLocalPersistenceNow({String reason = 'manual'}) {
    return _flushAllPersistenceNow(reason: reason);
  }

  Future<void> _flushAllPersistenceNow({required String reason}) async {
    await _runPersistNow(reason: reason, force: true);
    await _persistPinsState(reason: 'flush_$reason', force: true);
  }

  Survey createSurvey(SurveyType type) {
    final nextJobNumber = state.lastGeneratedJobNumber + 1;
    final s = Survey(
      type: type,
      workspace: _workspace, // always this controller's workspace
      reference: _formatJobNumber(nextJobNumber),
      companyId: _resolvedCompanyId ?? '',
    );
    state = state.copyWith(
      surveys: [...state.surveys, s],
      lastGeneratedJobNumber: nextJobNumber,
    );
    return s;
  }

  void archiveSurvey({required String surveyId, required String archivedBy}) {
    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    final current = surveys[idx];
    if (current.isArchived) return;

    surveys[idx] = current.copyWith(
      isArchived: true,
      archivedAt: DateTime.now(),
      archivedBy: archivedBy.trim(),
      restoredAt: null,
      restoredBy: '',
    );
    state = state.copyWith(surveys: surveys);
  }

  void restoreSurvey({required String surveyId, String restoredBy = ''}) {
    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    final current = surveys[idx];
    if (!current.isArchived) return;

    surveys[idx] = current.copyWith(
      isArchived: false,
      archivedAt: null,
      archivedBy: '',
      restoredAt: DateTime.now(),
      restoredBy: restoredBy.trim(),
    );
    state = state.copyWith(surveys: surveys);
  }

  Future<void> deleteSurveyPermanently({required String surveyId}) async {
    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    surveys.removeAt(idx);
    _pinsBySurveyDrawing.remove(surveyId);
    _firestoreDirty.remove(surveyId);
    state = state.copyWith(surveys: surveys);

    await _deleteSurveyFromFirestore(surveyId);
  }

  Survey? getById(String surveyId) {
    for (final s in state.surveys) {
      if (s.id == surveyId) return _mergeSurveyPins(s);
    }
    return null;
  }

  /// Fetch project details from all workspaces (for cross-module project reuse).
  /// Excludes the current workspace and returns only surveys with project details.
  Future<List<Survey>> listProjectDetailsFromAllWorkspaces() async {
    final collection = _firestoreCollection;
    if (collection == null) return [];

    try {
      final snapshot = await collection
          .where('_workspace', isNotEqualTo: _workspace.name)
          .orderBy('_workspace')
          .orderBy('reportDate', descending: true)
          .limit(100)
          .get();

      final projects = <Survey>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        try {
          final survey = _surveyFromMap(data);
          // Only include if it has meaningful project details
          if (survey.reportName.trim().isNotEmpty ||
              survey.siteName.trim().isNotEmpty ||
              survey.addressLine1.trim().isNotEmpty) {
            projects.add(survey);
          }
        } catch (e) {
          debugPrint(
              '[SurveyController] Error parsing project from Firestore: $e');
        }
      }
      return projects;
    } catch (e) {
      debugPrint(
          '[SurveyController] Error fetching cross-workspace projects: $e');
      return [];
    }
  }

  List<FloorPlanPin> getDrawingPins({
    required String surveyId,
    required String drawingId,
    List<FloorPlanPin> fallback = const [],
  }) {
    final surveyPins = _pinsBySurveyDrawing[surveyId];
    final pins = surveyPins?[drawingId];
    if (pins == null) return fallback;
    return List<FloorPlanPin>.from(pins);
  }

  List<({ProjectDrawing drawing, FloorPlanPin pin})> getDrawingPinCandidates(
      String surveyId) {
    final survey = getById(surveyId);
    if (survey == null) return const [];
    return survey.projectDrawings
        .expand((drawing) => getDrawingPins(
                surveyId: surveyId,
                drawingId: drawing.id,
                fallback: drawing.pins)
            .map((pin) => (drawing: drawing, pin: pin)))
        .toList();
  }

  void updateSurveyMeta({
    required String surveyId,
    String? siteName,
    String? siteAddress,
    String? reference,
    String? registerReference,
    DateTime? reportDate,
    String? reportName,
    String? addressLine1,
    String? addressLine2,
    String? cityTown,
    String? postCode,
    String? reportCompletedBy,
    String? clientName,
    String? clientEmail,
    String? clientPhone,
    List<String>? assignedGroupIds,
  }) {
    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    final current = surveys[idx];
    final requestedReference =
        reference == null ? current.reference : reference.trim();
    final generatedReference = requestedReference.isEmpty
        ? _formatJobNumber(state.lastGeneratedJobNumber + 1)
        : requestedReference;
    final parsedGeneratedNumber = _parseGeneratedJobNumber(generatedReference);

    final effReportName = (reportName ?? current.reportName).trim();
    final effAddressLine1 = (addressLine1 ?? current.addressLine1).trim();
    final effAddressLine2 = (addressLine2 ?? current.addressLine2).trim();
    final effCityTown = (cityTown ?? current.cityTown).trim();
    final effPostCode = (postCode ?? current.postCode).trim();

    final addressParts = <String>[
      if (effAddressLine1.isNotEmpty) effAddressLine1,
      if (effAddressLine2.isNotEmpty) effAddressLine2,
      if (effCityTown.isNotEmpty) effCityTown,
      if (effPostCode.isNotEmpty) effPostCode,
    ];
    final formattedAddress = addressParts.join(', ');

    final effectiveSiteName = (siteName ??
            (effReportName.isNotEmpty ? effReportName : current.siteName))
        .trim();
    final effectiveSiteAddress = (siteAddress ?? formattedAddress).trim();

    surveys[idx] = current.copyWith(
      siteName: effectiveSiteName,
      siteAddress: effectiveSiteAddress,
      reference: generatedReference,
      registerReference: registerReference,
      reportDate: reportDate,
      reportName: reportName,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      cityTown: cityTown,
      postCode: postCode,
      reportCompletedBy: reportCompletedBy,
      clientName: clientName,
      clientEmail: clientEmail,
      clientPhone: clientPhone,
      assignedGroupIds: assignedGroupIds,
    );

    state = state.copyWith(
      surveys: surveys,
      lastGeneratedJobNumber: parsedGeneratedNumber != null &&
              parsedGeneratedNumber > state.lastGeneratedJobNumber
          ? parsedGeneratedNumber
          : (requestedReference.isEmpty
              ? state.lastGeneratedJobNumber + 1
              : state.lastGeneratedJobNumber),
    );
  }

  void addProjectDrawings({
    required String surveyId,
    required List<ProjectDrawing> drawings,
  }) {
    if (drawings.isEmpty) return;

    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    final current = surveys[idx];
    surveys[idx] = current
        .copyWith(projectDrawings: [...current.projectDrawings, ...drawings]);
    state = state.copyWith(surveys: surveys);
    var pinSeeded = false;
    for (final drawing in drawings) {
      pinSeeded = _seedPinsIfMissing(
            surveyId: surveyId,
            drawingId: drawing.id,
            fallback: drawing.pins,
          ) ||
          pinSeeded;
    }
    if (pinSeeded) {
      _markPinsChanged(reason: 'add_project_drawings_seed');
    }
  }

  void removeProjectDrawing({
    required String surveyId,
    required String drawingId,
  }) {
    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    final current = surveys[idx];
    final next =
        current.projectDrawings.where((d) => d.id != drawingId).toList();
    surveys[idx] = current.copyWith(projectDrawings: next);
    state = state.copyWith(surveys: surveys);

    final surveyPins = _pinsBySurveyDrawing[surveyId];
    if (surveyPins != null && surveyPins.remove(drawingId) != null) {
      if (surveyPins.isEmpty) {
        _pinsBySurveyDrawing.remove(surveyId);
      }
      _markPinsChanged(reason: 'remove_project_drawing');
    }
  }

  void addFloorPlanPin({
    required String surveyId,
    required String drawingId,
    required FloorPlanPin pin,
  }) {
    final survey = _surveyById(surveyId);
    if (survey == null || !_surveyContainsDrawing(survey, drawingId)) return;

    final drawing = _drawingById(survey, drawingId);
    final existingPins = getDrawingPins(
      surveyId: surveyId,
      drawingId: drawingId,
      fallback: drawing?.pins ?? const [],
    );
    if (existingPins.any((p) => p.id == pin.id)) return;

    _setDrawingPins(
      surveyId: surveyId,
      drawingId: drawingId,
      pins: [...existingPins, pin],
    );
    _markPinsChanged(reason: 'add_floor_plan_pin');
  }

  void removeFloorPlanPin({
    required String surveyId,
    required String drawingId,
    required String pinId,
  }) {
    final survey = _surveyById(surveyId);
    if (survey == null || !_surveyContainsDrawing(survey, drawingId)) return;

    final drawing = _drawingById(survey, drawingId);
    final existingPins = getDrawingPins(
      surveyId: surveyId,
      drawingId: drawingId,
      fallback: drawing?.pins ?? const [],
    );
    final next = existingPins.where((p) => p.id != pinId).toList();
    if (next.length == existingPins.length) return;

    _setDrawingPins(surveyId: surveyId, drawingId: drawingId, pins: next);
    _markPinsChanged(reason: 'remove_floor_plan_pin');
  }

  void updateFloorPlanPin({
    required String surveyId,
    required String drawingId,
    required String pinId,
    String? doorRef,
    double? x,
    double? y,
    int? page,
  }) {
    final hasRef = doorRef != null && doorRef.trim().isNotEmpty;
    final hasPosition = x != null || y != null || page != null;
    if (!hasRef && !hasPosition) return;
    final normalizedDoorRef = doorRef?.trim();

    final survey = _surveyById(surveyId);
    if (survey == null || !_surveyContainsDrawing(survey, drawingId)) return;

    final drawing = _drawingById(survey, drawingId);
    final existingPins = getDrawingPins(
      surveyId: surveyId,
      drawingId: drawingId,
      fallback: drawing?.pins ?? const [],
    );
    final updatedPins = existingPins
        .map(
          (p) => p.id == pinId
              ? FloorPlanPin(
                  id: p.id,
                  drawingId: p.drawingId,
                  page: page ?? p.page,
                  x: x ?? p.x,
                  y: y ?? p.y,
                  doorNumber:
                      hasRef ? normalizedDoorRef ?? p.doorNumber : p.doorNumber,
                  label: hasRef ? normalizedDoorRef ?? p.label : p.label,
                  doorId: p.doorId,
                )
              : p,
        )
        .toList();
    if (_pinsEqual(existingPins, updatedPins)) return;

    _setDrawingPins(
        surveyId: surveyId, drawingId: drawingId, pins: updatedPins);
    _markPinsChanged(reason: 'update_floor_plan_pin');
  }

  /// Approve a fire door inspection (not the remedial workflow).
  void approveDoor({
    required String surveyId,
    required String doorId,
    required String approvedMaintainerName,
    required String approvedMaintainerNumber,
    String approvedBy = '',
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) => d.copyWith(
        approvedMaintainerName: approvedMaintainerName,
        approvedMaintainerNumber: approvedMaintainerNumber,
        approvedBy: approvedBy.isEmpty ? approvedMaintainerName : approvedBy,
        approvedAt: DateTime.now(),
      ),
    );
    unawaited(flushLocalPersistenceNow(reason: 'approve_door'));
  }

  void updateProjectDrawingMetadata({
    required String surveyId,
    required String drawingId,
    required String name,
    String? level,
    String? description,
  }) {
    final surveys = [...state.surveys];
    final sIdx = surveys.indexWhere((s) => s.id == surveyId);
    if (sIdx == -1) return;

    final survey = surveys[sIdx];
    final drawings = [...survey.projectDrawings];
    final dIdx = drawings.indexWhere((d) => d.id == drawingId);
    if (dIdx == -1) return;

    drawings[dIdx] = drawings[dIdx].copyWith(
      name: name.trim().isEmpty ? drawings[dIdx].fileName : name.trim(),
      level: level?.trim() ?? drawings[dIdx].level,
      description: description?.trim() ?? drawings[dIdx].description,
    );

    surveys[sIdx] = survey.copyWith(projectDrawings: drawings);
    state = state.copyWith(surveys: surveys);
  }

  void upsertProjectDrawings({
    required String surveyId,
    required List<ProjectDrawing> drawings,
  }) {
    if (drawings.isEmpty) return;
    final surveys = [...state.surveys];
    final sIdx = surveys.indexWhere((s) => s.id == surveyId);
    if (sIdx == -1) return;

    final survey = surveys[sIdx];
    final existing = [...survey.projectDrawings];
    var changed = false;

    for (final incoming in drawings) {
      final idx = existing.indexWhere((d) => d.id == incoming.id);
      if (idx == -1) {
        existing.add(incoming);
        changed = true;
        continue;
      }

      final current = existing[idx];
      final merged = current.copyWith(
        name: incoming.name,
        fileName: incoming.fileName,
        mimeType: incoming.mimeType,
        level: incoming.level,
        description: incoming.description,
        cloudStoragePath: incoming.cloudStoragePath,
        cloudDownloadUrl: incoming.cloudDownloadUrl,
        bytes: current.bytes.isEmpty ? incoming.bytes : current.bytes,
      );

      final isDifferent = merged.name != current.name ||
          merged.fileName != current.fileName ||
          merged.mimeType != current.mimeType ||
          merged.level != current.level ||
          merged.description != current.description ||
          merged.cloudStoragePath != current.cloudStoragePath ||
          merged.cloudDownloadUrl != current.cloudDownloadUrl ||
          (current.bytes.isEmpty && incoming.bytes.isNotEmpty);

      if (isDifferent) {
        existing[idx] = merged;
        changed = true;
      }
    }

    if (!changed) return;
    surveys[sIdx] = survey.copyWith(projectDrawings: existing);
    state = state.copyWith(surveys: surveys);

    var pinSeeded = false;
    for (final drawing in drawings) {
      pinSeeded = _seedPinsIfMissing(
            surveyId: surveyId,
            drawingId: drawing.id,
            fallback: drawing.pins,
          ) ||
          pinSeeded;
    }
    if (pinSeeded) {
      _markPinsChanged(reason: 'upsert_project_drawings_seed');
    }
  }

  void setProjectDrawingBytes({
    required String surveyId,
    required String drawingId,
    required List<int> bytes,
  }) {
    if (bytes.isEmpty) return;
    final surveys = [...state.surveys];
    final sIdx = surveys.indexWhere((s) => s.id == surveyId);
    if (sIdx == -1) return;

    final survey = surveys[sIdx];
    final drawings = [...survey.projectDrawings];
    final dIdx = drawings.indexWhere((d) => d.id == drawingId);
    if (dIdx == -1) return;

    drawings[dIdx] = drawings[dIdx].copyWith(bytes: bytes);
    surveys[sIdx] = survey.copyWith(projectDrawings: drawings);
    state = state.copyWith(surveys: surveys);
  }

  // Disclaimer acceptance (per survey)
  void acceptSurveyDisclaimer({
    required String surveyId,
    required String inspectorName,
  }) {
    final name = inspectorName.trim();
    if (name.isEmpty) return;

    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    final current = surveys[idx];
    final acceptedAt = DateTime.now();
    final moduleType = disclaimerAcceptanceScopeForModule(
        inspectionWorkspaceSlug(current.workspace));
    surveys[idx] = current.copyWith(
      disclaimerAcceptedAt: acceptedAt,
      disclaimerAcceptedBy: name,
      disclaimerAcceptance: DisclaimerAcceptanceRecord(
        acceptanceId: '',
        companyId: current.companyId,
        projectId: surveyId,
        reportId: surveyId,
        moduleType: moduleType,
        userId: '',
        userEmail: '',
        userRole: '',
        inspectorName: name,
        disclaimerAccepted: true,
        disclaimerAcceptedAt: acceptedAt,
        disclaimerVersion: kDisclaimerVersion,
        acceptedTextSnapshot: disclaimerTextForModule(moduleType),
        expiresAt: disclaimerExpiresAtFrom(acceptedAt),
      ),
    );
    state = state.copyWith(surveys: surveys);
  }

  void setSurveyDisclaimerRecord({
    required String surveyId,
    required DisclaimerAcceptanceRecord record,
  }) {
    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    final current = surveys[idx];
    surveys[idx] = current.copyWith(
      disclaimerAcceptedAt: record.disclaimerAcceptedAt,
      disclaimerAcceptedBy: record.inspectorName,
      disclaimerAcceptance: record,
      reportCompletedBy: current.reportCompletedBy.trim().isEmpty
          ? record.inspectorName
          : current.reportCompletedBy,
    );
    state = state.copyWith(surveys: surveys);
  }

  // ------------------------------------------------------------
  // DOORS (new workflow)
  //
  // - Add Door: UI opens DoorDetailScreen in create mode (no door saved)
  // - Save Door: creates/updates door here
  // - Duplicate: create draft copy, but requires changing Door ID/Ref before saving
  // ------------------------------------------------------------

  int _nextDoorNumber(Survey survey) {
    if (survey.doors.isEmpty) return 1;
    final maxNum =
        survey.doors.map((d) => d.number).reduce((a, b) => a > b ? a : b);
    return maxNum + 1;
  }

  bool doorIdTagExists({
    required String surveyId,
    required String doorIdTag,
    String? exceptDoorId,
  }) {
    final s = getById(surveyId);
    if (s == null) return false;

    final tag = doorIdTag.trim();
    if (tag.isEmpty) return false;

    for (final d in s.doors) {
      if (exceptDoorId != null && d.id == exceptDoorId) continue;
      if (d.doorIdTag.trim().toLowerCase() == tag.toLowerCase()) return true;
    }
    return false;
  }

  DoorResult _deriveDoorResult(Map<String, InspectionCheckResult> inspection,
      {bool replacementRequired = false}) {
    if (replacementRequired) return DoorResult.fail;
    if (inspection.isEmpty) return DoorResult.pass;

    var hasAnswered = false;
    var hasAdvisory = false;
    var hasFail = false;

    for (final r in inspection.values) {
      if (r.outcome == InspectionOutcome.notAnswered ||
          r.outcome == InspectionOutcome.notApplicable) {
        continue;
      }
      hasAnswered = true;
      if (r.outcome == InspectionOutcome.criticalFail ||
          r.outcome == InspectionOutcome.fail) {
        hasFail = true;
      } else if (r.outcome == InspectionOutcome.advisory) {
        hasAdvisory = true;
      }
    }

    if (hasFail) return DoorResult.fail;
    if (hasAdvisory) return DoorResult.advisory;
    if (hasAnswered) return DoorResult.pass;
    // If inspector leaves checks unanswered and no failures/advisories are marked,
    // treat as pass to avoid blocking save workflow.
    return DoorResult.pass;
  }

  List<RemedialItem> _syncRemedialItems({
    required String surveyId,
    required String doorId,
    required List<Issue> issues,
    required List<RemedialItem> existing,
  }) {
    if (issues.isEmpty) return const [];

    final byIssueId = <String, RemedialItem>{
      for (final item in existing) item.issueId: item,
    };

    final next = <RemedialItem>[];
    for (final issue in issues) {
      final prior = byIssueId[issue.id];
      final severity = issue.severity == IssueSeverity.criticalFail
          ? 'Critical'
          : (issue.severity == IssueSeverity.fail ? 'Fail' : 'Advisory');

      final generatedRecommendedAction = issue.actionMappings
          .map((m) {
            final art = (m['actualArtCode'] ?? '').trim();
            final action = (m['actionText'] ?? m['customText'] ?? '').trim();
            if (action.isEmpty) return '';
            return art.isEmpty ? action : '$art $action';
          })
          .where((line) => line.isNotEmpty)
          .join('\n');

      next.add(
        RemedialItem(
          id: prior?.id ?? _uuid.v4(),
          projectId: surveyId,
          doorId: doorId,
          issueId: issue.id,
          category: issue.sourceKey ?? 'General',
          title: issue.comment.trim().isEmpty
              ? 'Inspection issue'
              : issue.comment.trim(),
          severity: severity,
          originalComment: issue.comment,
          originalInspectionPhotos: issue.photos.isNotEmpty
              ? issue.photos
              : (prior?.originalInspectionPhotos ?? const []),
          recommendedAction: prior?.recommendedAction.isNotEmpty == true
              ? prior!.recommendedAction
              : generatedRecommendedAction,
          actionMappings: issue.actionMappings.isNotEmpty
              ? issue.actionMappings
              : (prior?.actionMappings ?? const []),
          status: prior?.status ?? RemedialStatus.pending,
          workerNote: prior?.workerNote ?? '',
          completedBy: prior?.completedBy ?? '',
          completedDate: prior?.completedDate,
          submittedBy: prior?.submittedBy ?? '',
          submittedAt: prior?.submittedAt,
          approvedBy: prior?.approvedBy ?? '',
          approvedAt: prior?.approvedAt,
          rejectedBy: prior?.rejectedBy ?? '',
          rejectedAt: prior?.rejectedAt,
          rejectionNote: prior?.rejectionNote ?? '',
          afterRepairPhotos: prior?.afterRepairPhotos ?? const [],
          approval: prior?.approval,
          managerRejectionNote: prior?.managerRejectionNote ?? '',
        ),
      );
    }

    return next;
  }

  RemedialStatus _deriveRemedialStatus(List<RemedialItem> items) {
    if (items.isEmpty) return RemedialStatus.pending;
    if (items.every((i) => i.status == RemedialStatus.approved)) {
      return RemedialStatus.approved;
    }
    if (items.any((i) => i.status == RemedialStatus.rejectedNeedsRework)) {
      return RemedialStatus.rejectedNeedsRework;
    }
    if (items.every((i) =>
        i.status == RemedialStatus.forApproval ||
        i.status == RemedialStatus.approved)) {
      return RemedialStatus.forApproval;
    }
    if (items.any((i) =>
        i.status == RemedialStatus.inProgress ||
        i.status == RemedialStatus.completedByWorker)) {
      return RemedialStatus.inProgress;
    }
    return RemedialStatus.pending;
  }

  RemedialStatus _statusForRemedialEvidence({
    required RemedialItem item,
    required List<RemedialPhoto> photos,
  }) {
    if (photos.isNotEmpty) return RemedialStatus.completedByWorker;
    if (item.status == RemedialStatus.rejectedNeedsRework) {
      return RemedialStatus.rejectedNeedsRework;
    }
    if (item.workerNote.trim().isNotEmpty) return RemedialStatus.inProgress;
    return RemedialStatus.pending;
  }

  /// Returns a Door draft (not stored in state). Used by UI for create/duplicate.
  Door createDoorDraft({
    required String surveyId,
    Door? fromDoor,
  }) {
    final survey = getById(surveyId);
    final nextNumber = survey == null ? 1 : _nextDoorNumber(survey);

    if (fromDoor == null) {
      return Door(number: nextNumber);
    }

    // Copy everything but clear doorIdTag (must be set new by user)
    return Door(
      number: nextNumber,
      doorIdTag: '',
      floor: fromDoor.floor,
      area: fromDoor.area,
      doorType: fromDoor.doorType,
      doorFunction: fromDoor.doorFunction,
      material: fromDoor.material,
      classification: fromDoor.classification,
      fireRating: fromDoor.fireRating,
      gradingLevel: fromDoor.gradingLevel,
      maintenanceIntervalMonths: fromDoor.maintenanceIntervalMonths,
      fireStoppingItemType: fromDoor.fireStoppingItemType,
      fireStoppingFireRating: fromDoor.fireStoppingFireRating,
      fireStoppingServiceType: fromDoor.fireStoppingServiceType,
      fireStoppingSize: fromDoor.fireStoppingSize,
      fireStoppingQuantity: fromDoor.fireStoppingQuantity,
      fireStoppingDefectDescription: fromDoor.fireStoppingDefectDescription,
      fireStoppingRecommendedAction: fromDoor.fireStoppingRecommendedAction,
      fireStoppingVideoUrl: fromDoor.fireStoppingVideoUrl,
      fireStoppingDefects: fromDoor.fireStoppingDefects,
      isFireExit: fromDoor.isFireExit,
      result: fromDoor.result,
      doorPhotos: fromDoor.doorPhotos,
      issues: fromDoor.issues,
      inspectionResults: fromDoor.inspectionResults,
    );
  }

  /// Creates a NEW door in a survey. Door ID/Ref is required + unique per survey.
  void saveNewDoor({
    required String surveyId,
    required Door door,
  }) {
    final tag = door.doorIdTag.trim();
    if (tag.isEmpty) {
      throw StateError('Door ID / Ref is required.');
    }

    if (doorIdTagExists(surveyId: surveyId, doorIdTag: tag)) {
      throw StateError('Door ID / Ref already exists in this project.');
    }

    final surveys = [...state.surveys];
    final sIdx = surveys.indexWhere((s) => s.id == surveyId);
    if (sIdx == -1) return;

    final survey = surveys[sIdx];
    surveys[sIdx] = survey.copyWith(doors: [...survey.doors, door]);
    state = state.copyWith(surveys: surveys);
    unawaited(flushLocalPersistenceNow(reason: 'save_new_door'));
  }

  /// Updates an EXISTING door in a survey. Door ID/Ref required + unique (excluding self).
  void updateDoor({
    required String surveyId,
    required String doorId,
    required Door Function(Door current) update,
  }) {
    final surveys = [...state.surveys];
    final sIdx = surveys.indexWhere((s) => s.id == surveyId);
    if (sIdx == -1) return;

    final survey = surveys[sIdx];
    final doors = [...survey.doors];
    final dIdx = doors.indexWhere((d) => d.id == doorId);
    if (dIdx == -1) return;

    final previous = doors[dIdx];
    final next = update(previous);

    // Only enforce uniqueness when a non-empty tag is set.
    // Empty tag is allowed during in-progress editing (validated at save time in the UI).
    final tag = next.doorIdTag.trim();
    if (tag.isNotEmpty &&
        doorIdTagExists(
            surveyId: surveyId, doorIdTag: tag, exceptDoorId: doorId)) {
      throw StateError('Door ID / Ref already exists in this project.');
    }

    doors[dIdx] = next;
    final surveyWithUpdatedDoors = survey.copyWith(doors: doors);
    final syncedSurvey =
        _syncReplacementInstallationItemsForSurvey(surveyWithUpdatedDoors);
    surveys[sIdx] = syncedSurvey;
    state = state.copyWith(surveys: surveys);

    if (previous.remedialItems.isEmpty && next.remedialItems.isNotEmpty) {
      final workspaceLabel = _workspace == InspectionWorkspace.fireStopping
          ? 'Fire Stopping'
          : 'Fire Door';
      final doorRef = next.doorIdTag.trim().isNotEmpty
          ? next.doorIdTag.trim()
          : 'Door ${next.number}';
      final notificationType = _workspace == InspectionWorkspace.fireStopping
          ? 'fire_stopping_defect_assigned'
          : 'failed_remedial_task_created';
      unawaited(
        _ref.read(workflowEventDispatcherProvider).dispatchDoorWorkflowEvent(
              survey: syncedSurvey,
              door: next,
              notificationType: notificationType,
              title: '$workspaceLabel: $doorRef assigned for remedial work',
              body:
                  'A new actionable defect has been assigned in ${syncedSurvey.siteName.trim().isEmpty ? syncedSurvey.reference.trim().isEmpty ? 'the project' : syncedSurvey.reference.trim() : syncedSurvey.siteName.trim()}.',
              toManagers: false,
              requiresAction: true,
            ),
      );
    }

    if (!previous.replacementRequired && next.replacementRequired) {
      PreInstallItem? replacementItem;
      for (final item in syncedSurvey.preInstallItems) {
        if (item.fullReplacementTask && item.linkedDoorId.trim() == doorId) {
          replacementItem = item;
          break;
        }
      }
      if (replacementItem != null) {
        final openingRef = replacementItem.doorRef.trim().isNotEmpty
            ? replacementItem.doorRef.trim()
            : 'Opening';
        unawaited(
          _ref
              .read(workflowEventDispatcherProvider)
              .dispatchInstallationWorkflowEvent(
                survey: syncedSurvey,
                item: replacementItem,
                notificationType: 'full_replacement_handover_assigned',
                title:
                    '${_workspace == InspectionWorkspace.fireStopping ? 'Fire Stopping' : 'Fire Door'}: $openingRef assigned for replacement/handover',
                body:
                    'A full replacement or installation handover task has been assigned.',
                toManagers: false,
                requiresAction: true,
              ),
        );
      }
    }
  }

  Door? getDoorById({
    required String surveyId,
    required String doorId,
  }) {
    final s = getById(surveyId);
    if (s == null) return null;
    for (final d in s.doors) {
      if (d.id == doorId) return d;
    }
    return null;
  }

  void deleteDoor({
    required String surveyId,
    required String doorId,
  }) {
    final surveys = [...state.surveys];
    final sIdx = surveys.indexWhere((s) => s.id == surveyId);
    if (sIdx == -1) return;

    final survey = surveys[sIdx];
    final nextDoors = survey.doors.where((d) => d.id != doorId).toList();
    surveys[sIdx] = survey.copyWith(doors: nextDoors);
    state = state.copyWith(surveys: surveys);
  }

  // Legacy method kept for compatibility if any old UI still calls it.
  // Do NOT use in new UX.
  void addDoor(String surveyId) {
    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    final survey = surveys[idx];
    final nextDoorNumber = _nextDoorNumber(survey);

    surveys[idx] =
        survey.copyWith(doors: [...survey.doors, Door(number: nextDoorNumber)]);
    state = state.copyWith(surveys: surveys);
  }

  void updateDoorMeta({
    required String surveyId,
    required String doorId,
    DateTime? inspectionDate,
    String? doorIdTag,
    String? floor,
    String? area,
    DoorType? doorType,
    DoorFunction? doorFunction,
    DoorMaterial? material,
    String? customMaterial,
    DoorClassification? classification,
    String? certificationBodyName,
    FireRating? fireRating,
    GradingLevel? gradingLevel,
    bool? isFireExit,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) => d.copyWith(
        inspectionDate: inspectionDate,
        doorIdTag: doorIdTag,
        floor: floor,
        area: area,
        doorType: doorType,
        doorFunction: doorFunction,
        material: material,
        customMaterial: customMaterial,
        classification: classification,
        certificationBodyName: certificationBodyName,
        fireRating: fireRating,
        gradingLevel: gradingLevel,
        isFireExit: isFireExit,
      ),
    );
  }

  void setDoorPhotos({
    required String surveyId,
    required String doorId,
    required List<PhotoAttachment> photos,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) => d.copyWith(doorPhotos: photos),
    );
  }

  // -----------------------
  // INSPECTION (Source of truth)
  // -----------------------

  String _sourceKeyForCheck(InspectionCheckId id) => 'CHECK:${id.name}';

  InspectionCheckResult _getOrInitResult(Door door, InspectionCheckId checkId) {
    final existing = door.inspectionResults[checkId.name];
    if (existing != null) return existing;

    final def = checkDef(checkId);
    return InspectionCheckResult(
      outcome: InspectionOutcome.notAnswered,
      recommendedAction: def.recommendedAction,
      comment: '',
      photos: const [],
    );
  }

  void setInspectionOutcome({
    required String surveyId,
    required String doorId,
    required InspectionCheckId checkId,
    required InspectionOutcome outcome,
    bool clearFailDetails = false,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final def = checkDef(checkId);

        if (!def.allowedOutcomes.contains(outcome) &&
            outcome != InspectionOutcome.notAnswered) {
          return d;
        }

        final current = _getOrInitResult(d, checkId);

        final shouldKeepGaps = checkId == InspectionCheckId.doorGapsIncorrect &&
            (outcome == InspectionOutcome.fail ||
                outcome == InspectionOutcome.criticalFail);
        final shouldClearDetails = clearFailDetails &&
            outcome != InspectionOutcome.fail &&
            outcome != InspectionOutcome.criticalFail &&
            outcome != InspectionOutcome.advisory;

        final nextResult = current.copyWith(
          outcome: outcome,
          comment: shouldClearDetails ? '' : null,
          recommendedAction: shouldClearDetails ? '' : null,
          photos: shouldClearDetails ? const [] : null,
          clearGaps: shouldClearDetails || !shouldKeepGaps,
          selectedActionCodes: shouldClearDetails ? const [] : null,
          selectedActionMappings: shouldClearDetails ? const [] : null,
          customActionText: shouldClearDetails ? '' : null,
          optionalVideoPath: shouldClearDetails ? '' : null,
        );

        final nextInspection =
            Map<String, InspectionCheckResult>.from(d.inspectionResults);
        nextInspection[checkId.name] = nextResult;

        final nextIssues = _syncIssueForCheck(
          issues: d.issues,
          checkId: checkId,
          result: nextResult,
        );

        final nextDoorResult = _deriveDoorResult(nextInspection,
            replacementRequired: d.replacementRequired);
        final nextRemedialItems = _syncRemedialItems(
          surveyId: surveyId,
          doorId: doorId,
          issues: nextIssues,
          existing: d.remedialItems,
        );
        final nextRemedialStatus = _deriveRemedialStatus(nextRemedialItems);

        if (kDebugMode) {
          final isFailOutcome = outcome == InspectionOutcome.fail ||
              outcome == InspectionOutcome.criticalFail;
          if (isFailOutcome) {
            debugPrint(
              'remedial_task_sync workspace=${_workspace.name} survey=$surveyId door=$doorId check=${checkId.name} outcome=${outcome.name} issues=${nextIssues.length} remedialItems=${nextRemedialItems.length} status=${nextRemedialStatus.name}',
            );
          }
        }

        return d.copyWith(
          inspectionResults: nextInspection,
          issues: nextIssues,
          result: nextDoorResult,
          remedialItems: nextRemedialItems,
          remedialStatus: nextRemedialStatus,
        );
      },
    );
  }

  void updateRemedialItemProgress({
    required String surveyId,
    required String doorId,
    required String remedialItemId,
    required RemedialStatus status,
    String? workerNote,
    String? completedBy,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final items = d.remedialItems.map((item) {
          if (item.id != remedialItemId) return item;
          return item.copyWith(
            status: status,
            workerNote: workerNote,
            completedBy: completedBy,
            completedDate: (status == RemedialStatus.completedByWorker ||
                    status == RemedialStatus.forApproval)
                ? DateTime.now()
                : item.completedDate,
          );
        }).toList();

        return d.copyWith(
          remedialItems: items,
          remedialStatus: _deriveRemedialStatus(items),
        );
      },
    );
  }

  void addRemedialPhoto({
    required String surveyId,
    required String doorId,
    required String remedialItemId,
    required List<RemedialPhoto> photos,
    String completedBy = '',
  }) {
    if (photos.isEmpty) return;
    final beforeDoor = getDoorById(surveyId: surveyId, doorId: doorId);
    var hadEvidence = false;
    if (beforeDoor != null) {
      for (final item in beforeDoor.remedialItems) {
        if (item.id == remedialItemId) {
          hadEvidence = item.afterRepairPhotos.isNotEmpty;
          break;
        }
      }
    }

    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final items = d.remedialItems.map((item) {
          if (item.id != remedialItemId) return item;
          final nextPhotos = [...item.afterRepairPhotos, ...photos];
          final hasEvidence = nextPhotos.isNotEmpty;
          return item.copyWith(
            afterRepairPhotos: nextPhotos,
            status: _statusForRemedialEvidence(item: item, photos: nextPhotos),
            completedBy: hasEvidence
                ? (completedBy.trim().isNotEmpty
                    ? completedBy.trim()
                    : item.completedBy)
                : '',
            completedDate:
                hasEvidence ? (item.completedDate ?? DateTime.now()) : null,
            clearCompletedDate: !hasEvidence,
          );
        }).toList();

        return d.copyWith(
          remedialItems: items,
          remedialStatus: _deriveRemedialStatus(items),
        );
      },
    );

    final survey = getById(surveyId);
    final door = getDoorById(surveyId: surveyId, doorId: doorId);
    if (!hadEvidence && survey != null && door != null) {
      final doorRef = door.doorIdTag.trim().isNotEmpty
          ? door.doorIdTag.trim()
          : 'Door ${door.number}';
      unawaited(
        _ref.read(workflowEventDispatcherProvider).dispatchDoorWorkflowEvent(
              survey: survey,
              door: door,
              notificationType: 'completion_evidence_uploaded',
              title:
                  '${_workspace == InspectionWorkspace.fireStopping ? 'Fire Stopping' : 'Fire Door'}: completion evidence uploaded for $doorRef',
              body: 'The worker uploaded completion evidence.',
              toManagers: true,
              requiresAction: false,
            ),
      );
    }
  }

  void setRemedialItemPhotos({
    required String surveyId,
    required String doorId,
    required String remedialItemId,
    required List<RemedialPhoto> photos,
    String completedBy = '',
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final items = d.remedialItems.map((item) {
          if (item.id != remedialItemId) return item;
          final hasEvidence = photos.isNotEmpty;
          return item.copyWith(
            afterRepairPhotos: photos,
            status: _statusForRemedialEvidence(item: item, photos: photos),
            completedBy: hasEvidence
                ? (completedBy.trim().isNotEmpty
                    ? completedBy.trim()
                    : item.completedBy)
                : '',
            completedDate:
                hasEvidence ? (item.completedDate ?? DateTime.now()) : null,
            clearCompletedDate: !hasEvidence,
          );
        }).toList();
        return d.copyWith(
            remedialItems: items, remedialStatus: _deriveRemedialStatus(items));
      },
    );
  }

  void addRemedialManagerApprovalPhotos({
    required String surveyId,
    required String doorId,
    required String remedialItemId,
    required List<RemedialPhoto> photos,
  }) {
    if (photos.isEmpty) return;
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final items = d.remedialItems.map((item) {
          if (item.id != remedialItemId) return item;
          return item.copyWith(managerApprovalPhotos: [
            ...item.managerApprovalPhotos,
            ...photos
          ]);
        }).toList();
        return d.copyWith(remedialItems: items);
      },
    );
  }

  void setRemedialManagerApprovalPhotos({
    required String surveyId,
    required String doorId,
    required String remedialItemId,
    required List<RemedialPhoto> photos,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final items = d.remedialItems.map((item) {
          if (item.id != remedialItemId) return item;
          return item.copyWith(managerApprovalPhotos: photos);
        }).toList();
        return d.copyWith(remedialItems: items);
      },
    );
  }

  void addRemedialManagerRejectionPhotos({
    required String surveyId,
    required String doorId,
    required String remedialItemId,
    required List<RemedialPhoto> photos,
  }) {
    if (photos.isEmpty) return;
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final items = d.remedialItems.map((item) {
          if (item.id != remedialItemId) return item;
          return item.copyWith(managerRejectionPhotos: [
            ...item.managerRejectionPhotos,
            ...photos
          ]);
        }).toList();
        return d.copyWith(remedialItems: items);
      },
    );
  }

  void setRemedialManagerRejectionPhotos({
    required String surveyId,
    required String doorId,
    required String remedialItemId,
    required List<RemedialPhoto> photos,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final items = d.remedialItems.map((item) {
          if (item.id != remedialItemId) return item;
          return item.copyWith(managerRejectionPhotos: photos);
        }).toList();
        return d.copyWith(remedialItems: items);
      },
    );
  }

  void setRemedialItemWorkerNote({
    required String surveyId,
    required String doorId,
    required String remedialItemId,
    required String note,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final items = d.remedialItems.map((item) {
          if (item.id != remedialItemId) return item;
          final nextStatus = item.status == RemedialStatus.pending
              ? RemedialStatus.inProgress
              : item.status;
          return item.copyWith(workerNote: note, status: nextStatus);
        }).toList();
        return d.copyWith(
            remedialItems: items, remedialStatus: _deriveRemedialStatus(items));
      },
    );
  }

  bool canSubmitDoorForApproval({
    required String surveyId,
    required String doorId,
  }) {
    final door = getDoorById(surveyId: surveyId, doorId: doorId);
    if (door == null) return false;
    if (door.remedialItems.isEmpty) return false;

    for (final item in door.remedialItems) {
      if (item.status == RemedialStatus.approved) continue;
      if (item.afterRepairPhotos.isEmpty) return false;
    }
    return true;
  }

  void submitDoorForApproval({
    required String surveyId,
    required String doorId,
    required String completedBy,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final now = DateTime.now();
        final issueById = {for (final issue in d.issues) issue.id: issue};
        final items = d.remedialItems
            .map((item) => item.copyWith(
                  status: RemedialStatus.forApproval,
                  originalInspectionPhotos:
                      issueById[item.issueId]?.photos.isNotEmpty == true
                          ? issueById[item.issueId]!.photos
                          : item.originalInspectionPhotos,
                  completedBy: completedBy,
                  completedDate: now,
                  submittedBy: completedBy,
                  submittedAt: now,
                  approvedBy: '',
                  clearApprovedAt: true,
                  rejectedBy: '',
                  clearRejectedAt: true,
                  rejectionNote: '',
                  managerRejectionNote: '',
                  managerRejectionPhotos: const [],
                ))
            .toList();
        return d.copyWith(
          remedialItems: items,
          remedialStatus: RemedialStatus.forApproval,
        );
      },
    );
    unawaited(flushLocalPersistenceNow(reason: 'submit_door_for_approval'));

    final survey = getById(surveyId);
    final door = getDoorById(surveyId: surveyId, doorId: doorId);
    if (survey != null && door != null) {
      final doorRef = door.doorIdTag.trim().isNotEmpty
          ? door.doorIdTag.trim()
          : 'Door ${door.number}';
      unawaited(
        _ref.read(workflowEventDispatcherProvider).dispatchDoorWorkflowEvent(
              survey: survey,
              door: door,
              notificationType: 'worker_submitted_remedial_for_approval',
              title:
                  '${_workspace == InspectionWorkspace.fireStopping ? 'Fire Stopping' : 'Fire Door'}: $doorRef submitted for approval',
              body: '$completedBy submitted remedial work for approval.',
              toManagers: true,
              requiresAction: true,
            ),
      );
    }
  }

  void approveDoorRemedial({
    required String surveyId,
    required String doorId,
    required String approvedBy,
    required Map<String, bool> defectPassByItemId,
    String comment = '',
    bool? maintenanceLabelFitted,
    DateTime? nextMaintenanceDueDate,
    String finalManagerComments = '',
    String signatureAssetPath = '',
    String signatureMethod = 'asset',
    String signatureInitials = '',
    List<int> signatureImageBytes = const [],
    String approvedMaintainerName = '',
    String approvedMaintainerNumber = '',
    String certificateJobReferenceOverride = '',
    int? maintenanceIntervalMonths,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final allPass = d.remedialItems.isNotEmpty &&
            d.remedialItems
                .every((item) => defectPassByItemId[item.id] == true);
        if (!allPass) {
          return d;
        }
        final now = DateTime.now();
        final items = d.remedialItems
            .map(
              (item) => item.copyWith(
                status: RemedialStatus.approved,
                approvedBy: approvedBy,
                approvedAt: now,
                rejectedBy: '',
                clearRejectedAt: true,
                rejectionNote: '',
                managerRejectionNote: '',
                managerRejectionPhotos: const [],
                approval: Approval(
                  projectId: surveyId,
                  doorId: doorId,
                  approvedBy: approvedBy,
                  decision: 'approved',
                  comment: comment,
                  approvedDate: now,
                  maintenanceLabelFitted: maintenanceLabelFitted,
                  nextMaintenanceDueDate: nextMaintenanceDueDate,
                  finalManagerComments: finalManagerComments,
                  signatureAssetPath: signatureAssetPath,
                  signatureMethod: signatureMethod,
                  signatureInitials: signatureInitials,
                  signatureImageBytes: signatureImageBytes,
                  approvedMaintainerName: approvedMaintainerName,
                  approvedMaintainerNumber: approvedMaintainerNumber,
                  certificateJobReferenceOverride:
                      certificateJobReferenceOverride,
                ),
              ),
            )
            .toList();
        return d.copyWith(
          remedialItems: items,
          remedialStatus: RemedialStatus.approved,
          maintenanceIntervalMonths: maintenanceIntervalMonths,
        );
      },
    );
    unawaited(flushLocalPersistenceNow(reason: 'approve_door_remedial'));

    final survey = getById(surveyId);
    final door = getDoorById(surveyId: surveyId, doorId: doorId);
    if (survey != null && door != null) {
      final doorRef = door.doorIdTag.trim().isNotEmpty
          ? door.doorIdTag.trim()
          : 'Door ${door.number}';
      unawaited(
        _ref.read(workflowEventDispatcherProvider).dispatchDoorWorkflowEvent(
              survey: survey,
              door: door,
              notificationType: 'item_approved',
              title:
                  '${_workspace == InspectionWorkspace.fireStopping ? 'Fire Stopping' : 'Fire Door'}: $doorRef approved',
              body: '$approvedBy approved the submitted remedial work.',
              toManagers: false,
              requiresAction: false,
            ),
      );
    }
  }

  void rejectDoorRemedial({
    required String surveyId,
    required String doorId,
    required String approvedBy,
    required Map<String, bool> defectPassByItemId,
    required Map<String, String> defectFailCommentByItemId,
    String rejectionNote = '',
    bool? maintenanceLabelFitted,
    DateTime? nextMaintenanceDueDate,
    String finalManagerComments = '',
    String signatureAssetPath = '',
    String signatureMethod = 'asset',
    String signatureInitials = '',
    List<int> signatureImageBytes = const [],
    String approvedMaintainerName = '',
    String approvedMaintainerNumber = '',
    String certificateJobReferenceOverride = '',
    int? maintenanceIntervalMonths,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final now = DateTime.now();
        final items = d.remedialItems.map(
          (item) {
            final isPass = defectPassByItemId[item.id] == true;
            final failComment =
                defectFailCommentByItemId[item.id]?.trim() ?? '';
            if (isPass) {
              return item.copyWith(
                status: RemedialStatus.approved,
                approvedBy: approvedBy,
                approvedAt: now,
                rejectedBy: '',
                clearRejectedAt: true,
                rejectionNote: '',
                managerRejectionNote: '',
                managerRejectionPhotos: const [],
                approval: Approval(
                  projectId: surveyId,
                  doorId: doorId,
                  approvedBy: approvedBy,
                  approvedDate: now,
                  decision: 'approved',
                  comment: finalManagerComments.trim().isEmpty
                      ? 'Approved per defect manager review.'
                      : finalManagerComments.trim(),
                  maintenanceLabelFitted: maintenanceLabelFitted,
                  nextMaintenanceDueDate: nextMaintenanceDueDate,
                  finalManagerComments: finalManagerComments,
                  signatureAssetPath: signatureAssetPath,
                  signatureMethod: signatureMethod,
                  signatureInitials: signatureInitials,
                  signatureImageBytes: signatureImageBytes,
                  approvedMaintainerName: approvedMaintainerName,
                  approvedMaintainerNumber: approvedMaintainerNumber,
                  certificateJobReferenceOverride:
                      certificateJobReferenceOverride,
                ),
              );
            }
            final itemRejection =
                failComment.isEmpty ? rejectionNote : failComment;
            return item.copyWith(
              status: RemedialStatus.rejectedNeedsRework,
              rejectedBy: approvedBy,
              rejectedAt: now,
              rejectionNote: itemRejection,
              approvedBy: '',
              clearApprovedAt: true,
              managerApprovalPhotos: const [],
              approval: Approval(
                projectId: surveyId,
                doorId: doorId,
                approvedBy: approvedBy,
                approvedDate: now,
                decision: 'rejected',
                comment: itemRejection,
                maintenanceLabelFitted: maintenanceLabelFitted,
                nextMaintenanceDueDate: nextMaintenanceDueDate,
                finalManagerComments: finalManagerComments,
                signatureAssetPath: signatureAssetPath,
                signatureMethod: signatureMethod,
                signatureInitials: signatureInitials,
                signatureImageBytes: signatureImageBytes,
                approvedMaintainerName: approvedMaintainerName,
                approvedMaintainerNumber: approvedMaintainerNumber,
                certificateJobReferenceOverride:
                    certificateJobReferenceOverride,
              ),
              managerRejectionNote: itemRejection,
            );
          },
        ).toList();
        return d.copyWith(
          remedialItems: items,
          remedialStatus: _deriveRemedialStatus(items),
          maintenanceIntervalMonths: maintenanceIntervalMonths,
        );
      },
    );
    unawaited(flushLocalPersistenceNow(reason: 'reject_door_remedial'));

    final survey = getById(surveyId);
    final door = getDoorById(surveyId: surveyId, doorId: doorId);
    if (survey != null && door != null) {
      final doorRef = door.doorIdTag.trim().isNotEmpty
          ? door.doorIdTag.trim()
          : 'Door ${door.number}';
      unawaited(
        _ref.read(workflowEventDispatcherProvider).dispatchDoorWorkflowEvent(
              survey: survey,
              door: door,
              notificationType: 'item_rejected_needs_update',
              title:
                  '${_workspace == InspectionWorkspace.fireStopping ? 'Fire Stopping' : 'Fire Door'}: $doorRef needs update',
              body:
                  '$approvedBy rejected the remedial work and sent it back for rework.',
              toManagers: false,
              requiresAction: true,
            ),
      );
    }
  }

  void reopenDoorRemedial({
    required String surveyId,
    required String doorId,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final items = d.remedialItems.map((item) {
          if (item.status != RemedialStatus.approved) {
            return item;
          }
          return item.copyWith(
            status: RemedialStatus.forApproval,
            approvedBy: '',
            clearApprovedAt: true,
            rejectedBy: '',
            clearRejectedAt: true,
            rejectionNote: '',
            managerApprovalPhotos: const [],
            managerRejectionPhotos: const [],
            clearApproval: true,
            managerRejectionNote: '',
          );
        }).toList();

        return d.copyWith(
          remedialItems: items,
          remedialStatus: _deriveRemedialStatus(items),
        );
      },
    );
  }

  // -----------------------
  // PRE-INSTALLATION -> INSTALLATION WORKFLOW
  // -----------------------

  List<InstallationTask> _defaultInstallationTasks() {
    return [
      InstallationTask(
          title: 'Frame installed', category: 'Frame', required: true),
      InstallationTask(
          title: 'Leaf installed', category: 'Leaf', required: true),
      InstallationTask(
          title: 'Gaps checked', category: 'Quality', required: true),
      InstallationTask(
          title: 'Seals fitted', category: 'Seals', required: true),
      InstallationTask(
          title: 'Hinges fitted', category: 'Ironmongery', required: true),
      InstallationTask(
          title: 'Closer fitted', category: 'Ironmongery', required: true),
      InstallationTask(
          title: 'Lock/latch fitted', category: 'Ironmongery', required: true),
      InstallationTask(
          title: 'Signage fitted', category: 'Signage', required: true),
      InstallationTask(
          title: 'Glazing completed', category: 'Glazing', required: false),
      InstallationTask(
          title: 'Ironmongery checked',
          category: 'Ironmongery',
          required: true),
      InstallationTask(
          title: 'Final operation checked',
          category: 'Final Check',
          required: true),
      InstallationTask(
          title: 'Site area left clean', category: 'Handover', required: true),
      InstallationTask(
          title: 'Handover ready', category: 'Handover', required: true),
    ];
  }

  Survey _syncReplacementInstallationItemsForSurvey(Survey survey) {
    if (survey.workspace != InspectionWorkspace.fireDoor) {
      return survey;
    }

    final replacementDoors =
        survey.doors.where((door) => door.replacementRequired).toList();
    final replacementDoorById = {
      for (final door in replacementDoors) door.id: door
    };

    final existingByDoorId = <String, PreInstallItem>{
      for (final item in survey.preInstallItems)
        if (item.fullReplacementTask && item.linkedDoorId.trim().isNotEmpty)
          item.linkedDoorId.trim(): item,
    };

    final syncedItems = <PreInstallItem>[];
    for (final door in replacementDoors) {
      final existing = existingByDoorId[door.id];
      syncedItems.add(
        _buildReplacementInstallItem(
          surveyId: survey.id,
          door: door,
          existing: existing,
        ),
      );
    }

    final retainedItems = <PreInstallItem>[];
    for (final item in survey.preInstallItems) {
      if (!item.fullReplacementTask) {
        retainedItems.add(item);
        continue;
      }

      final linkedDoorId = item.linkedDoorId.trim();
      if (linkedDoorId.isEmpty ||
          replacementDoorById.containsKey(linkedDoorId)) {
        continue;
      }

      // Keep historical records if replacement flag was removed; hide from active replacement flow.
      retainedItems.add(item.copyWith(fullReplacementTask: false));
    }

    return survey.copyWith(preInstallItems: [...retainedItems, ...syncedItems]);
  }

  PreInstallItem _buildReplacementInstallItem({
    required String surveyId,
    required Door door,
    PreInstallItem? existing,
  }) {
    final itemId = existing?.id ?? _uuid.v4();
    final fallbackRef = 'Door ${door.number}';
    final doorRef =
        door.doorIdTag.trim().isEmpty ? fallbackRef : door.doorIdTag.trim();
    final matchingDoorPhotos = door.doorPhotos
        .where((photo) => !photo.mimeType.toLowerCase().startsWith('video/'))
        .toList();
    final mappedPhotos = matchingDoorPhotos
        .map(
          (photo) => PreInstallPhoto(
            id: photo.id,
            projectId: surveyId,
            itemId: itemId,
            type: 'preInstall',
            fileName: photo.fileName,
            mimeType: photo.mimeType,
            bytes: photo.bytes,
            createdAt: photo.capturedAt,
          ),
        )
        .toList();

    final leafApproxSummary = door.configuration == DoorConfiguration.singleLeaf
        ? ''
        : [
            if (door.replacementDoor2Width.trim().isNotEmpty)
              'Leaf 1 approx width: ${door.replacementDoor2Width.trim()} mm',
            if (door.replacementDoor2Height.trim().isNotEmpty)
              'Leaf 2 approx width: ${door.replacementDoor2Height.trim()} mm',
          ].join(' | ');

    final notes = <String>[
      'Full door set replacement required from fire door inspection.',
      if (leafApproxSummary.isNotEmpty) leafApproxSummary,
    ].join(' ');

    final defaultItem = PreInstallItem(
      id: itemId,
      projectId: surveyId,
      linkedDoorId: door.id,
      fullReplacementTask: true,
      doorRef: doorRef,
      level: door.floor.trim(),
      location: door.area.trim(),
      fireRating: door.fireRating.name.toUpperCase(),
      configuration: door.configuration.name,
      openingWidth: door.replacementDoor1Width.trim(),
      openingHeight: door.replacementDoor1Height.trim(),
      preInstallComments: notes,
      specialNotes: notes,
      preInstallPhotos: mappedPhotos,
      installationTasks: _defaultInstallationTasks(),
    );

    if (existing == null) {
      return defaultItem;
    }

    return existing.copyWith(
      linkedDoorId: door.id,
      fullReplacementTask: true,
      doorRef: doorRef,
      level: door.floor.trim(),
      location: door.area.trim(),
      fireRating: door.fireRating.name.toUpperCase(),
      configuration: door.configuration.name,
      openingWidth: door.replacementDoor1Width.trim(),
      openingHeight: door.replacementDoor1Height.trim(),
      preInstallComments: notes,
      specialNotes: notes,
      preInstallPhotos: mappedPhotos,
      installationTasks: existing.installationTasks.isEmpty
          ? _defaultInstallationTasks()
          : existing.installationTasks,
    );
  }

  String _nextDoorRef(Survey survey) {
    final next = survey.preInstallItems.length + 1;
    return 'OPEN-${next.toString().padLeft(3, '0')}';
  }

  void addPreInstallItem(
    String surveyId, {
    PreInstallSurveyType surveyType = PreInstallSurveyType.specification_order,
    bool? existingDoorRemovalRequired,
  }) {
    final surveys = [...state.surveys];
    final idx = surveys.indexWhere((s) => s.id == surveyId);
    if (idx == -1) return;

    final survey = surveys[idx];
    final resolvedRemovalRequired = existingDoorRemovalRequired ??
        (surveyType != PreInstallSurveyType.new_opening &&
            surveyType != PreInstallSurveyType.installation_only);

    final item = PreInstallItem(
      id: _uuid.v4(),
      projectId: surveyId,
      surveyType: surveyType,
      existingDoorRemovalRequired: resolvedRemovalRequired,
      doorRef: _nextDoorRef(survey),
      features: _defaultDoorFeatures(),
      hardware: _defaultDoorHardware(),
      measurements: DoorMeasurementSet(id: _uuid.v4()),
      installationTasks: _defaultInstallationTasks(),
    );

    surveys[idx] =
        survey.copyWith(preInstallItems: [...survey.preInstallItems, item]);
    state = state.copyWith(surveys: surveys);
  }

  PreInstallItem? getPreInstallItem(
      {required String surveyId, required String itemId}) {
    final survey = getById(surveyId);
    if (survey == null) return null;
    for (final item in survey.preInstallItems) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  void updatePreInstallItem({
    required String surveyId,
    required String itemId,
    required PreInstallItem Function(PreInstallItem current) update,
  }) {
    final surveys = [...state.surveys];
    final sIdx = surveys.indexWhere((s) => s.id == surveyId);
    if (sIdx == -1) return;

    final survey = surveys[sIdx];
    final items = [...survey.preInstallItems];
    final iIdx = items.indexWhere((i) => i.id == itemId);
    if (iIdx == -1) return;

    items[iIdx] = update(items[iIdx]);
    surveys[sIdx] = survey.copyWith(preInstallItems: items);
    state = state.copyWith(surveys: surveys);
  }

  void deletePreInstallItem({
    required String surveyId,
    required String itemId,
  }) {
    final surveys = [...state.surveys];
    final sIdx = surveys.indexWhere((s) => s.id == surveyId);
    if (sIdx == -1) return;

    final survey = surveys[sIdx];
    final nextItems =
        survey.preInstallItems.where((i) => i.id != itemId).toList();
    surveys[sIdx] = survey.copyWith(preInstallItems: nextItems);
    state = state.copyWith(surveys: surveys);
  }

  void addPreInstallPhotos({
    required String surveyId,
    required String itemId,
    required List<PreInstallPhoto> photos,
  }) {
    if (photos.isEmpty) return;
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) => item
          .copyWith(preInstallPhotos: [...item.preInstallPhotos, ...photos]),
    );
  }

  void setPreInstallPhotos({
    required String surveyId,
    required String itemId,
    required List<PreInstallPhoto> photos,
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) => item.copyWith(preInstallPhotos: photos),
    );
  }

  void updateInstallationTaskStatus({
    required String surveyId,
    required String itemId,
    required String taskId,
    required InstallationTaskStatus status,
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) {
        final tasks = item.installationTasks.map((t) {
          if (t.id != taskId) return t;
          return t.copyWith(status: status);
        }).toList();

        final nextStatus =
            tasks.any((t) => t.status == InstallationTaskStatus.completed)
                ? InstallationStatus.inProgress
                : item.status;

        return item.copyWith(installationTasks: tasks, status: nextStatus);
      },
    );
  }

  void setInstallationTaskWorkerNote({
    required String surveyId,
    required String itemId,
    required String taskId,
    required String note,
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) {
        final tasks = item.installationTasks.map((t) {
          if (t.id != taskId) return t;
          return t.copyWith(workerNote: note);
        }).toList();

        final nextStatus = item.status == InstallationStatus.pending
            ? InstallationStatus.inProgress
            : item.status;
        return item.copyWith(installationTasks: tasks, status: nextStatus);
      },
    );
  }

  void setInstallationWorkerNote({
    required String surveyId,
    required String itemId,
    required String note,
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) => item.copyWith(
        workerNote: note,
        status: item.status == InstallationStatus.pending
            ? InstallationStatus.inProgress
            : item.status,
      ),
    );
  }

  void addInstallationPhotos({
    required String surveyId,
    required String itemId,
    required List<InstallationPhoto> photos,
  }) {
    if (photos.isEmpty) return;
    final beforeItem = getPreInstallItem(surveyId: surveyId, itemId: itemId);
    final hadEvidence = beforeItem?.installationPhotos.isNotEmpty ?? false;
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) => item.copyWith(
        installationPhotos: [...item.installationPhotos, ...photos],
        status: item.status == InstallationStatus.pending
            ? InstallationStatus.inProgress
            : item.status,
      ),
    );
    final survey = getById(surveyId);
    final item = getPreInstallItem(surveyId: surveyId, itemId: itemId);
    if (!hadEvidence && survey != null && item != null) {
      final opening =
          item.doorRef.trim().isNotEmpty ? item.doorRef.trim() : 'Opening';
      unawaited(
        _ref
            .read(workflowEventDispatcherProvider)
            .dispatchInstallationWorkflowEvent(
              survey: survey,
              item: item,
              notificationType: 'completion_evidence_uploaded',
              title:
                  '${_workspace == InspectionWorkspace.fireStopping ? 'Fire Stopping' : 'Fire Door'}: completion evidence uploaded for $opening',
              body: 'The worker uploaded installation or handover evidence.',
              toManagers: true,
              requiresAction: false,
            ),
      );
    }
  }

  void setInstallationPhotos({
    required String surveyId,
    required String itemId,
    required List<InstallationPhoto> photos,
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) => item.copyWith(installationPhotos: photos),
    );
  }

  void addInstallationManagerApprovalPhotos({
    required String surveyId,
    required String itemId,
    required List<InstallationPhoto> photos,
  }) {
    if (photos.isEmpty) return;
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) => item.copyWith(
        managerApprovalPhotos: [...item.managerApprovalPhotos, ...photos],
      ),
    );
  }

  void setInstallationManagerApprovalPhotos({
    required String surveyId,
    required String itemId,
    required List<InstallationPhoto> photos,
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) => item.copyWith(managerApprovalPhotos: photos),
    );
  }

  void addInstallationManagerRejectionPhotos({
    required String surveyId,
    required String itemId,
    required List<InstallationPhoto> photos,
  }) {
    if (photos.isEmpty) return;
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) => item.copyWith(
        managerRejectionPhotos: [...item.managerRejectionPhotos, ...photos],
      ),
    );
  }

  void setInstallationManagerRejectionPhotos({
    required String surveyId,
    required String itemId,
    required List<InstallationPhoto> photos,
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) => item.copyWith(managerRejectionPhotos: photos),
    );
  }

  bool canSubmitInstallationItem({
    required String surveyId,
    required String itemId,
  }) {
    final item = getPreInstallItem(surveyId: surveyId, itemId: itemId);
    if (item == null) return false;
    return item.installationPhotos.length >= minimumInstallationPhotoCount;
  }

  void markInstallationInProgress({
    required String surveyId,
    required String itemId,
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) {
        if (item.status == InstallationStatus.forApproval ||
            item.status == InstallationStatus.approved) {
          return item;
        }
        return item.copyWith(status: InstallationStatus.inProgress);
      },
    );
  }

  void submitInstallationForApproval({
    required String surveyId,
    required String itemId,
    required String completedBy,
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) {
        final now = DateTime.now();
        return item.copyWith(
          status: InstallationStatus.forApproval,
          completedBy: completedBy,
          completedDate: now,
          submittedBy: completedBy,
          submittedAt: now,
          approvedBy: '',
          clearApprovedAt: true,
          rejectedBy: '',
          clearRejectedAt: true,
          rejectionNote: '',
          rejectionReason: '',
          managerRejectionPhotos: const [],
        );
      },
    );
    unawaited(
        flushLocalPersistenceNow(reason: 'submit_installation_for_approval'));

    final survey = getById(surveyId);
    final item = getPreInstallItem(surveyId: surveyId, itemId: itemId);
    if (survey != null && item != null) {
      final opening =
          item.doorRef.trim().isNotEmpty ? item.doorRef.trim() : 'Opening';
      unawaited(
        _ref
            .read(workflowEventDispatcherProvider)
            .dispatchInstallationWorkflowEvent(
              survey: survey,
              item: item,
              notificationType: 'installation_handover_evidence_submitted',
              title:
                  '${_workspace == InspectionWorkspace.fireStopping ? 'Fire Stopping' : 'Fire Door'}: $opening submitted for approval',
              body: '$completedBy submitted installation or handover evidence.',
              toManagers: true,
              requiresAction: true,
            ),
      );
    }
  }

  void approveInstallationItem({
    required String surveyId,
    required String itemId,
    required String approvedBy,
    String comment = '',
    String signatureMethod = 'none',
    List<int> signatureImageBytes = const [],
    String approvedMaintainerNumber = '',
    String approvedMaintainerName = '',
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) {
        final now = DateTime.now();
        return item.copyWith(
          status: InstallationStatus.approved,
          approvedBy: approvedBy,
          approvedAt: now,
          rejectedBy: '',
          clearRejectedAt: true,
          rejectionNote: '',
          managerRejectionPhotos: const [],
          approval: InstallationApproval(
            projectId: surveyId,
            itemId: itemId,
            approvedBy: approvedBy,
            approvedDate: now,
            decision: 'approved',
            comment: comment,
            signatureMethod: signatureMethod,
            signatureImageBytes: signatureImageBytes,
            approvedMaintainerNumber: approvedMaintainerNumber,
            approvedMaintainerName: approvedMaintainerName,
          ),
          rejectionReason: '',
        );
      },
    );
    unawaited(flushLocalPersistenceNow(reason: 'approve_installation_item'));

    final survey = getById(surveyId);
    final item = getPreInstallItem(surveyId: surveyId, itemId: itemId);
    if (survey != null && item != null) {
      final opening =
          item.doorRef.trim().isNotEmpty ? item.doorRef.trim() : 'Opening';
      unawaited(
        _ref
            .read(workflowEventDispatcherProvider)
            .dispatchInstallationWorkflowEvent(
              survey: survey,
              item: item,
              notificationType: 'item_approved',
              title:
                  '${_workspace == InspectionWorkspace.fireStopping ? 'Fire Stopping' : 'Fire Door'}: $opening approved',
              body:
                  '$approvedBy approved the submitted installation or handover task.',
              toManagers: false,
              requiresAction: false,
            ),
      );
    }
  }

  void rejectInstallationItem({
    required String surveyId,
    required String itemId,
    required String approvedBy,
    required String rejectionReason,
    String signatureMethod = 'none',
    List<int> signatureImageBytes = const [],
    String approvedMaintainerNumber = '',
    String approvedMaintainerName = '',
  }) {
    updatePreInstallItem(
      surveyId: surveyId,
      itemId: itemId,
      update: (item) {
        final now = DateTime.now();
        return item.copyWith(
          status: InstallationStatus.rejectedNeedsRework,
          rejectedBy: approvedBy,
          rejectedAt: now,
          rejectionNote: rejectionReason,
          approvedBy: '',
          clearApprovedAt: true,
          approval: InstallationApproval(
            projectId: surveyId,
            itemId: itemId,
            approvedBy: approvedBy,
            approvedDate: now,
            decision: 'rejected',
            comment: rejectionReason,
            signatureMethod: signatureMethod,
            signatureImageBytes: signatureImageBytes,
            approvedMaintainerNumber: approvedMaintainerNumber,
            approvedMaintainerName: approvedMaintainerName,
          ),
          rejectionReason: rejectionReason,
          managerApprovalPhotos: const [],
        );
      },
    );
    unawaited(flushLocalPersistenceNow(reason: 'reject_installation_item'));

    final survey = getById(surveyId);
    final item = getPreInstallItem(surveyId: surveyId, itemId: itemId);
    if (survey != null && item != null) {
      final opening =
          item.doorRef.trim().isNotEmpty ? item.doorRef.trim() : 'Opening';
      unawaited(
        _ref
            .read(workflowEventDispatcherProvider)
            .dispatchInstallationWorkflowEvent(
              survey: survey,
              item: item,
              notificationType: 'item_rejected_needs_update',
              title:
                  '${_workspace == InspectionWorkspace.fireStopping ? 'Fire Stopping' : 'Fire Door'}: $opening needs update',
              body:
                  '$approvedBy rejected the submitted installation or handover task.',
              toManagers: false,
              requiresAction: true,
            ),
      );
    }
  }

  void setInspectionComment({
    required String surveyId,
    required String doorId,
    required InspectionCheckId checkId,
    required String comment,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final current = _getOrInitResult(d, checkId);
        final nextResult = current.copyWith(comment: comment);

        final nextInspection =
            Map<String, InspectionCheckResult>.from(d.inspectionResults);
        nextInspection[checkId.name] = nextResult;

        final nextIssues = _syncIssueForCheck(
          issues: d.issues,
          checkId: checkId,
          result: nextResult,
        );

        return d.copyWith(
            inspectionResults: nextInspection, issues: nextIssues);
      },
    );
  }

  void setInspectionRecommendedAction({
    required String surveyId,
    required String doorId,
    required InspectionCheckId checkId,
    required String recommendedAction,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final current = _getOrInitResult(d, checkId);
        final nextResult =
            current.copyWith(recommendedAction: recommendedAction);

        final nextInspection =
            Map<String, InspectionCheckResult>.from(d.inspectionResults);
        nextInspection[checkId.name] = nextResult;

        final nextIssues = _syncIssueForCheck(
          issues: d.issues,
          checkId: checkId,
          result: nextResult,
        );

        return d.copyWith(
            inspectionResults: nextInspection, issues: nextIssues);
      },
    );
  }

  /// Stores structured ART action selections and regenerates the
  /// recommended action text.  The [generatedRecommendedAction] is
  /// written to the [recommendedAction] text field so the user can
  /// still freely edit it afterwards.
  void setInspectionStructuredActions({
    required String surveyId,
    required String doorId,
    required InspectionCheckId checkId,
    required List<String> selectedActionCodes,
    required List<Map<String, String?>> selectedActionMappings,
    required String customActionText,
    required String generatedRecommendedAction,
    String? optionalVideoPath,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final current = _getOrInitResult(d, checkId);
        final nextResult = current.copyWith(
          selectedActionCodes: selectedActionCodes,
          selectedActionMappings: selectedActionMappings,
          customActionText: customActionText,
          recommendedAction: generatedRecommendedAction,
          optionalVideoPath: optionalVideoPath ?? current.optionalVideoPath,
        );

        final nextInspection =
            Map<String, InspectionCheckResult>.from(d.inspectionResults);
        nextInspection[checkId.name] = nextResult;

        final nextIssues = _syncIssueForCheck(
          issues: d.issues,
          checkId: checkId,
          result: nextResult,
        );

        return d.copyWith(
            inspectionResults: nextInspection, issues: nextIssues);
      },
    );
  }

  void addInspectionPhotos({
    required String surveyId,
    required String doorId,
    required InspectionCheckId checkId,
    required List<PhotoAttachment> photos,
  }) {
    if (photos.isEmpty) return;

    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final current = _getOrInitResult(d, checkId);
        final normalized = [
          ...photos.map(
            (p) => PhotoAttachment(
              id: p.id,
              fileName: p.fileName,
              mimeType: p.mimeType,
              bytes: p.bytes,
              capturedAt: p.capturedAt,
              surveyId: p.surveyId.isEmpty ? surveyId : p.surveyId,
              doorId: p.doorId.isEmpty ? doorId : p.doorId,
              issueId: p.issueId.isEmpty ? checkId.name : p.issueId,
            ),
          ),
        ];
        final nextResult =
            current.copyWith(photos: [...current.photos, ...normalized]);

        final nextInspection =
            Map<String, InspectionCheckResult>.from(d.inspectionResults);
        nextInspection[checkId.name] = nextResult;

        final nextIssues = _syncIssueForCheck(
          issues: d.issues,
          checkId: checkId,
          result: nextResult,
        );

        return d.copyWith(
          inspectionResults: nextInspection,
          issues: nextIssues,
          remedialItems: _syncRemedialItems(
            surveyId: surveyId,
            doorId: doorId,
            issues: nextIssues,
            existing: d.remedialItems,
          ),
        );
      },
    );
  }

  /// Replace the entire photo list for a single inspection check (used for photo deletion).
  void setInspectionPhotos({
    required String surveyId,
    required String doorId,
    required InspectionCheckId checkId,
    required List<PhotoAttachment> photos,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final current = _getOrInitResult(d, checkId);
        final normalized = [
          ...photos.map(
            (p) => PhotoAttachment(
              id: p.id,
              fileName: p.fileName,
              mimeType: p.mimeType,
              bytes: p.bytes,
              capturedAt: p.capturedAt,
              surveyId: p.surveyId.isEmpty ? surveyId : p.surveyId,
              doorId: p.doorId.isEmpty ? doorId : p.doorId,
              issueId: p.issueId.isEmpty ? checkId.name : p.issueId,
            ),
          ),
        ];
        final nextResult = current.copyWith(photos: normalized);

        final nextInspection =
            Map<String, InspectionCheckResult>.from(d.inspectionResults);
        nextInspection[checkId.name] = nextResult;

        final nextIssues = _syncIssueForCheck(
          issues: d.issues,
          checkId: checkId,
          result: nextResult,
        );

        return d.copyWith(
          inspectionResults: nextInspection,
          issues: nextIssues,
          remedialItems: _syncRemedialItems(
            surveyId: surveyId,
            doorId: doorId,
            issues: nextIssues,
            existing: d.remedialItems,
          ),
        );
      },
    );
  }

  void setInspectionGaps({
    required String surveyId,
    required String doorId,
    required InspectionCheckId checkId,
    required double? topMm,
    required double? bottomMm,
    required double? leftMm,
    required double? rightMm,
    double? meetingMm,
  }) {
    updateDoor(
      surveyId: surveyId,
      doorId: doorId,
      update: (d) {
        final current = _getOrInitResult(d, checkId);

        final nextResult = current.copyWith(
          gapTopMm: topMm,
          gapBottomMm: bottomMm,
          gapLeftMm: leftMm,
          gapRightMm: rightMm,
          gapMeetingMm: meetingMm,
        );

        final nextInspection =
            Map<String, InspectionCheckResult>.from(d.inspectionResults);
        nextInspection[checkId.name] = nextResult;

        final nextIssues = _syncIssueForCheck(
          issues: d.issues,
          checkId: checkId,
          result: nextResult,
        );

        return d.copyWith(
            inspectionResults: nextInspection, issues: nextIssues);
      },
    );
  }

  List<Issue> _syncIssueForCheck({
    required List<Issue> issues,
    required InspectionCheckId checkId,
    required InspectionCheckResult result,
  }) {
    final key = _sourceKeyForCheck(checkId);

    final shouldHaveIssue = result.outcome == InspectionOutcome.fail ||
        result.outcome == InspectionOutcome.criticalFail;
    if (!shouldHaveIssue) {
      return issues.where((i) => i.sourceKey != key).toList();
    }

    final art = _resolvedIssueArtCode(checkId: checkId, result: result);
    final severity = (result.outcome == InspectionOutcome.criticalFail)
        ? IssueSeverity.criticalFail
        : IssueSeverity.fail;

    final def = checkDef(checkId);
    final comment =
        result.comment.trim().isEmpty ? def.title : result.comment.trim();

    double? top =
        checkId == InspectionCheckId.doorGapsIncorrect ? result.gapTopMm : null;
    double? bottom = checkId == InspectionCheckId.doorGapsIncorrect
        ? result.gapBottomMm
        : null;
    double? left = checkId == InspectionCheckId.doorGapsIncorrect
        ? result.gapLeftMm
        : null;
    double? right = checkId == InspectionCheckId.doorGapsIncorrect
        ? result.gapRightMm
        : null;

    final next = <Issue>[];
    var replaced = false;

    for (final i in issues) {
      if (i.sourceKey == key) {
        next.add(
          Issue(
            id: i.id,
            artCode: art,
            severity: severity,
            comment: comment,
            actionMappings: result.selectedActionMappings,
            photos: result.photos,
            gapTopMm: top,
            gapBottomMm: bottom,
            gapLeftMm: left,
            gapRightMm: right,
            sourceKey: key,
          ),
        );
        replaced = true;
      } else {
        next.add(i);
      }
    }

    if (!replaced) {
      next.add(
        Issue(
          artCode: art,
          severity: severity,
          comment: comment,
          actionMappings: result.selectedActionMappings,
          photos: result.photos,
          gapTopMm: top,
          gapBottomMm: bottom,
          gapLeftMm: left,
          gapRightMm: right,
          sourceKey: key,
        ),
      );
    }

    return next;
  }

  int _resolvedIssueArtCode({
    required InspectionCheckId checkId,
    required InspectionCheckResult result,
  }) {
    for (final mapping in result.selectedActionMappings) {
      final actual = (mapping['actualArtCode'] ?? '').trim();
      final ui = (mapping['uiCode'] ?? '').trim();
      final candidate = actual.isNotEmpty ? actual : ui;
      if (candidate.isEmpty) {
        continue;
      }
      final m =
          RegExp(r'ART(\d{2})', caseSensitive: false).firstMatch(candidate);
      if (m != null) {
        return int.tryParse(m.group(1) ?? '') ?? 0;
      }
    }

    return autoArtCodeForOutcome(checkId: checkId, outcome: result.outcome) ??
        0;
  }

  Survey? _surveyById(String surveyId) {
    for (final survey in state.surveys) {
      if (survey.id == surveyId) {
        return survey;
      }
    }
    return null;
  }

  ProjectDrawing? _drawingById(Survey survey, String drawingId) {
    for (final drawing in survey.projectDrawings) {
      if (drawing.id == drawingId) {
        return drawing;
      }
    }
    return null;
  }

  bool _surveyContainsDrawing(Survey survey, String drawingId) {
    return _drawingById(survey, drawingId) != null;
  }

  bool _pinsEqual(List<FloorPlanPin> a, List<FloorPlanPin> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.drawingId != right.drawingId ||
          left.page != right.page ||
          left.x != right.x ||
          left.y != right.y ||
          left.doorNumber != right.doorNumber ||
          left.label != right.label ||
          left.doorId != right.doorId) {
        return false;
      }
    }
    return true;
  }

  bool _seedPinsIfMissing({
    required String surveyId,
    required String drawingId,
    required List<FloorPlanPin> fallback,
  }) {
    if (fallback.isEmpty) return false;
    final surveyPins = _pinsBySurveyDrawing.putIfAbsent(surveyId, () => {});
    if (surveyPins.containsKey(drawingId)) return false;
    surveyPins[drawingId] = List<FloorPlanPin>.from(fallback);
    return true;
  }

  void _setDrawingPins({
    required String surveyId,
    required String drawingId,
    required List<FloorPlanPin> pins,
  }) {
    final surveyPins = _pinsBySurveyDrawing.putIfAbsent(surveyId, () => {});
    surveyPins[drawingId] = List<FloorPlanPin>.from(pins);
  }

  void _markPinsChanged({required String reason}) {
    _ref.read(surveyDrawingPinsRevisionProvider(_workspace).notifier).state +=
        1;
    _schedulePinsPersist(reason: reason);
  }

  Survey _mergeSurveyPins(Survey survey) {
    final surveyPins = _pinsBySurveyDrawing[survey.id];
    if (surveyPins == null || surveyPins.isEmpty) return survey;

    var changed = false;
    final mergedDrawings = survey.projectDrawings.map((drawing) {
      final pins = surveyPins[drawing.id];
      if (pins == null) {
        return drawing;
      }
      changed = true;
      return drawing.copyWith(pins: List<FloorPlanPin>.from(pins));
    }).toList();

    if (!changed) return survey;
    return survey.copyWith(projectDrawings: mergedDrawings);
  }

  Future<void> _restorePinsState(
      {required Box box, required List<Survey> restoredSurveys}) async {
    _pinsBySurveyDrawing.clear();
    final raw = box.get(_pinStateKey);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final surveyEntry in decoded.entries) {
            final perDrawingRaw = surveyEntry.value;
            if (perDrawingRaw is! Map) continue;

            final perDrawing = <String, List<FloorPlanPin>>{};
            for (final drawingEntry in perDrawingRaw.entries) {
              final drawingId = drawingEntry.key.toString();
              final pinsRaw = drawingEntry.value;
              if (pinsRaw is! List) continue;
              final pins = pinsRaw
                  .whereType<Map>()
                  .map(
                      (e) => _floorPlanPinFromMap(Map<String, dynamic>.from(e)))
                  .toList();
              if (pins.isNotEmpty) {
                perDrawing[drawingId] = pins;
              }
            }

            if (perDrawing.isNotEmpty) {
              _pinsBySurveyDrawing[surveyEntry.key] = perDrawing;
            }
          }
        }
      } catch (_) {
        // Fall back to seeded legacy pins from drawing payload.
      }
    }

    if (_pinsBySurveyDrawing.isEmpty) {
      for (final survey in restoredSurveys) {
        final perDrawing = <String, List<FloorPlanPin>>{};
        for (final drawing in survey.projectDrawings) {
          if (drawing.pins.isNotEmpty) {
            perDrawing[drawing.id] = List<FloorPlanPin>.from(drawing.pins);
          }
        }
        if (perDrawing.isNotEmpty) {
          _pinsBySurveyDrawing[survey.id] = perDrawing;
        }
      }
    }
  }

  void _schedulePinsPersist({required String reason}) {
    _pinsPersistDebounceTimer?.cancel();
    if (kDebugMode) {
      debugPrint(
          'survey_pins_persist_scheduled workspace=${_workspace.name} reason=$reason');
    }
    _pinsPersistDebounceTimer = Timer(_pinsPersistDebounceDelay, () {
      unawaited(_persistPinsState(reason: 'debounced_$reason'));
    });
  }

  Future<void> _persistPinsState(
      {required String reason, bool force = false}) async {
    if (!force) {
      _pinsPersistDebounceTimer?.cancel();
      _pinsPersistDebounceTimer = null;
    }

    try {
      final box = await Hive.openBox(_namespacedBoxName);
      final payload = <String, Map<String, List<Map<String, dynamic>>>>{};
      for (final surveyEntry in _pinsBySurveyDrawing.entries) {
        final surveyPayload = <String, List<Map<String, dynamic>>>{};
        for (final drawingEntry in surveyEntry.value.entries) {
          surveyPayload[drawingEntry.key] =
              drawingEntry.value.map(_floorPlanPinToMap).toList();
        }
        payload[surveyEntry.key] = surveyPayload;
      }
      await box.put(_pinStateKey, jsonEncode(payload));
      if (kDebugMode) {
        debugPrint(
            'survey_pins_persist workspace=${_workspace.name} reason=$reason surveys=${payload.length}');
      }
    } catch (_) {
      // Ignore local persistence failures.
    }
  }

  Future<void> _restoreState() async {
    try {
      final box = await Hive.openBox(_namespacedBoxName);
      dynamic raw = box.get(_storageStateKey);
      if (raw is! String || raw.trim().isEmpty) {
        raw = await _readLegacyStateAndMigrateIfNeeded(targetBox: box);
      }
      if (raw is! String || raw.trim().isEmpty) {
        if (kDebugMode) {
          debugPrint(
              'survey_restore workspace=${_workspace.name} state=empty box=$_namespacedBoxName');
        }
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        if (kDebugMode) {
          debugPrint(
              'survey_restore workspace=${_workspace.name} error=invalid_json_root');
        }
        return;
      }

      final items = decoded['surveys'];
      if (items is! List) {
        if (kDebugMode) {
          debugPrint(
              'survey_restore workspace=${_workspace.name} error=missing_surveys_list');
        }
        return;
      }

      _isHydrating = true;
      final restoredSurveys = items
          .whereType<Map>()
          .map((e) => _surveyFromMap(Map<String, dynamic>.from(e)))
          .toList();
      final storedLastGenerated =
          (decoded['lastGeneratedJobNumber'] as num?)?.toInt() ?? 0;
      state = SurveyState(
        surveys: restoredSurveys,
        lastGeneratedJobNumber: storedLastGenerated > 0
            ? storedLastGenerated
            : _highestGeneratedJobNumber(restoredSurveys),
      );
      await _restorePinsState(box: box, restoredSurveys: restoredSurveys);
      _isHydrating = false;
      if (kDebugMode) {
        debugPrint(
            'survey_restore workspace=${_workspace.name} surveys=${restoredSurveys.length} box=$_namespacedBoxName');
      }
    } catch (e) {
      _isHydrating = false;
      if (kDebugMode) {
        debugPrint('survey_restore workspace=${_workspace.name} error=$e');
      }
    } finally {
      // Always start the Firestore realtime listener so data from other
      // devices is merged — even on a fresh install with no local Hive data.
      _startFirestoreListener();
    }
  }

  Future<String?> _readLegacyStateAndMigrateIfNeeded(
      {required Box targetBox}) async {
    if (targetBox.name == _legacyBoxName) return null;

    try {
      final legacyBox = await Hive.openBox(_legacyBoxName);
      final raw = legacyBox.get(_storageStateKey);
      if (raw is! String || raw.trim().isEmpty) return null;

      await targetBox.put(_storageStateKey, raw);
      return raw;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistState() async {
    try {
      final box = await Hive.openBox(_namespacedBoxName);
      final payload = {
        'surveys': state.surveys.map(_surveyToMap).toList(),
        'lastGeneratedJobNumber': state.lastGeneratedJobNumber,
      };
      await box.put(_storageStateKey, jsonEncode(payload));
      if (kDebugMode) {
        debugPrint(
            'survey_persist workspace=${_workspace.name} surveys=${state.surveys.length} box=$_namespacedBoxName');
      }
    } catch (_) {
      // Ignore persistence failures in local mode.
    }
    // Write modified surveys to Firestore (non-blocking, best-effort).
    unawaited(_syncDirtyToFirestore());
  }

  void _schedulePersist({required String reason}) {
    _coalescedPersistUpdates += 1;
    final pending = _coalescedPersistUpdates;
    _persistDebounceTimer?.cancel();

    if (kDebugMode) {
      debugPrint(
        'survey_persist_scheduled workspace=${_workspace.name} reason=$reason delayMs=${_persistDebounceDelay.inMilliseconds} pendingUpdates=$pending',
      );
    }

    _persistDebounceTimer = Timer(_persistDebounceDelay, () {
      unawaited(_runPersistNow(reason: 'debounced_$reason'));
    });
  }

  int _estimatePersistPayloadSizeBytes() {
    try {
      final payload = {
        'surveys': state.surveys.map(_surveyToMap).toList(),
        'lastGeneratedJobNumber': state.lastGeneratedJobNumber,
      };
      return utf8.encode(jsonEncode(payload)).length;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _runPersistNow(
      {required String reason, bool force = false}) async {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = null;

    final coalesced = _coalescedPersistUpdates;
    _coalescedPersistUpdates = 0;

    if (!force && coalesced == 0) {
      return;
    }

    final approxBytes = _estimatePersistPayloadSizeBytes();
    if (kDebugMode) {
      debugPrint(
        'survey_persist_run workspace=${_workspace.name} reason=$reason coalescedUpdates=$coalesced approxBytes=$approxBytes surveys=${state.surveys.length}',
      );
    }

    await _persistState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
          flushLocalPersistenceNow(reason: 'app_lifecycle_${state.name}'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistDebounceTimer?.cancel();
    _pinsPersistDebounceTimer?.cancel();
    _firestoreSubscription?.cancel();
    unawaited(_runPersistNow(reason: 'controller_dispose', force: true));
    unawaited(_persistPinsState(reason: 'controller_dispose', force: true));
    super.dispose();
  }

  Survey _surveyFromMap(Map<String, dynamic> m) {
    final typeName = m['type'] as String? ?? SurveyType.survey.name;
    final parsedType = SurveyType.values
        .firstWhere((e) => e.name == typeName, orElse: () => SurveyType.survey);
    final workspaceName = m['workspace'] as String?;
    final parsedWorkspace = InspectionWorkspace.values.firstWhere(
      (e) => e.name == workspaceName,
      orElse: () {
        if (parsedType == SurveyType.fireStopping) {
          return InspectionWorkspace.fireStopping;
        }
        if (parsedType == SurveyType.snagging) {
          return InspectionWorkspace.snagging;
        }
        return InspectionWorkspace.fireDoor;
      },
    );
    final survey = Survey(
      id: m['id'] as String?,
      companyId: m['companyId'] as String? ?? '',
      type: parsedType,
      workspace: parsedWorkspace,
      createdAt: DateTime.tryParse(m['createdAt'] as String? ?? ''),
      reportDate: DateTime.tryParse(m['reportDate'] as String? ?? ''),
      siteName: m['siteName'] as String? ?? '',
      siteAddress: m['siteAddress'] as String? ?? '',
      reference: m['reference'] as String? ?? '',
      registerReference: m['registerReference'] as String? ?? '',
      reportName: m['reportName'] as String? ?? '',
      addressLine1: m['addressLine1'] as String? ?? '',
      addressLine2: m['addressLine2'] as String? ?? '',
      cityTown: m['cityTown'] as String? ?? '',
      postCode: m['postCode'] as String? ?? '',
      reportCompletedBy: m['reportCompletedBy'] as String? ?? '',
      clientName: m['clientName'] as String? ?? '',
      clientEmail: m['clientEmail'] as String? ?? '',
      clientPhone: m['clientPhone'] as String? ?? '',
      disclaimerAcceptedAt:
          DateTime.tryParse(m['disclaimerAcceptedAt'] as String? ?? ''),
      disclaimerAcceptedBy: m['disclaimerAcceptedBy'] as String? ?? '',
      disclaimerAcceptance: m['disclaimerAcceptance'] is Map
          ? DisclaimerAcceptanceRecord.fromMap(
              Map<String, dynamic>.from(m['disclaimerAcceptance'] as Map))
          : null,
      assignedGroupIds: (m['assignedGroupIds'] as List? ?? const [])
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      isArchived: m['isArchived'] as bool? ?? false,
      archivedAt: DateTime.tryParse(m['archivedAt'] as String? ?? ''),
      archivedBy: m['archivedBy'] as String? ?? '',
      restoredAt: DateTime.tryParse(m['restoredAt'] as String? ?? ''),
      restoredBy: m['restoredBy'] as String? ?? '',
      projectDrawings: (m['projectDrawings'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _projectDrawingFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      doors: (m['doors'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _doorFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      preInstallItems: (m['preInstallItems'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _preInstallItemFromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
    return _syncReplacementInstallationItemsForSurvey(survey);
  }

  Map<String, dynamic> _surveyToMap(Survey s) {
    return {
      'id': s.id,
      'companyId': s.companyId,
      'type': s.type.name,
      'workspace': s.workspace.name,
      'createdAt': s.createdAt.toIso8601String(),
      'reportDate': s.reportDate.toIso8601String(),
      'siteName': s.siteName,
      'siteAddress': s.siteAddress,
      'reference': s.reference,
      'registerReference': s.registerReference,
      'reportName': s.reportName,
      'addressLine1': s.addressLine1,
      'addressLine2': s.addressLine2,
      'cityTown': s.cityTown,
      'postCode': s.postCode,
      'reportCompletedBy': s.reportCompletedBy,
      'clientName': s.clientName,
      'clientEmail': s.clientEmail,
      'clientPhone': s.clientPhone,
      'disclaimerAcceptedAt': s.disclaimerAcceptedAt?.toIso8601String(),
      'disclaimerAcceptedBy': s.disclaimerAcceptedBy,
      'disclaimerAcceptance':
          s.disclaimerAcceptance?.toMap(includeSignatureBytes: true),
      'assignedGroupIds': s.assignedGroupIds,
      'isArchived': s.isArchived,
      'archivedAt': s.archivedAt?.toIso8601String(),
      'archivedBy': s.archivedBy,
      'restoredAt': s.restoredAt?.toIso8601String(),
      'restoredBy': s.restoredBy,
      'projectDrawings': s.projectDrawings.map(_projectDrawingToMap).toList(),
      'doors': s.doors.map(_doorToMap).toList(),
      'preInstallItems': s.preInstallItems.map(_preInstallItemToMap).toList(),
    };
  }

  int _highestGeneratedJobNumber(List<Survey> surveys) {
    var highest = 0;
    for (final survey in surveys) {
      final parsed = _parseGeneratedJobNumber(survey.reference);
      if (parsed != null && parsed > highest) {
        highest = parsed;
      }
    }
    return highest;
  }

  int? _parseGeneratedJobNumber(String value) {
    final match = RegExp(r'^J-(\d{4,})$').firstMatch(value.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String _formatJobNumber(int value) {
    return 'J-${value.toString().padLeft(4, '0')}';
  }

  ProjectDrawing _projectDrawingFromMap(Map<String, dynamic> m) =>
      ProjectDrawing(
        id: m['id'] as String?,
        name: (m['name'] as String? ?? (m['fileName'] as String? ?? '')).trim(),
        fileName: m['fileName'] as String? ?? '',
        mimeType: m['mimeType'] as String? ?? 'application/octet-stream',
        level: m['level'] as String? ?? '',
        description: m['description'] as String? ?? '',
        bytes: (m['bytes'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        cloudStoragePath: m['cloudStoragePath'] as String? ?? '',
        cloudDownloadUrl: m['cloudDownloadUrl'] as String? ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? ''),
        pins: (m['pins'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => _floorPlanPinFromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> _projectDrawingToMap(ProjectDrawing d) => {
        'id': d.id,
        'name': d.name,
        'fileName': d.fileName,
        'mimeType': d.mimeType,
        'level': d.level,
        'description': d.description,
        'bytes': d.bytes,
        'cloudStoragePath': d.cloudStoragePath,
        'cloudDownloadUrl': d.cloudDownloadUrl,
        'createdAt': d.createdAt.toIso8601String(),
        'pins': d.pins.map(_floorPlanPinToMap).toList(),
      };

  FloorPlanPin _floorPlanPinFromMap(Map<String, dynamic> m) => FloorPlanPin(
        id: m['id'] as String?,
        drawingId: m['drawingId'] as String? ?? '',
        page: (m['page'] as num?)?.toInt() ?? 1,
        x: (m['x'] as num?)?.toDouble() ?? 0.0,
        y: (m['y'] as num?)?.toDouble() ?? 0.0,
        doorNumber: m['doorNumber'] as String? ?? '',
        label: m['label'] as String? ?? '',
        doorId: m['doorId'] as String? ?? '',
      );

  Map<String, dynamic> _floorPlanPinToMap(FloorPlanPin p) => {
        'id': p.id,
        'drawingId': p.drawingId,
        'page': p.page,
        'x': p.x,
        'y': p.y,
        'doorNumber': p.doorNumber,
        'label': p.label,
        'doorId': p.doorId,
      };

  Door _doorFromMap(Map<String, dynamic> m) {
    final rawMaterial = m['material'] as String? ?? '';
    final resolvedMaterial = rawMaterial == 'steel'
        ? DoorMaterial.metalDoor
        : DoorMaterial.values.firstWhere(
            (e) => e.name == rawMaterial,
            orElse: () => DoorMaterial.unknown,
          );

    final rawClassification = m['classification'] as String? ?? '';
    DoorClassification resolvedClassification;
    switch (rawClassification) {
      case 'manufacturerCertified':
        resolvedClassification =
            DoorClassification.manufacturerEvidenceAvailable;
        break;
      case 'notCertified':
        resolvedClassification =
            DoorClassification.noEvidenceClientStatedFireRated;
        break;
      case 'unknown':
        resolvedClassification = DoorClassification.unknownNotVerified;
        break;
      default:
        resolvedClassification = DoorClassification.values.firstWhere(
          (e) => e.name == rawClassification,
          orElse: () => DoorClassification.unknownNotVerified,
        );
    }

    return Door(
      id: m['id'] as String?,
      number: (m['number'] as num?)?.toInt() ?? 1,
      inspectionDate: DateTime.tryParse(m['inspectionDate'] as String? ?? ''),
      doorIdTag: m['doorIdTag'] as String? ?? '',
      floor: m['floor'] as String? ?? '',
      area: m['area'] as String? ?? '',
      doorType: DoorType.values.firstWhere(
          (e) => e.name == (m['doorType'] as String? ?? ''),
          orElse: () => DoorType.other),
      doorFunction: DoorFunction.values.firstWhere(
          (e) => e.name == (m['doorFunction'] as String? ?? ''),
          orElse: () => DoorFunction.unknown),
      material: resolvedMaterial,
      customMaterial: m['customMaterial'] as String? ?? '',
      classification: resolvedClassification,
      certificationBodyName: m['certificationBodyName'] as String? ?? '',
      fireRating: FireRating.values.firstWhere(
          (e) => e.name == (m['fireRating'] as String? ?? ''),
          orElse: () => FireRating.unknown),
      gradingLevel: GradingLevel.values.firstWhere(
          (e) => e.name == (m['gradingLevel'] as String? ?? ''),
          orElse: () => GradingLevel.level4),
      configuration: DoorConfiguration.values.firstWhere(
          (e) => e.name == (m['configuration'] as String? ?? ''),
          orElse: () => DoorConfiguration.singleLeaf),
      hasGlazing: m['hasGlazing'] as bool? ?? false,
      isFireExit: m['isFireExit'] as bool? ?? false,
      result: DoorResult.values.firstWhere(
          (e) => e.name == (m['result'] as String? ?? ''),
          orElse: () => DoorResult.unknown),
      remedialStatus: RemedialStatus.values.firstWhere(
          (e) => e.name == (m['remedialStatus'] as String? ?? ''),
          orElse: () => RemedialStatus.pending),
      approvedMaintainerName: m['approvedMaintainerName'] as String? ?? '',
      approvedMaintainerNumber: m['approvedMaintainerNumber'] as String? ?? '',
      approvedBy: m['approvedBy'] as String? ?? '',
      approvedAt: DateTime.tryParse(m['approvedAt'] as String? ?? ''),
      maintenanceIntervalMonths:
          ((m['maintenanceIntervalMonths'] as num?)?.toInt() ?? 12) > 0
              ? ((m['maintenanceIntervalMonths'] as num?)?.toInt() ?? 12)
              : 12,
      doorDrawingId: m['doorDrawingId'] as String? ?? '',
      doorPinId: m['doorPinId'] as String? ?? '',
      fireStoppingItemType: m['fireStoppingItemType'] as String? ?? '',
      fireStoppingFireRating: m['fireStoppingFireRating'] as String? ?? '',
      fireStoppingServiceType: m['fireStoppingServiceType'] as String? ?? '',
      fireStoppingSize: m['fireStoppingSize'] as String? ?? '',
      fireStoppingQuantity:
          ((m['fireStoppingQuantity'] as num?)?.toInt() ?? 1) > 0
              ? ((m['fireStoppingQuantity'] as num?)?.toInt() ?? 1)
              : 1,
      fireStoppingDefectDescription:
          m['fireStoppingDefectDescription'] as String? ?? '',
      fireStoppingRecommendedAction:
          m['fireStoppingRecommendedAction'] as String? ?? '',
      fireStoppingVideoUrl: m['fireStoppingVideoUrl'] as String? ?? '',
      fireStoppingDefects: (m['fireStoppingDefects'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _fireStoppingDefectFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      replacementRequired: m['replacementRequired'] as bool? ?? false,
      replacementDoor1Width: m['replacementDoor1Width'] as String? ?? '',
      replacementDoor1Height: m['replacementDoor1Height'] as String? ?? '',
      replacementDoor2Width: m['replacementDoor2Width'] as String? ?? '',
      replacementDoor2Height: m['replacementDoor2Height'] as String? ?? '',
      doorPhotos: (m['doorPhotos'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _photoFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      issues: (m['issues'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _issueFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      remedialItems: (m['remedialItems'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _remedialItemFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      inspectionResults: ((m['inspectionResults'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(
          key.toString(),
          _inspectionResultFromMap(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
  }

  Map<String, dynamic> _doorToMap(Door d) {
    return {
      'id': d.id,
      'number': d.number,
      'inspectionDate': d.inspectionDate.toIso8601String(),
      'doorIdTag': d.doorIdTag,
      'floor': d.floor,
      'area': d.area,
      'doorType': d.doorType.name,
      'doorFunction': d.doorFunction.name,
      'material': d.material.name,
      'customMaterial': d.customMaterial,
      'classification': d.classification.name,
      'certificationBodyName': d.certificationBodyName,
      'fireRating': d.fireRating.name,
      'gradingLevel': d.gradingLevel.name,
      'configuration': d.configuration.name,
      'hasGlazing': d.hasGlazing,
      'isFireExit': d.isFireExit,
      'result': d.result.name,
      'remedialStatus': d.remedialStatus.name,
      'approvedMaintainerName': d.approvedMaintainerName,
      'approvedMaintainerNumber': d.approvedMaintainerNumber,
      'approvedBy': d.approvedBy,
      'approvedAt': d.approvedAt?.toIso8601String(),
      'maintenanceIntervalMonths': d.maintenanceIntervalMonths,
      'doorDrawingId': d.doorDrawingId,
      'doorPinId': d.doorPinId,
      'fireStoppingItemType': d.fireStoppingItemType,
      'fireStoppingFireRating': d.fireStoppingFireRating,
      'fireStoppingServiceType': d.fireStoppingServiceType,
      'fireStoppingSize': d.fireStoppingSize,
      'fireStoppingQuantity': d.fireStoppingQuantity,
      'fireStoppingDefectDescription': d.fireStoppingDefectDescription,
      'fireStoppingRecommendedAction': d.fireStoppingRecommendedAction,
      'fireStoppingVideoUrl': d.fireStoppingVideoUrl,
      'fireStoppingDefects':
          d.fireStoppingDefects.map(_fireStoppingDefectToMap).toList(),
      'replacementRequired': d.replacementRequired,
      'replacementDoor1Width': d.replacementDoor1Width,
      'replacementDoor1Height': d.replacementDoor1Height,
      'replacementDoor2Width': d.replacementDoor2Width,
      'replacementDoor2Height': d.replacementDoor2Height,
      'doorPhotos': d.doorPhotos.map(_photoToMap).toList(),
      'issues': d.issues.map(_issueToMap).toList(),
      'remedialItems': d.remedialItems.map(_remedialItemToMap).toList(),
      'inspectionResults': d.inspectionResults
          .map((k, v) => MapEntry(k, _inspectionResultToMap(v))),
    };
  }

  /// Infer MIME type from file name if missing or incorrect
  String _inferMimeTypeFromFileName(String fileName) {
    if (fileName.isEmpty) return 'application/octet-stream';

    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      // Video formats
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/x-m4v';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      // Image formats
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      // Document formats
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  PhotoAttachment _photoFromMap(Map<String, dynamic> m) {
    final fileName = m['fileName'] as String? ?? '';
    final mimeType = m['mimeType'] as String? ?? '';

    // Infer MIME type from filename if missing
    final inferredMimeType =
        mimeType.isNotEmpty ? mimeType : _inferMimeTypeFromFileName(fileName);

    return PhotoAttachment(
      id: m['id'] as String?,
      fileName: fileName,
      mimeType: inferredMimeType,
      bytes: (m['bytes'] as List? ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      capturedAt: DateTime.tryParse(m['capturedAt'] as String? ?? ''),
      surveyId: m['surveyId'] as String? ?? '',
      doorId: m['doorId'] as String? ?? '',
      issueId: m['issueId'] as String? ?? '',
    );
  }

  Map<String, dynamic> _photoToMap(PhotoAttachment p) => {
        'id': p.id,
        'fileName': p.fileName,
        'mimeType': p.mimeType,
        'bytes': p.bytes,
        'capturedAt': p.capturedAt.toIso8601String(),
        'surveyId': p.surveyId,
        'doorId': p.doorId,
        'issueId': p.issueId,
      };

  Issue _issueFromMap(Map<String, dynamic> m) => Issue(
        id: m['id'] as String?,
        artCode: (m['artCode'] as num?)?.toInt() ?? 0,
        comment: m['comment'] as String? ?? '',
        actionMappings: (m['actionMappings'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (e) => {
                'sectionArtCode': e['sectionArtCode']?.toString(),
                'visibleLabel': e['visibleLabel']?.toString(),
                'uiCode': e['uiCode']?.toString(),
                'actualArtCode': e['actualArtCode']?.toString(),
                'actionText': e['actionText']?.toString(),
                'customText': e['customText']?.toString(),
              },
            )
            .toList(),
        severity: IssueSeverity.values.firstWhere(
            (e) => e.name == (m['severity'] as String? ?? ''),
            orElse: () => IssueSeverity.fail),
        gapLeftMm: (m['gapLeftMm'] as num?)?.toDouble(),
        gapRightMm: (m['gapRightMm'] as num?)?.toDouble(),
        gapTopMm: (m['gapTopMm'] as num?)?.toDouble(),
        gapBottomMm: (m['gapBottomMm'] as num?)?.toDouble(),
        gapMeetingMm: (m['gapMeetingMm'] as num?)?.toDouble(),
        photos: (m['photos'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => _photoFromMap(Map<String, dynamic>.from(e)))
            .toList(),
        sourceKey: m['sourceKey'] as String?,
      );

  Map<String, dynamic> _issueToMap(Issue i) => {
        'id': i.id,
        'artCode': i.artCode,
        'comment': i.comment,
        'actionMappings': i.actionMappings,
        'severity': i.severity.name,
        'gapLeftMm': i.gapLeftMm,
        'gapRightMm': i.gapRightMm,
        'gapTopMm': i.gapTopMm,
        'gapBottomMm': i.gapBottomMm,
        'gapMeetingMm': i.gapMeetingMm,
        'photos': i.photos.map(_photoToMap).toList(),
        'sourceKey': i.sourceKey,
      };

  FireStoppingDefect _fireStoppingDefectFromMap(Map<String, dynamic> m) =>
      FireStoppingDefect(
        id: m['id'] as String? ?? _uuid.v4(),
        template: m['template'] as String? ?? '',
        fireRating: m['fireRating'] as String? ?? '',
        serviceType: m['serviceType'] as String? ?? '',
        description: m['description'] as String? ?? '',
        recommendedAction: m['recommendedAction'] as String? ?? '',
        lengthMm: m['lengthMm'] as String? ?? '',
        widthMm: m['widthMm'] as String? ?? '',
        drawingId: m['drawingId'] as String? ?? '',
        pinId: m['pinId'] as String? ?? '',
        photos: (m['photos'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => _photoFromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> _fireStoppingDefectToMap(FireStoppingDefect d) => {
        'id': d.id,
        'template': d.template,
        'fireRating': d.fireRating,
        'serviceType': d.serviceType,
        'description': d.description,
        'recommendedAction': d.recommendedAction,
        'lengthMm': d.lengthMm,
        'widthMm': d.widthMm,
        'drawingId': d.drawingId,
        'pinId': d.pinId,
        'photos': d.photos.map(_photoToMap).toList(),
      };

  InspectionCheckResult _inspectionResultFromMap(Map<String, dynamic> m) =>
      InspectionCheckResult(
        outcome: InspectionOutcome.values.firstWhere(
            (e) => e.name == (m['outcome'] as String? ?? ''),
            orElse: () => InspectionOutcome.notAnswered),
        comment: m['comment'] as String? ?? '',
        recommendedAction: m['recommendedAction'] as String? ?? '',
        photos: (m['photos'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => _photoFromMap(Map<String, dynamic>.from(e)))
            .toList(),
        gapTopMm: (m['gapTopMm'] as num?)?.toDouble(),
        gapBottomMm: (m['gapBottomMm'] as num?)?.toDouble(),
        gapLeftMm: (m['gapLeftMm'] as num?)?.toDouble(),
        gapRightMm: (m['gapRightMm'] as num?)?.toDouble(),
        gapMeetingMm: (m['gapMeetingMm'] as num?)?.toDouble(),
        selectedActionCodes: (m['selectedActionCodes'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        selectedActionMappings:
            (m['selectedActionMappings'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (e) => {
                    'selectedLabel': e['selectedLabel']?.toString(),
                    'uiCode': e['uiCode']?.toString(),
                    'actualArtCode': e['actualArtCode']?.toString(),
                  },
                )
                .toList(),
        customActionText: m['customActionText'] as String? ?? '',
        optionalVideoPath: m['optionalVideoPath'] as String? ?? '',
      );

  Map<String, dynamic> _inspectionResultToMap(InspectionCheckResult r) => {
        'outcome': r.outcome.name,
        'comment': r.comment,
        'recommendedAction': r.recommendedAction,
        'photos': r.photos.map(_photoToMap).toList(),
        'gapTopMm': r.gapTopMm,
        'gapBottomMm': r.gapBottomMm,
        'gapLeftMm': r.gapLeftMm,
        'gapRightMm': r.gapRightMm,
        'gapMeetingMm': r.gapMeetingMm,
        'selectedActionCodes': r.selectedActionCodes,
        'selectedActionMappings': r.selectedActionMappings,
        'customActionText': r.customActionText,
        'optionalVideoPath': r.optionalVideoPath,
      };

  RemedialPhoto _remedialPhotoFromMap(Map<String, dynamic> m) => RemedialPhoto(
        id: m['id'] as String?,
        projectId: m['projectId'] as String? ?? '',
        doorId: m['doorId'] as String? ?? '',
        remedialItemId: m['remedialItemId'] as String? ?? '',
        issueId: m['issueId'] as String? ?? '',
        type: m['type'] as String? ?? 'afterRepair',
        fileName: m['fileName'] as String? ?? '',
        mimeType: m['mimeType'] as String? ?? '',
        bytes: (m['bytes'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? ''),
      );

  Map<String, dynamic> _remedialPhotoToMap(RemedialPhoto p) => {
        'id': p.id,
        'projectId': p.projectId,
        'doorId': p.doorId,
        'remedialItemId': p.remedialItemId,
        'issueId': p.issueId,
        'type': p.type,
        'fileName': p.fileName,
        'mimeType': p.mimeType,
        'bytes': p.bytes,
        'createdAt': p.createdAt.toIso8601String(),
      };

  Approval _approvalFromMap(Map<String, dynamic> m) => Approval(
        id: m['id'] as String?,
        projectId: m['projectId'] as String? ?? '',
        doorId: m['doorId'] as String? ?? '',
        moduleType: m['moduleType'] as String? ?? 'remedial',
        approvedBy: m['approvedBy'] as String? ?? '',
        approvedDate: DateTime.tryParse(m['approvedDate'] as String? ?? ''),
        decision: m['decision'] as String? ?? '',
        comment: m['comment'] as String? ?? '',
        maintenanceLabelFitted: m['maintenanceLabelFitted'] as bool?,
        nextMaintenanceDueDate:
            DateTime.tryParse(m['nextMaintenanceDueDate'] as String? ?? ''),
        finalManagerComments: m['finalManagerComments'] as String? ?? '',
        signatureAssetPath: m['signatureAssetPath'] as String? ?? '',
        signatureMethod: m['signatureMethod'] as String? ?? 'asset',
        signatureInitials: m['signatureInitials'] as String? ?? '',
        signatureImageBytes: (m['signatureImageBytes'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        approvedMaintainerName: m['approvedMaintainerName'] as String? ?? '',
        approvedMaintainerNumber:
            m['approvedMaintainerNumber'] as String? ?? '',
        certificateJobReferenceOverride:
            m['certificateJobReferenceOverride'] as String? ?? '',
      );

  Map<String, dynamic> _approvalToMap(Approval a) => {
        'id': a.id,
        'projectId': a.projectId,
        'doorId': a.doorId,
        'moduleType': a.moduleType,
        'approvedBy': a.approvedBy,
        'approvedDate': a.approvedDate.toIso8601String(),
        'decision': a.decision,
        'comment': a.comment,
        'maintenanceLabelFitted': a.maintenanceLabelFitted,
        'nextMaintenanceDueDate': a.nextMaintenanceDueDate?.toIso8601String(),
        'finalManagerComments': a.finalManagerComments,
        'signatureAssetPath': a.signatureAssetPath,
        'signatureMethod': a.signatureMethod,
        'signatureInitials': a.signatureInitials,
        'signatureImageBytes': a.signatureImageBytes,
        'approvedMaintainerName': a.approvedMaintainerName,
        'approvedMaintainerNumber': a.approvedMaintainerNumber,
        'certificateJobReferenceOverride': a.certificateJobReferenceOverride,
      };

  RemedialItem _remedialItemFromMap(Map<String, dynamic> m) => RemedialItem(
        id: m['id'] as String? ?? _uuid.v4(),
        projectId: m['projectId'] as String? ?? '',
        doorId: m['doorId'] as String? ?? '',
        issueId: m['issueId'] as String? ?? '',
        category: m['category'] as String? ?? '',
        title: m['title'] as String? ?? '',
        severity: m['severity'] as String? ?? '',
        originalComment: m['originalComment'] as String? ?? '',
        originalInspectionPhotos:
            (m['originalInspectionPhotos'] as List? ?? const [])
                .whereType<Map>()
                .map((e) => _photoFromMap(Map<String, dynamic>.from(e)))
                .toList(),
        recommendedAction: m['recommendedAction'] as String? ?? '',
        actionMappings: (m['actionMappings'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (e) => {
                'sectionArtCode': e['sectionArtCode']?.toString(),
                'visibleLabel': e['visibleLabel']?.toString(),
                'uiCode': e['uiCode']?.toString(),
                'actualArtCode': e['actualArtCode']?.toString(),
                'actionText': e['actionText']?.toString(),
                'customText': e['customText']?.toString(),
              },
            )
            .toList(),
        status: RemedialStatus.values.firstWhere(
            (e) => e.name == (m['status'] as String? ?? ''),
            orElse: () => RemedialStatus.pending),
        workerNote: m['workerNote'] as String? ?? '',
        completedBy: m['completedBy'] as String? ?? '',
        completedDate: DateTime.tryParse(m['completedDate'] as String? ?? ''),
        submittedBy: m['submittedBy'] as String? ?? '',
        submittedAt: DateTime.tryParse(m['submittedAt'] as String? ?? ''),
        approvedBy: m['approvedBy'] as String? ?? '',
        approvedAt: DateTime.tryParse(m['approvedAt'] as String? ?? ''),
        rejectedBy: m['rejectedBy'] as String? ?? '',
        rejectedAt: DateTime.tryParse(m['rejectedAt'] as String? ?? ''),
        rejectionNote: m['rejectionNote'] as String? ?? '',
        afterRepairPhotos: (m['afterRepairPhotos'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => _remedialPhotoFromMap(Map<String, dynamic>.from(e)))
            .toList(),
        managerApprovalPhotos: (m['managerApprovalPhotos'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => _remedialPhotoFromMap(Map<String, dynamic>.from(e)))
            .toList(),
        managerRejectionPhotos:
            (m['managerRejectionPhotos'] as List? ?? const [])
                .whereType<Map>()
                .map((e) => _remedialPhotoFromMap(Map<String, dynamic>.from(e)))
                .toList(),
        approval: m['approval'] is Map
            ? _approvalFromMap(Map<String, dynamic>.from(m['approval'] as Map))
            : null,
        managerRejectionNote: m['managerRejectionNote'] as String? ?? '',
      );

  Map<String, dynamic> _remedialItemToMap(RemedialItem r) => {
        'id': r.id,
        'projectId': r.projectId,
        'doorId': r.doorId,
        'issueId': r.issueId,
        'category': r.category,
        'title': r.title,
        'severity': r.severity,
        'originalComment': r.originalComment,
        'originalInspectionPhotos':
            r.originalInspectionPhotos.map(_photoToMap).toList(),
        'recommendedAction': r.recommendedAction,
        'actionMappings': r.actionMappings,
        'status': r.status.name,
        'workerNote': r.workerNote,
        'completedBy': r.completedBy,
        'completedDate': r.completedDate?.toIso8601String(),
        'submittedBy': r.submittedBy,
        'submittedAt': r.submittedAt?.toIso8601String(),
        'approvedBy': r.approvedBy,
        'approvedAt': r.approvedAt?.toIso8601String(),
        'rejectedBy': r.rejectedBy,
        'rejectedAt': r.rejectedAt?.toIso8601String(),
        'rejectionNote': r.rejectionNote,
        'afterRepairPhotos':
            r.afterRepairPhotos.map(_remedialPhotoToMap).toList(),
        'managerApprovalPhotos':
            r.managerApprovalPhotos.map(_remedialPhotoToMap).toList(),
        'managerRejectionPhotos':
            r.managerRejectionPhotos.map(_remedialPhotoToMap).toList(),
        'approval': r.approval == null ? null : _approvalToMap(r.approval!),
        'managerRejectionNote': r.managerRejectionNote,
      };

  PreInstallPhoto _preInstallPhotoFromMap(Map<String, dynamic> m) =>
      PreInstallPhoto(
        id: m['id'] as String?,
        projectId: m['projectId'] as String? ?? '',
        itemId: m['itemId'] as String? ?? '',
        type: m['type'] as String? ?? 'preInstall',
        fileName: m['fileName'] as String? ?? '',
        mimeType: m['mimeType'] as String? ?? '',
        bytes: (m['bytes'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        cloudStoragePath: m['cloudStoragePath'] as String? ?? '',
        cloudDownloadUrl: m['cloudDownloadUrl'] as String? ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? ''),
      );

  Map<String, dynamic> _preInstallPhotoToMap(PreInstallPhoto p) => {
        'id': p.id,
        'projectId': p.projectId,
        'itemId': p.itemId,
        'type': p.type,
        'fileName': p.fileName,
        'mimeType': p.mimeType,
        'bytes': p.bytes,
        'cloudStoragePath': p.cloudStoragePath,
        'cloudDownloadUrl': p.cloudDownloadUrl,
        'createdAt': p.createdAt.toIso8601String(),
      };

  InstallationPhoto _installationPhotoFromMap(Map<String, dynamic> m) =>
      InstallationPhoto(
        id: m['id'] as String?,
        projectId: m['projectId'] as String? ?? '',
        itemId: m['itemId'] as String? ?? '',
        type: m['type'] as String? ?? 'afterInstall',
        fileName: m['fileName'] as String? ?? '',
        mimeType: m['mimeType'] as String? ?? '',
        bytes: (m['bytes'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        cloudStoragePath: m['cloudStoragePath'] as String? ?? '',
        cloudDownloadUrl: m['cloudDownloadUrl'] as String? ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? ''),
      );

  Map<String, dynamic> _installationPhotoToMap(InstallationPhoto p) => {
        'id': p.id,
        'projectId': p.projectId,
        'itemId': p.itemId,
        'type': p.type,
        'fileName': p.fileName,
        'mimeType': p.mimeType,
        'bytes': p.bytes,
        'cloudStoragePath': p.cloudStoragePath,
        'cloudDownloadUrl': p.cloudDownloadUrl,
        'createdAt': p.createdAt.toIso8601String(),
      };

  InstallationTask _installationTaskFromMap(Map<String, dynamic> m) =>
      InstallationTask(
        id: m['id'] as String?,
        title: m['title'] as String? ?? '',
        category: m['category'] as String? ?? '',
        required: m['required'] as bool? ?? true,
        status: InstallationTaskStatus.values.firstWhere(
          (e) => e.name == (m['status'] as String? ?? ''),
          orElse: () => InstallationTaskStatus.notCompleted,
        ),
        workerNote: m['workerNote'] as String? ?? '',
      );

  Map<String, dynamic> _installationTaskToMap(InstallationTask t) => {
        'id': t.id,
        'title': t.title,
        'category': t.category,
        'required': t.required,
        'status': t.status.name,
        'workerNote': t.workerNote,
      };

  InstallationApproval _installationApprovalFromMap(Map<String, dynamic> m) =>
      InstallationApproval(
        id: m['id'] as String?,
        projectId: m['projectId'] as String? ?? '',
        itemId: m['itemId'] as String? ?? '',
        approvedBy: m['approvedBy'] as String? ?? '',
        approvedDate: DateTime.tryParse(m['approvedDate'] as String? ?? ''),
        decision: m['decision'] as String? ?? '',
        comment: m['comment'] as String? ?? '',
        signatureMethod: m['signatureMethod'] as String? ?? 'none',
        signatureImageBytes: (m['signatureImageBytes'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        approvedMaintainerNumber:
            m['approvedMaintainerNumber'] as String? ?? '',
        approvedMaintainerName: m['approvedMaintainerName'] as String? ?? '',
      );

  Map<String, dynamic> _installationApprovalToMap(InstallationApproval a) => {
        'id': a.id,
        'projectId': a.projectId,
        'itemId': a.itemId,
        'approvedBy': a.approvedBy,
        'approvedDate': a.approvedDate.toIso8601String(),
        'decision': a.decision,
        'comment': a.comment,
        'signatureMethod': a.signatureMethod,
        'signatureImageBytes': a.signatureImageBytes,
        'approvedMaintainerNumber': a.approvedMaintainerNumber,
        'approvedMaintainerName': a.approvedMaintainerName,
      };

  DoorFeatureItem _doorFeatureFromMap(Map<String, dynamic> m) =>
      DoorFeatureItem(
        id: m['id'] as String? ?? _uuid.v4(),
        type: m['type'] as String? ?? '',
        selected: m['selected'] as bool? ?? false,
        value: m['value'] as String? ?? '',
        position: m['position'] as String? ?? '',
        note: m['note'] as String? ?? '',
      );

  Map<String, dynamic> _doorFeatureToMap(DoorFeatureItem f) => {
        'id': f.id,
        'type': f.type,
        'selected': f.selected,
        'value': f.value,
        'position': f.position,
        'note': f.note,
      };

  DoorHardwareItem _doorHardwareFromMap(Map<String, dynamic> m) =>
      DoorHardwareItem(
        id: m['id'] as String? ?? _uuid.v4(),
        category: m['category'] as String? ?? '',
        type: m['type'] as String? ?? '',
        selected: m['selected'] as bool? ?? false,
        note: m['note'] as String? ?? '',
      );

  Map<String, dynamic> _doorHardwareToMap(DoorHardwareItem h) => {
        'id': h.id,
        'category': h.category,
        'type': h.type,
        'selected': h.selected,
        'note': h.note,
      };

  DoorMeasurementSet _measurementFromMap(Map<String, dynamic> m) =>
      DoorMeasurementSet(
        id: m['id'] as String? ?? _uuid.v4(),
        openingWidthTop: (m['openingWidthTop'] as num?)?.toDouble(),
        openingWidthMiddle: (m['openingWidthMiddle'] as num?)?.toDouble(),
        openingWidthBottom: (m['openingWidthBottom'] as num?)?.toDouble(),
        openingHeightLeft: (m['openingHeightLeft'] as num?)?.toDouble(),
        openingHeightCentre: (m['openingHeightCentre'] as num?)?.toDouble(),
        openingHeightRight: (m['openingHeightRight'] as num?)?.toDouble(),
        frameWidth: (m['frameWidth'] as num?)?.toDouble(),
        frameHeight: (m['frameHeight'] as num?)?.toDouble(),
        frameDepth: (m['frameDepth'] as num?)?.toDouble(),
        leafWidth: (m['leafWidth'] as num?)?.toDouble(),
        leafHeight: (m['leafHeight'] as num?)?.toDouble(),
        leafThickness: (m['leafThickness'] as num?)?.toDouble(),
      );

  Map<String, dynamic> _measurementToMap(DoorMeasurementSet m) => {
        'id': m.id,
        'openingWidthTop': m.openingWidthTop,
        'openingWidthMiddle': m.openingWidthMiddle,
        'openingWidthBottom': m.openingWidthBottom,
        'openingHeightLeft': m.openingHeightLeft,
        'openingHeightCentre': m.openingHeightCentre,
        'openingHeightRight': m.openingHeightRight,
        'frameWidth': m.frameWidth,
        'frameHeight': m.frameHeight,
        'frameDepth': m.frameDepth,
        'leafWidth': m.leafWidth,
        'leafHeight': m.leafHeight,
        'leafThickness': m.leafThickness,
      };

  List<DoorFeatureItem> _defaultDoorFeatures() {
    return [
      DoorFeatureItem(id: _uuid.v4(), type: 'spyhole'),
      DoorFeatureItem(id: _uuid.v4(), type: 'letterPlate'),
      DoorFeatureItem(
          id: _uuid.v4(), type: 'ventilationGrille', position: 'low'),
      DoorFeatureItem(id: _uuid.v4(), type: 'kickPlate'),
      DoorFeatureItem(id: _uuid.v4(), type: 'pushPlate'),
      DoorFeatureItem(id: _uuid.v4(), type: 'pullHandle'),
      DoorFeatureItem(id: _uuid.v4(), type: 'leverHandle'),
      DoorFeatureItem(id: _uuid.v4(), type: 'panicBar'),
      DoorFeatureItem(id: _uuid.v4(), type: 'accessControl'),
      DoorFeatureItem(id: _uuid.v4(), type: 'signage', value: 'none'),
    ];
  }

  List<DoorHardwareItem> _defaultDoorHardware() {
    return [
      DoorHardwareItem(
          id: _uuid.v4(), category: 'doorControl', type: 'doorCloser'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'doorControl', type: 'concealedCloser'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'doorControl', type: 'floorSpring'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'handles', type: 'leverHandle'),
      DoorHardwareItem(id: _uuid.v4(), category: 'handles', type: 'pullHandle'),
      DoorHardwareItem(id: _uuid.v4(), category: 'handles', type: 'knob'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'locking', type: 'morticeLock'),
      DoorHardwareItem(id: _uuid.v4(), category: 'locking', type: 'latch'),
      DoorHardwareItem(id: _uuid.v4(), category: 'locking', type: 'deadlock'),
      DoorHardwareItem(id: _uuid.v4(), category: 'locking', type: 'multipoint'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'locking', type: 'electricLock'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'additional', type: 'dropSeal'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'additional', type: 'thresholdSeal'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'additional', type: 'intumescentSeals'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'additional', type: 'smokeSeals'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'additional', type: 'doorSelector'),
      DoorHardwareItem(
          id: _uuid.v4(), category: 'additional', type: 'coordinator'),
    ];
  }

  PreInstallItem _preInstallItemFromMap(Map<String, dynamic> m) {
    // Migration-safe logic: If visibleToWorkers is missing but releasedToInstallation is true, set visibleToWorkers true
    final hasVisibleToWorkers = m.containsKey('visibleToWorkers');
    final legacyReleased = m['releasedToInstallation'] == true;
    final visibleToWorkers = hasVisibleToWorkers
        ? (m['visibleToWorkers'] as bool? ?? false)
        : (legacyReleased ? true : false);
    return PreInstallItem(
      id: m['id'] as String? ?? _uuid.v4(),
      projectId: m['projectId'] as String? ?? '',
      doorRef: m['doorRef'] as String? ?? '',
      doorDrawingId: m['doorDrawingId'] as String? ?? '',
      doorPinId: m['doorPinId'] as String? ?? '',
      level: m['level'] as String? ?? '',
      location: m['location'] as String? ?? '',
      doorPurpose: m['doorPurpose'] as String? ?? '',
      configuration: m['configuration'] as String? ?? 'singleLeaf',
      hasFrame: m['hasFrame'] as bool? ?? true,
      handingMode: m['handingMode'] as String? ?? 'hingesLeftIn',
      openingWidth: m['openingWidth'] as String? ?? '',
      openingHeight: m['openingHeight'] as String? ?? '',
      frameDepth: m['frameDepth'] as String? ?? '',
      handing: m['handing'] as String? ?? '',
      fireRating: m['fireRating'] as String? ?? '',
      doorType: m['doorType'] as String? ?? '',
      leafType: m['leafType'] as String? ?? '',
      frameType: m['frameType'] as String? ?? '',
      threshold: m['threshold'] as String? ?? '',
      glazing: m['glazing'] as String? ?? '',
      glazingDetails: m['glazingDetails'] as String? ?? '',
      seals: m['seals'] as String? ?? '',
      ironmongery: m['ironmongery'] as String? ?? '',
      closer: m['closer'] as String? ?? '',
      lockLatchType: m['lockLatchType'] as String? ?? '',
      letterplate: m['letterplate'] as String? ?? '',
      viewer: m['viewer'] as String? ?? '',
      signage: m['signage'] as String? ?? '',
      customSignage: m['customSignage'] as String? ?? '',
      glazingType: m['glazingType'] as String? ?? 'none',
      ventilationGrilleEnabled: m['ventilationGrilleEnabled'] as bool? ?? false,
      ventilationGrillePosition:
          m['ventilationGrillePosition'] as String? ?? 'low',
      finish: m['finish'] as String? ?? '',
      doorMaterial: m['doorMaterial'] as String? ?? '',
      frameMaterial: m['frameMaterial'] as String? ?? '',
      finishType: m['finishType'] as String? ?? '',
      colourRal: m['colourRal'] as String? ?? '',
      specialFinishNotes: m['specialFinishNotes'] as String? ?? '',
      architraves: m['architraves'] as String? ?? '',
      specialNotes: m['specialNotes'] as String? ?? '',
      accessNotes: m['accessNotes'] as String? ?? '',
      materialsRequired: m['materialsRequired'] as String? ?? '',
      preInstallComments: m['preInstallComments'] as String? ?? '',
      manufactureNotes: m['manufactureNotes'] as String? ?? '',
      revisionVersion: m['revisionVersion'] as String? ?? 'v1',
      status: InstallationStatus.values.firstWhere(
          (e) => e.name == (m['status'] as String? ?? ''),
          orElse: () => InstallationStatus.pending),
      preInstallPhotos: (m['preInstallPhotos'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _preInstallPhotoFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      features: (m['features'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _doorFeatureFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      hardware: (m['hardware'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _doorHardwareFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      measurements: m['measurements'] is Map
          ? _measurementFromMap(
              Map<String, dynamic>.from(m['measurements'] as Map))
          : null,
      installationTasks: (m['installationTasks'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _installationTaskFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      installationPhotos: (m['installationPhotos'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _installationPhotoFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      workerNote: m['workerNote'] as String? ?? '',
      completedBy: m['completedBy'] as String? ?? '',
      completedDate: DateTime.tryParse(m['completedDate'] as String? ?? ''),
      submittedBy: m['submittedBy'] as String? ?? '',
      submittedAt: DateTime.tryParse(m['submittedAt'] as String? ?? ''),
      approvedBy: m['approvedBy'] as String? ?? '',
      approvedAt: DateTime.tryParse(m['approvedAt'] as String? ?? ''),
      rejectedBy: m['rejectedBy'] as String? ?? '',
      rejectedAt: DateTime.tryParse(m['rejectedAt'] as String? ?? ''),
      rejectionNote: m['rejectionNote'] as String? ?? '',
      approval: m['approval'] is Map
          ? _installationApprovalFromMap(
              Map<String, dynamic>.from(m['approval'] as Map))
          : null,
      rejectionReason: m['rejectionReason'] as String? ?? '',
      managerApprovalPhotos: (m['managerApprovalPhotos'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _installationPhotoFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      managerRejectionPhotos: (m['managerRejectionPhotos'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _installationPhotoFromMap(Map<String, dynamic>.from(e)))
          .toList(),
      linkedDoorId: m['linkedDoorId'] as String? ?? '',
      fullReplacementTask: m['fullReplacementTask'] as bool? ?? false,
      surveyType: _preInstallSurveyTypeFromStorage(
        m['surveyType'] as String?,
      ),
      existingDoorRemovalRequired: _existingDoorRemovalRequiredFromStorage(
        surveyTypeRaw: m['surveyType'] as String?,
        explicitValue: m['existingDoorRemovalRequired'],
      ),
      supplyResponsibility: PreInstallSupplyResponsibility.values.firstWhere(
          (e) => e.name == (m['supplyResponsibility'] as String? ?? ''),
          orElse: () => PreInstallSupplyResponsibility.bw_supply_install),
      customSupplyResponsibility:
          m['customSupplyResponsibility'] as String? ?? '',
      preInstallationStatus: PreInstallationWorkflowStatus.values.firstWhere(
          (e) => e.name == (m['preInstallationStatus'] as String? ?? ''),
          orElse: () => PreInstallationWorkflowStatus.draft),
      expectedDeliveryDate:
          DateTime.tryParse(m['expectedDeliveryDate'] as String? ?? ''),
      deliveryConfirmed: m['deliveryConfirmed'] as bool? ?? false,
      deliveryConfirmedAt:
          DateTime.tryParse(m['deliveryConfirmedAt'] as String? ?? ''),
      deliveryConfirmedBy: m['deliveryConfirmedBy'] as String? ?? '',
      releasedToInstallation: m['releasedToInstallation'] as bool? ?? false,
      releasedDate: DateTime.tryParse(m['releasedDate'] as String? ?? ''),
      releasedBy: m['releasedBy'] as String? ?? '',
      visibleToWorkers: visibleToWorkers,
      workerVisibleFrom:
          DateTime.tryParse(m['workerVisibleFrom'] as String? ?? ''),
    );
  }

  Map<String, dynamic> _preInstallItemToMap(PreInstallItem i) => {
        'id': i.id,
        'projectId': i.projectId,
        'doorRef': i.doorRef,
        'doorDrawingId': i.doorDrawingId,
        'doorPinId': i.doorPinId,
        'level': i.level,
        'location': i.location,
        'doorPurpose': i.doorPurpose,
        'configuration': i.configuration,
        'hasFrame': i.hasFrame,
        'handingMode': i.handingMode,
        'openingWidth': i.openingWidth,
        'openingHeight': i.openingHeight,
        'frameDepth': i.frameDepth,
        'handing': i.handing,
        'fireRating': i.fireRating,
        'doorType': i.doorType,
        'leafType': i.leafType,
        'frameType': i.frameType,
        'threshold': i.threshold,
        'glazing': i.glazing,
        'glazingDetails': i.glazingDetails,
        'seals': i.seals,
        'ironmongery': i.ironmongery,
        'closer': i.closer,
        'lockLatchType': i.lockLatchType,
        'letterplate': i.letterplate,
        'viewer': i.viewer,
        'signage': i.signage,
        'customSignage': i.customSignage,
        'glazingType': i.glazingType,
        'ventilationGrilleEnabled': i.ventilationGrilleEnabled,
        'ventilationGrillePosition': i.ventilationGrillePosition,
        'finish': i.finish,
        'doorMaterial': i.doorMaterial,
        'frameMaterial': i.frameMaterial,
        'finishType': i.finishType,
        'colourRal': i.colourRal,
        'specialFinishNotes': i.specialFinishNotes,
        'architraves': i.architraves,
        'specialNotes': i.specialNotes,
        'accessNotes': i.accessNotes,
        'materialsRequired': i.materialsRequired,
        'preInstallComments': i.preInstallComments,
        'manufactureNotes': i.manufactureNotes,
        'revisionVersion': i.revisionVersion,
        'status': i.status.name,
        'preInstallPhotos':
            i.preInstallPhotos.map(_preInstallPhotoToMap).toList(),
        'features': i.features.map(_doorFeatureToMap).toList(),
        'hardware': i.hardware.map(_doorHardwareToMap).toList(),
        'measurements':
            i.measurements == null ? null : _measurementToMap(i.measurements!),
        'installationTasks':
            i.installationTasks.map(_installationTaskToMap).toList(),
        'installationPhotos':
            i.installationPhotos.map(_installationPhotoToMap).toList(),
        'workerNote': i.workerNote,
        'completedBy': i.completedBy,
        'completedDate': i.completedDate?.toIso8601String(),
        'submittedBy': i.submittedBy,
        'submittedAt': i.submittedAt?.toIso8601String(),
        'approvedBy': i.approvedBy,
        'approvedAt': i.approvedAt?.toIso8601String(),
        'rejectedBy': i.rejectedBy,
        'rejectedAt': i.rejectedAt?.toIso8601String(),
        'rejectionNote': i.rejectionNote,
        'approval':
            i.approval == null ? null : _installationApprovalToMap(i.approval!),
        'rejectionReason': i.rejectionReason,
        'managerApprovalPhotos':
            i.managerApprovalPhotos.map(_installationPhotoToMap).toList(),
        'managerRejectionPhotos':
            i.managerRejectionPhotos.map(_installationPhotoToMap).toList(),
        'linkedDoorId': i.linkedDoorId,
        'fullReplacementTask': i.fullReplacementTask,
        'surveyType': i.surveyType.name,
        'existingDoorRemovalRequired': i.existingDoorRemovalRequired,
        'supplyResponsibility': i.supplyResponsibility.name,
        'customSupplyResponsibility': i.customSupplyResponsibility,
        'preInstallationStatus': i.preInstallationStatus.name,
        'expectedDeliveryDate': i.expectedDeliveryDate?.toIso8601String(),
        'deliveryConfirmed': i.deliveryConfirmed,
        'deliveryConfirmedAt': i.deliveryConfirmedAt?.toIso8601String(),
        'deliveryConfirmedBy': i.deliveryConfirmedBy,
        'releasedToInstallation': i.releasedToInstallation,
        'releasedDate': i.releasedDate?.toIso8601String(),
        'releasedBy': i.releasedBy,
        'visibleToWorkers': i.visibleToWorkers,
        'workerVisibleFrom': i.workerVisibleFrom?.toIso8601String(),
      };

  PreInstallSurveyType _preInstallSurveyTypeFromStorage(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return PreInstallSurveyType.specification_order;
    }
    if (raw == 'existing_door' || raw == 'new_opening') {
      return PreInstallSurveyType.specification_order;
    }
    if (raw == 'installation_only') {
      return PreInstallSurveyType.installation_only;
    }
    return PreInstallSurveyType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () {
        return PreInstallSurveyType.specification_order;
      },
    );
  }

  bool _existingDoorRemovalRequiredFromStorage({
    required String? surveyTypeRaw,
    required Object? explicitValue,
  }) {
    if (explicitValue is bool) {
      return explicitValue;
    }

    final raw = (surveyTypeRaw ?? '').trim();
    if (raw == 'new_opening') {
      return false;
    }
    if (raw == 'installation_only') {
      return false;
    }
    return true;
  }
}

/// One independent controller+storage per workspace.
final surveyControllerFamilyProvider = StateNotifierProvider.family<
    SurveyController, SurveyState, InspectionWorkspace>(
  (ref, workspace) => SurveyController(ref, workspace),
);

/// Increments when DRW pins change, allowing overlays to rebuild without rewriting Survey state.
final surveyDrawingPinsRevisionProvider =
    StateProvider.family<int, InspectionWorkspace>((ref, workspace) => 0);

/// Convenience alias – fire-door workspace (uses same Hive key as historical data).
final surveyControllerProvider =
    surveyControllerFamilyProvider(InspectionWorkspace.fireDoor);
