import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/photo_viewer.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../../core/media/camera_capture_helper.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/state/survey_controller.dart';
import '../../surveys/ui/project_drawing_viewer.dart';

class RemedialDoorDetailScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final String doorId;
  final String workspaceKey;

  const RemedialDoorDetailScreen({
    super.key,
    required this.surveyId,
    required this.doorId,
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<RemedialDoorDetailScreen> createState() =>
      _RemedialDoorDetailScreenState();
}

class _RemedialDoorDetailScreenState
    extends ConsumerState<RemedialDoorDetailScreen> {
  bool _isSubmittingForApproval = false;
  bool _redirectingFromStaleRoute = false;

  Future<PhotoAttachment?> _takePhoto({required String issueId}) async {
    final x = await CameraCaptureHelper.pickImage(context, imageQuality: 85);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    return PhotoAttachment(
      fileName: x.name.isEmpty
          ? 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : x.name,
      mimeType: 'image/jpeg',
      bytes: bytes,
      surveyId: widget.surveyId,
      doorId: widget.doorId,
      issueId: issueId,
    );
  }

  Future<List<PhotoAttachment>> _uploadPhotos({required String issueId}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (res == null) return [];

    final out = <PhotoAttachment>[];
    for (final f in res.files) {
      if (f.bytes == null) continue;
      out.add(
        PhotoAttachment(
          fileName: f.name,
          mimeType: 'image/*',
          bytes: f.bytes!,
          surveyId: widget.surveyId,
          doorId: widget.doorId,
          issueId: issueId,
        ),
      );
    }
    return out;
  }

  RemedialPhoto _toRemedialPhoto(
      {required PhotoAttachment p, required String remedialItemId}) {
    return RemedialPhoto(
      projectId: widget.surveyId,
      doorId: widget.doorId,
      remedialItemId: remedialItemId,
      issueId: p.issueId,
      fileName: p.fileName,
      mimeType: p.mimeType,
      bytes: p.bytes,
      createdAt: p.capturedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = parseInspectionWorkspaceKey(widget.workspaceKey) ??
        InspectionWorkspace.fireDoor;
    final workspaceSlug = inspectionWorkspaceSlug(workspace);
    final state = ref.watch(surveyControllerFamilyProvider(workspace));
    final controller =
        ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final auth = ref.watch(authControllerProvider);
    final survey = controller.getById(widget.surveyId);
    final door = controller.getDoorById(
        surveyId: widget.surveyId, doorId: widget.doorId);
    if (kDebugMode) {
      debugPrint(
        'remedial_detail_lookup workspace=$workspaceSlug survey=${widget.surveyId} door=${widget.doorId} foundSurvey=${survey != null} foundDoor=${door != null}',
      );
    }
    if (survey == null || door == null) {
      String? fallbackSurveyId;
      for (final s in state.surveys) {
        final hasDoor = s.doors.any((d) => d.id == widget.doorId);
        if (hasDoor) {
          fallbackSurveyId = s.id;
          break;
        }
      }

      if (fallbackSurveyId != null &&
          fallbackSurveyId != widget.surveyId &&
          !_redirectingFromStaleRoute) {
        _redirectingFromStaleRoute = true;
        if (kDebugMode) {
          debugPrint(
            'notification_opened_remedial workspace=$workspaceSlug survey=${widget.surveyId} door=${widget.doorId} fallbackSurvey=$fallbackSurveyId',
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go(
              '/workspace/$workspaceSlug/remedials/$fallbackSurveyId/doors/${widget.doorId}');
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This task is no longer available or has been moved.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go(
                      '/workspace/$workspaceSlug/modules/remedials/projects'),
                  child: const Text('Open Remedial Projects'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final canEdit = door.remedialStatus != RemedialStatus.approved;
    final canSubmit = controller.canSubmitDoorForApproval(
        surveyId: widget.surveyId, doorId: widget.doorId);
    final hasPreviousSubmit =
        door.remedialItems.any((i) => i.submittedAt != null);
    final workerIdentity = _currentUserIdentity(auth);
    final activeItems = door.remedialItems
        .where((i) => i.status != RemedialStatus.approved)
        .toList();
    final pageBody = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ProjectDrawingAccess.showDrawingPicker(
                      context: context,
                      survey: survey,
                      preferredLevel: door.floor,
                    ),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('View Drawing'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (door.remedialStatus == RemedialStatus.rejectedNeedsRework)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  'Returned for rework. Review rejection notes below, update evidence, and resubmit.',
                  style:
                      TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                ),
              ),
            if (door.remedialStatus == RemedialStatus.forApproval)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.45)),
                ),
                child: const Text(
                  'Submitted — awaiting manager review. You can still update evidence and resubmit.',
                  style: TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.w700),
                ),
              ),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Door Summary',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 8),
                    Text('Door: ${door.number}'),
                    Text('Level: ${door.floor.isEmpty ? '-' : door.floor}'),
                    Text('Location: ${door.area.isEmpty ? '-' : door.area}'),
                    Text('Fire rating: ${door.fireRating.name.toUpperCase()}'),
                    Text(
                        'Inspection result: ${door.result.name.toUpperCase()}'),
                    Text(
                        'Date inspected: ${door.inspectionDate.day.toString().padLeft(2, '0')}/${door.inspectionDate.month.toString().padLeft(2, '0')}/${door.inspectionDate.year}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (activeItems.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                      'All remedial issues on this door are already approved.'),
                ),
              ),
            for (final item in activeItems) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text('Category: ${item.category}'),
                      Text('Severity: ${item.severity}'),
                      const SizedBox(height: 8),
                      const Text('Original inspection note',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(item.originalComment.trim().isEmpty
                          ? '-'
                          : item.originalComment),
                      const SizedBox(height: 8),
                      const Text('Required action / guidance',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(item.recommendedAction.trim().isEmpty
                          ? '-'
                          : item.recommendedAction),
                      const SizedBox(height: 10),
                      if (item.originalInspectionPhotos.isNotEmpty) ...[
                        const Text('Original inspection photos',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 90,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: item.originalInspectionPhotos.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final p = item.originalInspectionPhotos[index];
                              return GestureDetector(
                                onTap: () => showPhotoViewer(
                                  context: context,
                                  photos: item.originalInspectionPhotos
                                      .map((e) => e.bytes)
                                      .toList(),
                                  initialIndex: index,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                      Uint8List.fromList(p.bytes),
                                      width: 120,
                                      fit: BoxFit.cover),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextFormField(
                        initialValue: item.workerNote,
                        enabled: canEdit,
                        onChanged: (v) => controller.setRemedialItemWorkerNote(
                          surveyId: widget.surveyId,
                          doorId: widget.doorId,
                          remedialItemId: item.id,
                          note: v,
                        ),
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Worker completion note',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (item.rejectionNote.trim().isNotEmpty ||
                          item.managerRejectionNote.trim().isNotEmpty) ...[
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
                            'Rejection note: ${item.rejectionNote.trim().isEmpty ? item.managerRejectionNote : item.rejectionNote}',
                            style: const TextStyle(
                                color: Colors.red, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (item.managerRejectionPhotos.isNotEmpty) ...[
                        const Text('Manager rejection evidence',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (int i = 0;
                                i < item.managerRejectionPhotos.length;
                                i++)
                              GestureDetector(
                                onTap: () => showPhotoViewer(
                                  context: context,
                                  photos: item.managerRejectionPhotos
                                      .map((p) => p.bytes)
                                      .toList(),
                                  initialIndex: i,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    Uint8List.fromList(
                                        item.managerRejectionPhotos[i].bytes),
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !canEdit
                                  ? null
                                  : () async {
                                      final p = await _takePhoto(
                                          issueId: item.issueId);
                                      if (p == null) return;
                                      controller.addRemedialPhoto(
                                        surveyId: widget.surveyId,
                                        doorId: widget.doorId,
                                        remedialItemId: item.id,
                                        photos: [
                                          _toRemedialPhoto(
                                              p: p, remedialItemId: item.id)
                                        ],
                                        completedBy: workerIdentity,
                                      );
                                    },
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Take Photo'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !canEdit
                                  ? null
                                  : () async {
                                      final picked = await _uploadPhotos(
                                          issueId: item.issueId);
                                      if (picked.isEmpty) return;
                                      controller.addRemedialPhoto(
                                        surveyId: widget.surveyId,
                                        doorId: widget.doorId,
                                        remedialItemId: item.id,
                                        photos: picked
                                            .map((p) => _toRemedialPhoto(
                                                p: p, remedialItemId: item.id))
                                            .toList(),
                                        completedBy: workerIdentity,
                                      );
                                    },
                              icon: const Icon(Icons.upload_file_outlined),
                              label: const Text('Upload Photo'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (item.afterRepairPhotos.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.red.withValues(alpha: 0.35)),
                          ),
                          child: const Text(
                            'Not completed. Upload at least one completion photo for this defect.',
                            style: TextStyle(
                                color: Colors.red, fontWeight: FontWeight.w700),
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color:
                                        Colors.green.withValues(alpha: 0.35)),
                              ),
                              child: Text(
                                item.completedBy.trim().isEmpty
                                    ? 'Completed. Evidence uploaded for this defect.'
                                    : 'Completed by ${item.completedBy} with photo evidence.',
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (int i = 0;
                                    i < item.afterRepairPhotos.length;
                                    i++)
                                  Stack(
                                    children: [
                                      GestureDetector(
                                        onTap: () => showPhotoViewer(
                                          context: context,
                                          photos: item.afterRepairPhotos
                                              .map((p) => p.bytes)
                                              .toList(),
                                          initialIndex: i,
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.memory(
                                            Uint8List.fromList(item
                                                .afterRepairPhotos[i].bytes),
                                            width: 90,
                                            height: 90,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      if (canEdit)
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: InkWell(
                                            onTap: () {
                                              final next = [
                                                ...item.afterRepairPhotos
                                              ]..removeAt(i);
                                              controller.setRemedialItemPhotos(
                                                surveyId: widget.surveyId,
                                                doorId: widget.doorId,
                                                remedialItemId: item.id,
                                                photos: next,
                                                completedBy: workerIdentity,
                                              );
                                            },
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              padding: const EdgeInsets.all(3),
                                              child: const Icon(Icons.close,
                                                  color: Colors.white,
                                                  size: 14),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      _completionStatusBanner(item),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (canEdit && !canSubmit)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  'Submit for Approval stays disabled until every defect has at least one completion photo.',
                  style:
                      TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                ),
              ),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: (!canEdit || !canSubmit || _isSubmittingForApproval)
                    ? null
                    : () {
                        if (_isSubmittingForApproval) return;
                        setState(() => _isSubmittingForApproval = true);
                        controller.submitDoorForApproval(
                          surveyId: widget.surveyId,
                          doorId: widget.doorId,
                          completedBy: workerIdentity,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              hasPreviousSubmit
                                  ? 'Resubmitted for approval.'
                                  : 'Submitted for approval.',
                            ),
                          ),
                        );
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          context.go(
                              '/workspace/$workspaceSlug/remedials/${widget.surveyId}/doors');
                        }
                      },
                icon: const Icon(Icons.send_outlined),
                label: Text(hasPreviousSubmit
                    ? 'Resubmit for Approval'
                    : 'Submit for Approval'),
              ),
            ),
          ],
        ),
      ),
    );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        title: door.doorIdTag.isEmpty
            ? 'Door No: ${door.number} – Remedial'
            : 'Door No: ${door.doorIdTag}',
        workspaceKey: widget.workspaceKey,
        currentRoute:
            '/workspace/$workspaceSlug/remedials/${widget.surveyId}/doors/${widget.doorId}',
        workflowLabel: 'Remedial Works',
        drawerRoute: '/workspace/$workspaceSlug/modules/remedials/projects',
        surveyId: widget.surveyId,
        body: pageBody,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(door.doorIdTag.isEmpty
            ? 'Door No: ${door.number} – Remedial'
            : 'Door No: ${door.doorIdTag}'),
        bottom:
            WorkspaceSwitchCardsBar(currentWorkspaceKey: widget.workspaceKey),
        actions: [
          IconButton(
            tooltip: 'View Drawing',
            onPressed: () => ProjectDrawingAccess.showDrawingPicker(
              context: context,
              survey: survey,
              preferredLevel: door.floor,
            ),
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/modules/remedials/projects'),
      body: pageBody,
    );
  }

  Widget _completionStatusBanner(RemedialItem item) {
    final hasEvidence = item.afterRepairPhotos.isNotEmpty;
    final color = hasEvidence ? Colors.green : Colors.red;
    final label = hasEvidence ? 'COMPLETED' : 'NOT COMPLETED';
    final subtitle = hasEvidence
        ? (item.completedBy.trim().isEmpty
            ? 'Completion evidence uploaded.'
            : 'Completion evidence uploaded by ${item.completedBy}.')
        : 'Waiting for completion photo evidence.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _currentUserIdentity(AuthState auth) {
    final name = auth.currentUser?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = auth.email.trim();
    if (email.isNotEmpty) return email;
    return auth.uid.trim();
  }
}
