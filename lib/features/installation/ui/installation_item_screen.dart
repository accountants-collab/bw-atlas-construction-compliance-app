import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../app/app_drawer.dart';
import '../../../app/ui/photo_viewer.dart';
import '../../../app/ui/selection_controls.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../../auth/current_user_role.dart';
import '../../../core/media/camera_capture_helper.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../storage/data/company_file_providers.dart';
import '../../storage/domain/company_file_record.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/state/survey_controller.dart';
import '../../surveys/ui/project_drawing_viewer.dart';

class InstallationItemScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final String itemId;
  final bool managerReview;
  final String workspaceKey;

  const InstallationItemScreen({
    super.key,
    required this.surveyId,
    required this.itemId,
    this.managerReview = false,
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<InstallationItemScreen> createState() =>
      _InstallationItemScreenState();
}

class _InstallationItemScreenState
    extends ConsumerState<InstallationItemScreen> {
  final _reviewNote = TextEditingController();
  final _approverName = TextEditingController();
  final _approvedMaintainerNumber = TextEditingController();
  Uint8List? _overrideSignatureBytes;
  String _overrideSignatureName = '';
  bool _managerReviewSeeded = false;
  bool _cloudPhotoSynced = false;

  static const _blue = Color(0xFF1565C0);

  @override
  void dispose() {
    _reviewNote.dispose();
    _approverName.dispose();
    _approvedMaintainerNumber.dispose();
    super.dispose();
  }

  Future<Uint8List?> _captureCamera() async {
    final x = await CameraCaptureHelper.pickImage(context, imageQuality: 85);
    if (x == null) return null;
    return x.readAsBytes();
  }

  Future<List<PlatformFile>> _pickUpload() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (res == null) return const [];
    return res.files.where((f) => f.bytes != null).toList();
  }

  String _mimeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<List<InstallationPhoto>> _uploadPhotosToCloud({
    required String companyId,
    required String uploaderUid,
    required String photoType,
    required List<Map<String, dynamic>> files,
  }) async {
    final repo = ref.read(companyFileRepositoryProvider);
    final uploaded = <InstallationPhoto>[];

    for (final file in files) {
      final name = file['name'] as String;
      final bytes = file['bytes'] as Uint8List;
      final mimeType = file['mimeType'] as String;
      try {
        final record = await repo.uploadBytes(
          companyId: companyId,
          entityType: 'installationPhoto',
          entityId: widget.itemId,
          createdByUid: uploaderUid,
          fileName: name,
          bytes: bytes,
          mimeType: mimeType,
          kind: CompanyFileKind.image,
          tags: [photoType, widget.surveyId],
        );
        uploaded.add(
          InstallationPhoto(
            id: record.fileId,
            projectId: widget.surveyId,
            itemId: widget.itemId,
            type: photoType,
            fileName: name,
            mimeType: mimeType,
            bytes: bytes,
            cloudStoragePath: record.storagePath,
            cloudDownloadUrl: record.downloadUrl,
          ),
        );
      } catch (_) {
        // Keep going for remaining files.
      }
    }

    return uploaded;
  }

  List<InstallationPhoto> _mergeById(
      List<InstallationPhoto> current, List<InstallationPhoto> incoming) {
    final next = [...current];
    for (final photo in incoming) {
      final idx = next.indexWhere((p) => p.id == photo.id);
      if (idx == -1) {
        next.add(photo);
      } else {
        final existing = next[idx];
        next[idx] = existing.copyWith(
          fileName: photo.fileName,
          mimeType: photo.mimeType,
          cloudStoragePath: photo.cloudStoragePath,
          cloudDownloadUrl: photo.cloudDownloadUrl,
          bytes: existing.bytes.isEmpty ? photo.bytes : existing.bytes,
        );
      }
    }
    return next;
  }

  Future<void> _syncCloudInstallationPhotos({
    required String companyId,
    required SurveyController controller,
    required PreInstallItem item,
  }) async {
    if (_cloudPhotoSynced) return;
    _cloudPhotoSynced = true;

    final repo = ref.read(companyFileRepositoryProvider);
    try {
      final records = await repo.listEntityFiles(
        companyId: companyId,
        entityType: 'installationPhoto',
        entityId: widget.itemId,
      );
      if (!mounted || records.isEmpty) return;

      final install = <InstallationPhoto>[];
      final managerApproval = <InstallationPhoto>[];
      final managerRejection = <InstallationPhoto>[];

      for (final r in records) {
        final type = r.tags.isEmpty ? 'installation' : r.tags.first;
        final photo = InstallationPhoto(
          id: r.fileId,
          projectId: widget.surveyId,
          itemId: widget.itemId,
          type: type,
          fileName: r.originalName,
          mimeType: r.mimeType,
          bytes: const [],
          cloudStoragePath: r.storagePath,
          cloudDownloadUrl: r.downloadUrl,
          createdAt: r.createdAt,
        );

        if (type == 'managerApproval') {
          managerApproval.add(photo);
        } else if (type == 'managerRejection') {
          managerRejection.add(photo);
        } else {
          install.add(photo);
        }
      }

      controller.setInstallationPhotos(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        photos: _mergeById(item.installationPhotos, install),
      );
      controller.setInstallationManagerApprovalPhotos(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        photos: _mergeById(item.managerApprovalPhotos, managerApproval),
      );
      controller.setInstallationManagerRejectionPhotos(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        photos: _mergeById(item.managerRejectionPhotos, managerRejection),
      );
    } catch (_) {
      // Non-blocking: local photos continue to work.
    }
  }

  Future<InstallationPhoto?> _resolvePhotoBytes({
    required InstallationPhoto photo,
    required List<InstallationPhoto> source,
    required void Function(List<InstallationPhoto>) apply,
  }) async {
    if (photo.bytes.isNotEmpty) return photo;
    if (photo.cloudDownloadUrl.trim().isEmpty) return photo;

    try {
      final response = await http.get(Uri.parse(photo.cloudDownloadUrl));
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.isEmpty) {
        throw Exception('download failed');
      }
      final updated = photo.copyWith(bytes: response.bodyBytes);
      final next = source.map((p) => p.id == photo.id ? updated : p).toList();
      apply(next);
      return updated;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not load photo from cloud storage.')),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = parseInspectionWorkspaceKey(widget.workspaceKey) ??
        InspectionWorkspace.fireDoor;
    final workspaceSlug = inspectionWorkspaceSlug(workspace);
    ref.watch(surveyControllerFamilyProvider(workspace));
    final controller =
        ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final survey = controller.getById(widget.surveyId);
    final item = controller.getPreInstallItem(
        surveyId: widget.surveyId, itemId: widget.itemId);
    final role = ref.watch(currentUserRoleProvider);

    if (survey == null || item == null) {
      return const Scaffold(body: Center(child: Text('Opening not found')));
    }

    final auth = ref.watch(authControllerProvider);
    final disclaimer = survey.disclaimerAcceptance;
    final fallbackApproverName = () {
      final disclaimerName = disclaimer?.inspectorName.trim() ?? '';
      if (disclaimerName.isNotEmpty) return disclaimerName;
      final currentUserName = auth.currentUser?.name.trim() ?? '';
      if (currentUserName.isNotEmpty) return currentUserName;
      return 'Manager';
    }();
    final companyId = auth.companyId;
    if (companyId != null && companyId.isNotEmpty) {
      _syncCloudInstallationPhotos(
        companyId: companyId,
        controller: controller,
        item: item,
      );
    }

    final workerEditableStatus = item.status == InstallationStatus.pending ||
        item.status == InstallationStatus.inProgress ||
        item.status == InstallationStatus.rejectedNeedsRework ||
        item.status == InstallationStatus.completedByWorker;
    final canWorkerUpdate = !widget.managerReview &&
        role == UserRole.worker &&
        workerEditableStatus;
    final canManagerReview = widget.managerReview &&
        (role == UserRole.manager ||
            role == UserRole.owner ||
            role == UserRole.admin ||
            role == UserRole.superAdmin);
    final linkedDoor = item.linkedDoorId.trim().isEmpty
        ? null
        : survey.doors.cast<Door?>().firstWhere(
              (door) => door != null && door.id == item.linkedDoorId.trim(),
              orElse: () => null,
            );

    if (!_managerReviewSeeded) {
      _managerReviewSeeded = true;
      _approverName.text = item.approvedBy.trim().isNotEmpty
          ? item.approvedBy.trim()
          : fallbackApproverName;
      _approvedMaintainerNumber.text =
          item.approval?.approvedMaintainerNumber.trim().isNotEmpty == true
              ? item.approval!.approvedMaintainerNumber.trim()
              : '';
      _reviewNote.text = item.approval?.comment.trim().isNotEmpty == true
          ? item.approval!.comment.trim()
          : item.rejectionReason.trim();
    }

    void patch(PreInstallItem Function(PreInstallItem current) update) {
      controller.updatePreInstallItem(
          surveyId: widget.surveyId, itemId: widget.itemId, update: update);
    }

    Future<void> addInstallPhoto({required bool camera}) async {
      if (!canWorkerUpdate) return;
      const type = 'installation';
      final companyId = auth.companyId;
      if (companyId == null || companyId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Company workspace is missing.')),
        );
        return;
      }

      final payloads = <Map<String, dynamic>>[];

      if (camera) {
        final bytes = await _captureCamera();
        if (bytes == null) return;
        payloads.add({
          'name': 'install_${DateTime.now().millisecondsSinceEpoch}.jpg',
          'mimeType': 'image/jpeg',
          'bytes': bytes,
        });
      } else {
        final files = await _pickUpload();
        if (files.isEmpty) return;
        for (final f in files) {
          payloads.add({
            'name': f.name,
            'mimeType': _mimeForName(f.name),
            'bytes': f.bytes!,
          });
        }
      }

      final uploaded = await _uploadPhotosToCloud(
        companyId: companyId,
        uploaderUid: auth.uid,
        photoType: type,
        files: payloads,
      );
      if (uploaded.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Photo upload failed. Please try again.')),
        );
        return;
      }

      controller.addInstallationPhotos(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        photos: uploaded,
      );
    }

    return _buildInstallationExecution(
      context: context,
      survey: survey,
      item: item,
      workspaceSlug: workspaceSlug,
      canWorkerUpdate: canWorkerUpdate,
      canManagerReview: canManagerReview,
      linkedDoor: linkedDoor,
      patch: patch,
      addInstallPhoto: addInstallPhoto,
      controller: controller,
    );
  }

  Widget _buildInstallationExecution({
    required BuildContext context,
    required Survey survey,
    required PreInstallItem item,
    required String workspaceSlug,
    required bool canWorkerUpdate,
    required bool canManagerReview,
    required Door? linkedDoor,
    required void Function(
            PreInstallItem Function(PreInstallItem current) update)
        patch,
    required Future<void> Function({required bool camera}) addInstallPhoto,
    required SurveyController controller,
  }) {
    final auth = ref.watch(authControllerProvider);
    final canSubmit = controller.canSubmitInstallationItem(
        surveyId: widget.surveyId, itemId: widget.itemId);
    final minPhotos = SurveyController.minimumInstallationPhotoCount;
    final isLockedAfterSubmit = item.status == InstallationStatus.forApproval ||
        item.status == InstallationStatus.approved;
    final disclaimer = survey.disclaimerAcceptance;
    final disclaimerSignatureBytes =
        disclaimer?.signatureImageBytes ?? const <int>[];
    final effectiveSignatureBytes =
        (_overrideSignatureBytes != null && _overrideSignatureBytes!.isNotEmpty)
            ? _overrideSignatureBytes!
            : (disclaimerSignatureBytes.isNotEmpty
                ? Uint8List.fromList(disclaimerSignatureBytes)
                : null);
    final isReplacementTask =
        item.fullReplacementTask || (linkedDoor?.replacementRequired ?? false);
    final finishSummary = [item.finishType, item.colourRal]
        .where((v) => v.trim().isNotEmpty)
        .join(' / ');
    final hardwareSummary = item.hardware
        .where((h) => h.selected)
        .map((h) => _labelize(h.type))
        .join(', ');

    final pageTitle = widget.managerReview
        ? 'Installation Review ${item.doorRef}'
        : 'Installation Item ${item.doorRef}';
    final pageBody = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => ProjectDrawingAccess.showDrawingPicker(
                  context: context,
                  survey: survey,
                  preferredLevel: item.level,
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('View Drawing'),
              ),
            ),
            const SizedBox(height: 10),
            _card(
              title: 'Door Context & Specification',
              icon: Icons.inventory_2_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _readOnlyKV(
                      'Door Number', item.doorRef.isEmpty ? '-' : item.doorRef),
                  _readOnlyKV(
                      'Location', item.location.isEmpty ? '-' : item.location),
                  _readOnlyKV('Level', item.level.isEmpty ? '-' : item.level),
                  _readOnlyKV('Fire Rating',
                      item.fireRating.isEmpty ? '-' : item.fireRating),
                  _readOnlyKV(
                      'Door Configuration', _labelize(item.configuration)),
                  if (isReplacementTask)
                    _readOnlyKV('Replacement Reason',
                        'Full door set replacement required'),
                  if (isReplacementTask)
                    _readOnlyKV(
                      'Original Inspection Result',
                      linkedDoor == null
                          ? '-'
                          : linkedDoor.result.name.toUpperCase(),
                    ),
                  if (isReplacementTask)
                    _readOnlyKV(
                      'Opening Width (mm)',
                      linkedDoor?.replacementDoor1Width.trim().isNotEmpty ==
                              true
                          ? linkedDoor!.replacementDoor1Width.trim()
                          : (item.openingWidth.trim().isEmpty
                              ? '-'
                              : item.openingWidth.trim()),
                    ),
                  if (isReplacementTask)
                    _readOnlyKV(
                      'Opening Height (mm)',
                      linkedDoor?.replacementDoor1Height.trim().isNotEmpty ==
                              true
                          ? linkedDoor!.replacementDoor1Height.trim()
                          : (item.openingHeight.trim().isEmpty
                              ? '-'
                              : item.openingHeight.trim()),
                    ),
                  if (isReplacementTask &&
                      linkedDoor != null &&
                      linkedDoor.configuration != DoorConfiguration.singleLeaf)
                    _readOnlyKV(
                      'Leaf 1 Approx Width (mm)',
                      linkedDoor.replacementDoor2Width.trim().isEmpty
                          ? '-'
                          : linkedDoor.replacementDoor2Width.trim(),
                    ),
                  if (isReplacementTask &&
                      linkedDoor != null &&
                      linkedDoor.configuration != DoorConfiguration.singleLeaf)
                    _readOnlyKV(
                      'Leaf 2 Approx Width (mm)',
                      linkedDoor.replacementDoor2Height.trim().isEmpty
                          ? '-'
                          : linkedDoor.replacementDoor2Height.trim(),
                    ),
                  _readOnlyKV('Handing', _labelize(item.handingMode)),
                  _readOnlyKV('Glazing', _labelize(item.glazingType)),
                  _readOnlyKV('Finish / Colour',
                      finishSummary.isEmpty ? '-' : finishSummary),
                  _readOnlyKV('Hardware',
                      hardwareSummary.isEmpty ? '-' : hardwareSummary),
                  const SizedBox(height: 8),
                  const Text(
                    'Original Survey Photos',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  if (item.preInstallPhotos.isEmpty)
                    const Text('No original survey photos attached.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in item.preInstallPhotos)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              Uint8List.fromList(p.bytes),
                              width: 108,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: item.workerNote,
                    enabled: canWorkerUpdate,
                    maxLines: 3,
                    onChanged: (value) {
                      controller.setInstallationWorkerNote(
                        surveyId: widget.surveyId,
                        itemId: widget.itemId,
                        note: value,
                      );
                    },
                    decoration: const InputDecoration(
                      labelText: 'Worker completion note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _card(
              title: 'Installation Checklist',
              icon: Icons.task_alt_outlined,
              child: Column(
                children: [
                  for (final task in item.installationTasks) ...[
                    Row(
                      children: [
                        Expanded(
                            child: Text(task.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 170,
                          child:
                              DropdownButtonFormField<InstallationTaskStatus>(
                            initialValue: task.status,
                            decoration: appSelectFieldDecoration(
                              labelText: 'Status',
                              hasSelection: task.status !=
                                  InstallationTaskStatus.notCompleted,
                            ),
                            items: InstallationTaskStatus.values
                                .map((s) => DropdownMenuItem(
                                    value: s, child: Text(_taskLabel(s))))
                                .toList(),
                            onChanged: !canWorkerUpdate
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    controller.updateInstallationTaskStatus(
                                      surveyId: widget.surveyId,
                                      itemId: widget.itemId,
                                      taskId: task.id,
                                      status: v,
                                    );
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            _card(
              title: 'Photos',
              icon: Icons.photo_camera_back_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.status ==
                      InstallationStatus.rejectedNeedsRework) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        item.rejectionNote.trim().isEmpty
                            ? 'This item was returned for rework by manager.'
                            : 'Manager rejection note: ${item.rejectionNote.trim()}',
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (item.managerRejectionPhotos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Manager rejection evidence',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      _installationEvidenceWrap(
                        photos: item.managerRejectionPhotos,
                        showDelete: false,
                        onReplace: (next) {
                          controller.setInstallationManagerRejectionPhotos(
                            surveyId: widget.surveyId,
                            itemId: widget.itemId,
                            photos: next,
                          );
                        },
                        onDelete: null,
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],
                  Text(
                    'Required photos (${item.installationPhotos.length}/$minPhotos minimum):',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text('Existing door (before removal)'),
                  const Text('Opening after removal'),
                  const Text('During installation'),
                  const Text('Fire foam / mastic applied'),
                  const Text('Completed door'),
                  const SizedBox(height: 8),
                  if (canWorkerUpdate)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => addInstallPhoto(camera: true),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Take Photo'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => addInstallPhoto(camera: false),
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Upload Photo'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  if (item.installationPhotos.isEmpty)
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No installation photos yet.'))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (int i = 0; i < item.installationPhotos.length; i++)
                          Container(
                            width: 104,
                            decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final photo = item.installationPhotos[i];
                                    final resolved = await _resolvePhotoBytes(
                                      photo: photo,
                                      source: item.installationPhotos,
                                      apply: (next) {
                                        controller.setInstallationPhotos(
                                          surveyId: widget.surveyId,
                                          itemId: widget.itemId,
                                          photos: next,
                                        );
                                      },
                                    );
                                    if (resolved == null ||
                                        resolved.bytes.isEmpty ||
                                        !context.mounted) {
                                      return;
                                    }

                                    final readyPhotos = item.installationPhotos
                                        .map((p) =>
                                            p.id == resolved.id ? resolved : p)
                                        .where((p) => p.bytes.isNotEmpty)
                                        .toList();
                                    final readyBytes = readyPhotos
                                        .map((p) => p.bytes)
                                        .toList();
                                    final idx = readyPhotos
                                        .indexWhere((p) => p.id == resolved.id);
                                    showPhotoViewer(
                                      context: context,
                                      photos: readyBytes,
                                      initialIndex: idx == -1 ? 0 : idx,
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(8)),
                                    child:
                                        item.installationPhotos[i].bytes.isEmpty
                                            ? Container(
                                                width: 104,
                                                height: 80,
                                                color: const Color(0xFFE8EEF7),
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                    Icons.cloud_done_outlined,
                                                    color: Color(0xFF1565C0)),
                                              )
                                            : Image.memory(
                                                Uint8List.fromList(item
                                                    .installationPhotos[i]
                                                    .bytes),
                                                width: 104,
                                                height: 80,
                                                fit: BoxFit.cover,
                                              ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text('Installation photo ${i + 1}',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: item.workerNote,
                    enabled: canWorkerUpdate,
                    maxLines: 3,
                    onChanged: (value) {
                      controller.setInstallationWorkerNote(
                        surveyId: widget.surveyId,
                        itemId: widget.itemId,
                        note: value,
                      );
                    },
                    decoration: const InputDecoration(
                      labelText: 'Worker completion note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (isLockedAfterSubmit)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        item.status == InstallationStatus.approved
                            ? 'Editing is locked: this item is approved.'
                            : 'Editing is locked after submission until manager review is completed.',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  if (canWorkerUpdate) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        controller.markInstallationInProgress(
                            surveyId: widget.surveyId, itemId: widget.itemId);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Progress saved.')),
                        );
                      },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Progress'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: !canSubmit
                          ? null
                          : () {
                              final workerIdentity =
                                  auth.currentUser?.name.trim().isNotEmpty ==
                                          true
                                      ? auth.currentUser!.name.trim()
                                      : (auth.currentUser?.email
                                                  .trim()
                                                  .isNotEmpty ==
                                              true
                                          ? auth.currentUser!.email.trim()
                                          : 'Worker');
                              controller.submitInstallationForApproval(
                                surveyId: widget.surveyId,
                                itemId: widget.itemId,
                                completedBy: workerIdentity,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Installation item submitted for approval.')),
                              );
                            },
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Submit for Approval'),
                    ),
                  ],
                ],
              ),
            ),
            if (canManagerReview) ...[
              const SizedBox(height: 10),
              _card(
                title: 'Manager Review',
                icon: Icons.verified_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Worker completion evidence',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    if (item.workerNote.trim().isNotEmpty) ...[
                      Text('Worker note: ${item.workerNote.trim()}'),
                      const SizedBox(height: 8),
                    ],
                    if (item.installationPhotos.isEmpty)
                      const Text('No worker completion photos uploaded yet.')
                    else
                      _installationEvidenceWrap(
                        photos: item.installationPhotos,
                        showDelete: false,
                        onReplace: (next) {
                          controller.setInstallationPhotos(
                            surveyId: widget.surveyId,
                            itemId: widget.itemId,
                            photos: next,
                          );
                        },
                        onDelete: null,
                      ),
                    const SizedBox(height: 10),
                    const Text('Manager Sign-Off',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _approverName,
                      decoration: const InputDecoration(
                        labelText: 'Approver full name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _approvedMaintainerNumber,
                      decoration: const InputDecoration(
                        labelText:
                            'Approved maintainer / certificate number (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA5D6A7)),
                      ),
                      child: Text(
                        disclaimerSignatureBytes.isNotEmpty
                            ? 'Disclaimer signature detected and will be used by default for manager sign-off.'
                            : 'No disclaimer signature found. Upload a signature image to include in sign-off.',
                        style: const TextStyle(
                            color: Color(0xFF1B5E20),
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final files = await _pickUpload();
                              if (files.isEmpty) return;
                              final first = files.first;
                              if (first.bytes == null || first.bytes!.isEmpty) {
                                return;
                              }
                              setState(() {
                                _overrideSignatureBytes = first.bytes!;
                                _overrideSignatureName = first.name;
                              });
                            },
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text(
                                'Upload signature override (optional)'),
                          ),
                        ),
                      ],
                    ),
                    if (_overrideSignatureName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Using uploaded signature: $_overrideSignatureName'),
                    ],
                    if (effectiveSignatureBytes != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            Image.memory(effectiveSignatureBytes, height: 72),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text('Manager approval evidence',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final bytes = await _captureCamera();
                              if (bytes == null) return;
                              final companyId = auth.companyId;
                              if (companyId == null || companyId.isEmpty) {
                                return;
                              }
                              final uploaded = await _uploadPhotosToCloud(
                                companyId: companyId,
                                uploaderUid: auth.uid,
                                photoType: 'managerApproval',
                                files: [
                                  {
                                    'name':
                                        'manager_approval_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                    'mimeType': 'image/jpeg',
                                    'bytes': bytes,
                                  },
                                ],
                              );
                              if (uploaded.isEmpty) return;
                              controller.addInstallationManagerApprovalPhotos(
                                surveyId: widget.surveyId,
                                itemId: widget.itemId,
                                photos: uploaded,
                              );
                            },
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Take Photo'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final files = await _pickUpload();
                              if (files.isEmpty) return;
                              final companyId = auth.companyId;
                              if (companyId == null || companyId.isEmpty) {
                                return;
                              }
                              final uploaded = await _uploadPhotosToCloud(
                                companyId: companyId,
                                uploaderUid: auth.uid,
                                photoType: 'managerApproval',
                                files: files
                                    .map((f) => {
                                          'name': f.name,
                                          'mimeType': _mimeForName(f.name),
                                          'bytes': f.bytes!,
                                        })
                                    .toList(),
                              );
                              if (uploaded.isEmpty) return;
                              controller.addInstallationManagerApprovalPhotos(
                                surveyId: widget.surveyId,
                                itemId: widget.itemId,
                                photos: uploaded,
                              );
                            },
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Upload Photo'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (item.managerApprovalPhotos.isNotEmpty)
                      _installationEvidenceWrap(
                        photos: item.managerApprovalPhotos,
                        showDelete: true,
                        onReplace: (next) {
                          controller.setInstallationManagerApprovalPhotos(
                            surveyId: widget.surveyId,
                            itemId: widget.itemId,
                            photos: next,
                          );
                        },
                        onDelete: (index) {
                          final next = [...item.managerApprovalPhotos]
                            ..removeAt(index);
                          final removed = item.managerApprovalPhotos[index];
                          final companyId = auth.companyId;
                          if (companyId != null && companyId.isNotEmpty) {
                            ref.read(companyFileRepositoryProvider).deleteFile(
                                  companyId: companyId,
                                  fileId: removed.id,
                                );
                          }
                          controller.setInstallationManagerApprovalPhotos(
                            surveyId: widget.surveyId,
                            itemId: widget.itemId,
                            photos: next,
                          );
                        },
                      ),
                    const SizedBox(height: 10),
                    const Text('Manager rejection evidence',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final bytes = await _captureCamera();
                              if (bytes == null) return;
                              final companyId = auth.companyId;
                              if (companyId == null || companyId.isEmpty) {
                                return;
                              }
                              final uploaded = await _uploadPhotosToCloud(
                                companyId: companyId,
                                uploaderUid: auth.uid,
                                photoType: 'managerRejection',
                                files: [
                                  {
                                    'name':
                                        'manager_rejection_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                    'mimeType': 'image/jpeg',
                                    'bytes': bytes,
                                  },
                                ],
                              );
                              if (uploaded.isEmpty) return;
                              controller.addInstallationManagerRejectionPhotos(
                                surveyId: widget.surveyId,
                                itemId: widget.itemId,
                                photos: uploaded,
                              );
                            },
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Take Photo'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final files = await _pickUpload();
                              if (files.isEmpty) return;
                              final companyId = auth.companyId;
                              if (companyId == null || companyId.isEmpty) {
                                return;
                              }
                              final uploaded = await _uploadPhotosToCloud(
                                companyId: companyId,
                                uploaderUid: auth.uid,
                                photoType: 'managerRejection',
                                files: files
                                    .map((f) => {
                                          'name': f.name,
                                          'mimeType': _mimeForName(f.name),
                                          'bytes': f.bytes!,
                                        })
                                    .toList(),
                              );
                              if (uploaded.isEmpty) return;
                              controller.addInstallationManagerRejectionPhotos(
                                surveyId: widget.surveyId,
                                itemId: widget.itemId,
                                photos: uploaded,
                              );
                            },
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Upload Photo'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (item.managerRejectionPhotos.isNotEmpty)
                      _installationEvidenceWrap(
                        photos: item.managerRejectionPhotos,
                        showDelete: true,
                        onReplace: (next) {
                          controller.setInstallationManagerRejectionPhotos(
                            surveyId: widget.surveyId,
                            itemId: widget.itemId,
                            photos: next,
                          );
                        },
                        onDelete: (index) {
                          final next = [...item.managerRejectionPhotos]
                            ..removeAt(index);
                          final removed = item.managerRejectionPhotos[index];
                          final companyId = auth.companyId;
                          if (companyId != null && companyId.isNotEmpty) {
                            ref.read(companyFileRepositoryProvider).deleteFile(
                                  companyId: companyId,
                                  fileId: removed.id,
                                );
                          }
                          controller.setInstallationManagerRejectionPhotos(
                            surveyId: widget.surveyId,
                            itemId: widget.itemId,
                            photos: next,
                          );
                        },
                      ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _reviewNote,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Review / rejection note',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              final approver = _approverName.text.trim();
                              if (approver.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Approver full name is required before approval.')),
                                );
                                return;
                              }
                              if (effectiveSignatureBytes == null ||
                                  effectiveSignatureBytes.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'A signature is required for final approval sign-off.')),
                                );
                                return;
                              }
                              controller.approveInstallationItem(
                                surveyId: widget.surveyId,
                                itemId: widget.itemId,
                                approvedBy: approver,
                                comment: _reviewNote.text.trim(),
                                signatureMethod: _overrideSignatureBytes != null
                                    ? 'upload'
                                    : 'disclaimer',
                                signatureImageBytes:
                                    effectiveSignatureBytes.toList(),
                                approvedMaintainerNumber:
                                    _approvedMaintainerNumber.text.trim(),
                                approvedMaintainerName: approver,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Installation item approved.')),
                              );
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Approve Item'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final note = _reviewNote.text.trim();
                              if (note.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Please add rejection note before returning for rework.')),
                                );
                                return;
                              }
                              final approver = _approverName.text.trim();
                              if (approver.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Approver full name is required.')),
                                );
                                return;
                              }
                              controller.rejectInstallationItem(
                                surveyId: widget.surveyId,
                                itemId: widget.itemId,
                                approvedBy: approver,
                                rejectionReason: note,
                                signatureMethod: _overrideSignatureBytes != null
                                    ? 'upload'
                                    : 'disclaimer',
                                signatureImageBytes:
                                    effectiveSignatureBytes?.toList() ??
                                        const [],
                                approvedMaintainerNumber:
                                    _approvedMaintainerNumber.text.trim(),
                                approvedMaintainerName: approver,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Installation item returned for rework.')),
                              );
                            },
                            icon: const Icon(Icons.undo_outlined),
                            label: const Text('Reject / Rework'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        title: pageTitle,
        workspaceKey: widget.workspaceKey,
        currentRoute: '/workspace/$workspaceSlug/modules/installation/projects',
        body: pageBody,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(pageTitle),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: workspaceSlug),
        actions: [
          IconButton(
            onPressed: () => ProjectDrawingAccess.showDrawingPicker(
              context: context,
              survey: survey,
              preferredLevel: item.level,
            ),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'View Drawing',
          ),
        ],
      ),
      drawer: AppDrawer(
          currentRoute:
              '/workspace/$workspaceSlug/modules/installation/projects'),
      body: pageBody,
    );
  }

  Widget _card(
      {required String title, required IconData icon, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _blue),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _readOnlyKV(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
              width: 160,
              child:
                  Text(k, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _installationEvidenceWrap({
    required List<InstallationPhoto> photos,
    required bool showDelete,
    required void Function(List<InstallationPhoto>)? onReplace,
    required void Function(int index)? onDelete,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < photos.length; i++)
          Stack(
            children: [
              GestureDetector(
                onTap: () async {
                  final resolved = await _resolvePhotoBytes(
                    photo: photos[i],
                    source: photos,
                    apply: (next) {
                      if (onReplace != null) {
                        onReplace(next);
                      }
                    },
                  );
                  if (resolved == null || resolved.bytes.isEmpty) {
                    return;
                  }
                  if (!mounted) return;

                  final readyPhotos = photos
                      .map((p) => p.id == resolved.id ? resolved : p)
                      .where((p) => p.bytes.isNotEmpty)
                      .toList();
                  final readyBytes = readyPhotos.map((p) => p.bytes).toList();
                  final idx =
                      readyPhotos.indexWhere((p) => p.id == resolved.id);
                  showPhotoViewer(
                    context: this.context,
                    photos: readyBytes,
                    initialIndex: idx == -1 ? 0 : idx,
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photos[i].bytes.isEmpty
                      ? Container(
                          width: 104,
                          height: 80,
                          color: const Color(0xFFE8EEF7),
                          alignment: Alignment.center,
                          child: const Icon(Icons.cloud_done_outlined,
                              color: Color(0xFF1565C0)),
                        )
                      : Image.memory(
                          Uint8List.fromList(photos[i].bytes),
                          width: 104,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              if (showDelete && onDelete != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: InkWell(
                    onTap: () => onDelete(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

String _taskLabel(InstallationTaskStatus s) {
  switch (s) {
    case InstallationTaskStatus.notCompleted:
      return 'Not Completed';
    case InstallationTaskStatus.completed:
      return 'Completed';
    case InstallationTaskStatus.notApplicable:
      return 'N/A';
  }
}

String _labelize(String raw) {
  if (raw.isEmpty) return '-';
  final withSpaces =
      raw.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return withSpaces
      .replaceAll('_', ' ')
      .split(' ')
      .where((e) => e.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

List<DoorFeatureItem> cFeatureSet(
  List<DoorFeatureItem> source, {
  required String type,
  required bool selected,
  String? value,
  String? position,
}) {
  var found = false;
  final out = source.map((f) {
    if (f.type != type) return f;
    found = true;
    return f.copyWith(selected: selected, value: value, position: position);
  }).toList();
  if (!found) {
    out.add(
      DoorFeatureItem(
        id: '${type}_${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        selected: selected,
        value: value ?? '',
        position: position ?? '',
      ),
    );
  }
  return out;
}
