import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/branding_resolver.dart';
import '../../../app/ui/photo_viewer.dart';
import '../../../app/ui/selection_controls.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../../auth/current_user_role.dart';
import '../../../core/files/pdf_download_saver.dart';
import '../../../core/media/camera_capture_helper.dart';
import '../../disclaimer/data/disclaimer_providers.dart';
import '../../disclaimer/domain/disclaimer_models.dart';
import '../../disclaimer/ui/disclaimer_capture_sheet.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../reports/domain/report_file_naming.dart';
import '../../settings/state/settings_controller.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/pdf/web_download_stub.dart'
    if (dart.library.html) '../../surveys/pdf/web_download.dart';
import '../../surveys/state/survey_controller.dart';
import '../../surveys/ui/project_drawing_viewer.dart';
import '../pdf/remedial_pdf.dart';

enum _SignatureInputMethod { draw, upload, initials }

class RemedialReviewScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final String doorId;
  final String workspaceKey;

  const RemedialReviewScreen({
    super.key,
    required this.surveyId,
    required this.doorId,
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<RemedialReviewScreen> createState() =>
      _RemedialReviewScreenState();
}

class _RemedialReviewScreenState extends ConsumerState<RemedialReviewScreen> {
  final _finalManagerComments = TextEditingController();
  final _jobRefOverride = TextEditingController();
  final _approverName = TextEditingController();
  late final TextEditingController _maintainerName;
  late final TextEditingController _maintainerNumber;
  final _signatureInitials = TextEditingController();

  final Map<String, bool?> _defectPassById = {};
  final Map<String, TextEditingController> _defectFailCommentById = {};

  bool _maintenanceLabelFitted = true;
  bool _maintainerIdentityConfirmed = false;
  DateTime? _nextMaintenanceDueDate;
  int _maintenanceIntervalMonths = 12;
  bool _customMaintenanceInterval = false;
  final _customIntervalController = TextEditingController(text: '12');
  bool _reviewFieldsSeeded = false;
  bool _useManualSignatureOverride = false;
  bool _approvalDisclaimerInFlight = false;
  _SignatureInputMethod _signatureInputMethod = _SignatureInputMethod.initials;
  final List<Offset?> _signatureDrawPoints = [];
  Uint8List? _uploadedSignatureBytes;
  String _uploadedSignatureName = '';
  bool _isCompletingReviewAction = false;
  bool _isGeneratingPdf = false;
  bool _redirectingFromStaleRoute = false;

  InspectionWorkspace get _workspace =>
      parseInspectionWorkspaceKey(widget.workspaceKey) ??
      InspectionWorkspace.fireDoor;

  @override
  void initState() {
    super.initState();
    _maintainerName = TextEditingController();
    _maintainerNumber = TextEditingController();
  }

  @override
  void dispose() {
    _finalManagerComments.dispose();
    _jobRefOverride.dispose();
    _approverName.dispose();
    _maintainerName.dispose();
    _maintainerNumber.dispose();
    _customIntervalController.dispose();
    _signatureInitials.dispose();
    for (final controller in _defectFailCommentById.values) {
      controller.dispose();
    }
    super.dispose();
  }

  DateTime _effectiveMaintenanceCompletedDate(Door door) {
    final completedDates = List<DateTime>.from(
      door.remedialItems
          .where((item) =>
              item.status == RemedialStatus.approved &&
              item.completedDate != null)
          .map((item) => item.completedDate!)
          .toList(),
    );
    if (completedDates.isEmpty) return DateTime.now();
    try {
      if (completedDates.length > 1) {
        completedDates.sort((a, b) => a.compareTo(b));
      }
    } catch (e) {
      debugPrint('Sort error (remedial completed dates): $e');
    }
    return completedDates.last;
  }

  DateTime _addMonths(DateTime date, int months) {
    final safeMonths = months <= 0 ? 12 : months;
    final monthIndex = date.month - 1 + safeMonths;
    final year = date.year + (monthIndex ~/ 12);
    final month = (monthIndex % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = math.min(date.day, lastDay);
    return DateTime(year, month, day);
  }

  void _syncIntervalAndDueDateFromDoor(Door door) {
    final interval = door.maintenanceIntervalMonths > 0
        ? door.maintenanceIntervalMonths
        : 12;
    _maintenanceIntervalMonths = interval;
    _customMaintenanceInterval =
        !(interval == 3 || interval == 6 || interval == 12 || interval == 24);
    _customIntervalController.text = interval.toString();
    _nextMaintenanceDueDate =
        _addMonths(_effectiveMaintenanceCompletedDate(door), interval);
  }

  void _recalculateDueDate(Door door) {
    _nextMaintenanceDueDate = _addMonths(
        _effectiveMaintenanceCompletedDate(door), _maintenanceIntervalMonths);
  }

  void _syncDefectDecisionState(List<RemedialItem> items) {
    for (final item in items) {
      _defectPassById.putIfAbsent(item.id, () {
        if (item.status == RemedialStatus.approved) return true;
        if (item.status == RemedialStatus.rejectedNeedsRework) return false;
        return null;
      });
      _defectFailCommentById.putIfAbsent(item.id, () {
        final existing = item.managerRejectionNote.trim().isNotEmpty
            ? item.managerRejectionNote
            : item.rejectionNote;
        return TextEditingController(text: existing);
      });
    }
  }

  bool _isApprovalAllowed(List<RemedialItem> items) {
    if (items.isEmpty) return false;
    // All items must be set to Pass; manager approval photos are optional (recommended)
    return items.every((item) => _defectPassById[item.id] == true);
  }

  bool _canReturnForRework(List<RemedialItem> items) {
    if (items.isEmpty) return false;
    final hasFail = items.any((item) => _defectPassById[item.id] == false);
    if (!hasFail) return false;
    // Each failed item must have a rejection comment; rejection photos are optional
    return items.where((item) => _defectPassById[item.id] == false).every(
          (item) => _defectFailCommentById[item.id]!.text.trim().isNotEmpty,
        );
  }

  Future<RemedialPhoto?> _takeManagerEvidencePhoto({
    required String remedialItemId,
    required String issueId,
    required String type,
  }) async {
    final x = await CameraCaptureHelper.pickImage(context, imageQuality: 85);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    return RemedialPhoto(
      projectId: widget.surveyId,
      doorId: widget.doorId,
      remedialItemId: remedialItemId,
      issueId: issueId,
      type: type,
      fileName: x.name.isEmpty
          ? 'manager_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : x.name,
      mimeType: 'image/jpeg',
      bytes: bytes,
    );
  }

  Future<List<RemedialPhoto>> _uploadManagerEvidencePhotos({
    required String remedialItemId,
    required String issueId,
    required String type,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return const [];
    final photos = <RemedialPhoto>[];
    for (final f in result.files) {
      if (f.bytes == null || f.bytes!.isEmpty) continue;
      photos.add(
        RemedialPhoto(
          projectId: widget.surveyId,
          doorId: widget.doorId,
          remedialItemId: remedialItemId,
          issueId: issueId,
          type: type,
          fileName: f.name,
          mimeType: 'image/*',
          bytes: f.bytes!,
        ),
      );
    }
    return photos;
  }

  bool _hasValidSignatureInput({required bool hasDisclaimerSignature}) {
    if (!_useManualSignatureOverride) {
      return hasDisclaimerSignature;
    }
    switch (_signatureInputMethod) {
      case _SignatureInputMethod.draw:
        return _signatureDrawPoints.any((p) => p != null);
      case _SignatureInputMethod.upload:
        return _uploadedSignatureBytes != null &&
            _uploadedSignatureBytes!.isNotEmpty;
      case _SignatureInputMethod.initials:
        return _signatureInitials.text.trim().isNotEmpty;
    }
  }

  Future<Uint8List?> _drawnSignatureBytes() async {
    final points = _signatureDrawPoints.whereType<Offset>().toList();
    if (points.isEmpty) return null;

    var minX = points.first.dx;
    var minY = points.first.dy;
    var maxX = points.first.dx;
    var maxY = points.first.dy;

    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }

    const padding = 8.0;
    final width = (maxX - minX + padding * 2).clamp(64.0, 800.0);
    final height = (maxY - minY + padding * 2).clamp(32.0, 320.0);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.2
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;

    Offset? previous;
    for (final p in _signatureDrawPoints) {
      if (p == null) {
        previous = null;
        continue;
      }
      final shifted = Offset(p.dx - minX + padding, p.dy - minY + padding);
      if (previous != null) {
        canvas.drawLine(previous, shifted, paint);
      }
      previous = shifted;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), height.ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<List<int>> _signatureBytesForSave() async {
    switch (_signatureInputMethod) {
      case _SignatureInputMethod.upload:
        return _uploadedSignatureBytes?.toList() ?? const [];
      case _SignatureInputMethod.draw:
        return (await _drawnSignatureBytes())?.toList() ?? const [];
      case _SignatureInputMethod.initials:
        return const [];
    }
  }

  Future<void> _pickSignatureImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;
    setState(() {
      _uploadedSignatureBytes = bytes;
      _uploadedSignatureName = file.name;
    });
  }

  String? _nextDoorId(Survey survey, String currentDoorId) {
    final candidates = survey.doors
        .where(
          (d) =>
              !d.replacementRequired &&
              (d.remedialItems
                      .any((i) => i.severity.toLowerCase() != 'advisory') ||
                  d.issues.any((i) =>
                      i.severity == IssueSeverity.fail ||
                      i.severity == IssueSeverity.criticalFail) ||
                  d.result == DoorResult.fail),
        )
        .toList();
    if (candidates.isEmpty) return null;
    final currentIndex = candidates.indexWhere((d) => d.id == currentDoorId);
    if (currentIndex == -1) return null;
    if (currentIndex + 1 >= candidates.length) return null;
    return candidates[currentIndex + 1].id;
  }

  bool _isManagerLike(UserRole role) {
    return role == UserRole.manager ||
        role == UserRole.owner ||
        role == UserRole.admin ||
        role == UserRole.superAdmin;
  }

  Future<bool> _ensureApprovalDisclaimer({
    required Survey survey,
    required SurveyController controller,
  }) async {
    final auth = ref.read(authControllerProvider);
    final companyId = auth.companyId;
    final userId = auth.uid.trim();
    if (companyId == null || companyId.isEmpty || userId.isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company or user context is missing.')),
      );
      return false;
    }

    final moduleType = disclaimerAcceptanceScopeForModule(
        inspectionWorkspaceSlug(survey.workspace));

    final localRecord = survey.disclaimerAcceptance;
    if (isDisclaimerAcceptanceCurrent(
      record: localRecord,
      moduleType: moduleType,
      userId: userId,
    )) {
      return true;
    }

    final repo = ref.read(disclaimerRepositoryProvider);
    final existing = await repo.findUserModuleRecord(
      companyId: companyId,
      moduleType: moduleType,
      userId: userId,
    );
    if (existing != null) {
      controller.setSurveyDisclaimerRecord(
          surveyId: survey.id, record: existing);
      return true;
    }

    if (!mounted) return false;
    final accepted = await showDisclaimerCaptureSheet(
      context: context,
      ref: ref,
      companyId: companyId,
      projectId: survey.id,
      reportId: survey.id,
      moduleType: moduleType,
      projectName: survey.reportName.trim().isEmpty
          ? survey.siteName
          : survey.reportName,
      projectNumber: survey.reference,
      reportReference: survey.registerReference,
    );
    if (accepted == null) {
      return false;
    }

    controller.setSurveyDisclaimerRecord(surveyId: survey.id, record: accepted);
    return true;
  }

  Future<void> _showAfterReviewChoice({
    required BuildContext context,
    required Survey survey,
    required String currentDoorId,
  }) async {
    final nextId = _nextDoorId(survey, currentDoorId);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Next Action'),
        content: Text(
          nextId == null
              ? 'Review saved successfully. No next door is available, or return to door list.'
              : 'Review saved successfully. Go to next door or return to door list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'list'),
            child: const Text('Back to doors list'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'next'),
            child: const Text('Next door'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    if (action == 'next') {
      if (nextId != null) {
        context.go(
            '/workspace/${inspectionWorkspaceSlug(_workspace)}/remedials/${widget.surveyId}/doors/$nextId/review');
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more doors')),
      );
      context.go(
          '/workspace/${inspectionWorkspaceSlug(_workspace)}/remedials/${widget.surveyId}/doors');
      return;
    }
    context.go(
        '/workspace/${inspectionWorkspaceSlug(_workspace)}/remedials/${widget.surveyId}/doors');
  }

  Future<void> _showAfterApprovalSuccessDialog({
    required Survey survey,
    required String currentDoorId,
  }) async {
    final nextId = _nextDoorId(survey, currentDoorId);
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Item approved successfully.'),
        content: Text(
          nextId == null
              ? 'Choose what you want to do next.'
              : 'Choose what you want to do next, or move to the next item waiting for review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'list'),
            child: const Text('Back to list'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, 'pdf'),
            child: const Text('Generate PDF report'),
          ),
          if (nextId != null)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'next'),
              child: const Text('Review next item'),
            ),
        ],
      ),
    );

    if (!mounted) return;
    switch (action) {
      case 'next':
        if (nextId != null) {
          context.go(
              '/workspace/${inspectionWorkspaceSlug(_workspace)}/remedials/${widget.surveyId}/doors/$nextId/review');
        }
        return;
      case 'pdf':
        await _downloadCertificate(survey: survey, doorId: currentDoorId);
        return;
      case 'list':
      default:
        context.go(
            '/workspace/${inspectionWorkspaceSlug(_workspace)}/remedials/${widget.surveyId}/doors');
        return;
    }
  }

  Future<void> _downloadCertificate({
    required Survey survey,
    required String doorId,
  }) async {
    final controller =
        ref.read(surveyControllerFamilyProvider(_workspace).notifier);
    final door = controller.getDoorById(surveyId: survey.id, doorId: doorId);
    if (door == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Door not found.')),
      );
      return;
    }
    if (door.remedialStatus != RemedialStatus.approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Door must be approved before generating the certificate.')),
      );
      return;
    }
    setState(() => _isGeneratingPdf = true);
    try {
      final settings = ref.read(settingsControllerProvider);
      final branding = resolvePdfBranding(settings);
      final bytes = await RemedialPdfBuilder.buildSingleApprovedDoorPdf(
        survey,
        door,
        companyName: branding.companyName,
        companyLogoBytes: branding.logoBytes,
        reportHeaderText: branding.reportHeaderText,
        reportFooterText: branding.reportFooterText,
      );
      final name = buildReportFileName(
        settings: settings,
        survey: survey,
        reportType: 'Remedial-Certificate',
        extension: 'pdf',
      );
      if (kIsWeb) {
        downloadBytesWeb(
            bytes: bytes, fileName: name, mimeType: 'application/pdf');
      } else {
        try {
          final saved =
              await PdfDownloadSaver.savePdf(bytes: bytes, fileName: name);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF saved: ${saved.fileName}')),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save PDF to device storage: $e')),
          );
        }
      }
      if (kDebugMode) {
        debugPrint(
            'manager_certificate_download survey=${survey.id} door=${door.id}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Certificate error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(surveyControllerFamilyProvider(_workspace));
    final controller =
        ref.read(surveyControllerFamilyProvider(_workspace).notifier);
    final auth = ref.watch(authControllerProvider);
    final role = ref.watch(currentUserRoleProvider);
    final survey = controller.getById(widget.surveyId);
    final door = controller.getDoorById(
        surveyId: widget.surveyId, doorId: widget.doorId);

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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go(
              '/workspace/${inspectionWorkspaceSlug(_workspace)}/remedials/$fallbackSurveyId/doors/${widget.doorId}/review');
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Door or project not found'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go(
                    '/workspace/${inspectionWorkspaceSlug(_workspace)}/modules/remedials/projects'),
                child: const Text('Open Remedial Projects'),
              ),
            ],
          ),
        ),
      );
    }

    final isManagerLike = _isManagerLike(role);
    if (!isManagerLike) {
      return const Scaffold(
        body: Center(
            child:
                Text('Manager approval access is required for this screen.')),
      );
    }

    final disclaimer = survey.disclaimerAcceptance;
    final hasCurrentUserDisclaimer =
        disclaimer != null && disclaimer.userId.trim() == auth.uid.trim();
    if (!hasCurrentUserDisclaimer && !_approvalDisclaimerInFlight) {
      _approvalDisclaimerInFlight = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final ensured = await _ensureApprovalDisclaimer(
            survey: survey, controller: controller);
        if (!mounted) return;
        setState(() => _approvalDisclaimerInFlight = false);
        if (!context.mounted) return;
        if (!ensured) {
          context.go(
              '/workspace/${inspectionWorkspaceSlug(_workspace)}/remedials/${widget.surveyId}/doors');
        }
      });
    }

    if (!_reviewFieldsSeeded) {
      _syncIntervalAndDueDateFromDoor(door);
      _reviewFieldsSeeded = true;
    }

    final effectiveDisclaimer = survey.disclaimerAcceptance;
    final disclaimerSignatureBytes =
        effectiveDisclaimer?.signatureImageBytes ?? const <int>[];
    final disclaimerSignatureImage = disclaimerSignatureBytes.isNotEmpty
        ? Uint8List.fromList(disclaimerSignatureBytes)
        : null;
    final disclaimerReady = effectiveDisclaimer != null &&
        effectiveDisclaimer.userId.trim() == auth.uid.trim() &&
        disclaimerSignatureImage != null &&
        disclaimerSignatureImage.isNotEmpty;
    final defaultApproverName = effectiveDisclaimer != null &&
            effectiveDisclaimer.inspectorName.trim().isNotEmpty
        ? effectiveDisclaimer.inspectorName.trim()
        : _currentUserIdentity(auth);
    if (_approverName.text.trim().isEmpty ||
        (!_useManualSignatureOverride &&
            door.remedialStatus != RemedialStatus.approved)) {
      _approverName.text = defaultApproverName;
    }

    _syncDefectDecisionState(door.remedialItems);
    final canApproveDoor = _isApprovalAllowed(door.remedialItems);
    final canReturnForRework = _canReturnForRework(door.remedialItems);

    final pageBody = ListView(
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
        _sectionCard(
          title: 'Door Summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryLine(
                  'Door Ref',
                  door.doorIdTag.isEmpty
                      ? 'Door ${door.number}'
                      : door.doorIdTag),
              _summaryLine('Level', door.floor.isEmpty ? '-' : door.floor),
              _summaryLine('Location', door.area.isEmpty ? '-' : door.area),
              _summaryLine('Fire rating', door.fireRating.name.toUpperCase()),
              _summaryLine('Inspection result', door.result.name.toUpperCase()),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final item in door.remedialItems) ...[
          _issueCard(item),
          const SizedBox(height: 10),
        ],
        _sectionCard(
          title: 'Final Approval Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _finalManagerComments,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Final manager comments',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _jobRefOverride,
                decoration: const InputDecoration(
                  labelText:
                      'Certificate / project reference override (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _maintainerName,
                      decoration: const InputDecoration(
                        labelText: 'Approved maintainer name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _maintainerNumber,
                      decoration: const InputDecoration(
                        labelText: 'Approved maintainer number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey<int>(_customMaintenanceInterval
                          ? -1
                          : _maintenanceIntervalMonths),
                      initialValue: _customMaintenanceInterval
                          ? -1
                          : _maintenanceIntervalMonths,
                      decoration: const InputDecoration(
                        labelText: 'Maintenance interval',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3 months')),
                        DropdownMenuItem(value: 6, child: Text('6 months')),
                        DropdownMenuItem(value: 12, child: Text('12 months')),
                        DropdownMenuItem(value: 24, child: Text('24 months')),
                        DropdownMenuItem(
                            value: -1, child: Text('Custom interval')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          if (value == -1) {
                            _customMaintenanceInterval = true;
                            final parsed = int.tryParse(
                                _customIntervalController.text.trim());
                            if (parsed != null && parsed > 0) {
                              _maintenanceIntervalMonths = parsed;
                              _recalculateDueDate(door);
                            }
                          } else {
                            _customMaintenanceInterval = false;
                            _maintenanceIntervalMonths = value;
                            _customIntervalController.text = value.toString();
                            _recalculateDueDate(door);
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              if (_customMaintenanceInterval) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _customIntervalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Custom maintenance interval (months)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null || parsed <= 0) return;
                    setState(() {
                      _maintenanceIntervalMonths = parsed;
                      _recalculateDueDate(door);
                    });
                  },
                ),
              ],
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Next maintenance due date (auto)',
                  border: OutlineInputBorder(),
                ),
                child: Text(_fmtDate(_nextMaintenanceDueDate)),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _maintenanceLabelFitted,
                onChanged: (v) => setState(() => _maintenanceLabelFitted = v),
                title: const Text('Maintenance label fitted'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _maintainerIdentityConfirmed,
                onChanged: (v) =>
                    setState(() => _maintainerIdentityConfirmed = v ?? false),
                title: const Text('I confirm approved maintainer identity'),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _approverName,
                readOnly: !_useManualSignatureOverride,
                decoration: InputDecoration(
                  labelText: _useManualSignatureOverride
                      ? 'Approver full name'
                      : 'Approver full name (from disclaimer)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Manager sign-off',
                  border: OutlineInputBorder(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_approvalDisclaimerInFlight) ...[
                      const Text('Checking required disclaimer record...'),
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ] else if (!_useManualSignatureOverride) ...[
                      Text(
                        disclaimerReady
                            ? 'Approver name, signature, and sign-off date are sourced from the saved disclaimer record for this project.'
                            : 'A saved disclaimer record is required before approval. Complete the disclaimer to continue.',
                      ),
                      if (effectiveDisclaimer != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Disclaimer accepted on: ${_fmtDate(effectiveDisclaimer.disclaimerAcceptedAt ?? effectiveDisclaimer.createdAt)}',
                        ),
                      ],
                      if (disclaimerSignatureImage != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(disclaimerSignatureImage,
                              height: 72),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(
                              () => _useManualSignatureOverride = true),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Use manual override instead'),
                        ),
                      ),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: disclaimerReady
                              ? () => setState(
                                  () => _useManualSignatureOverride = false)
                              : null,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('Use disclaimer sign-off'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<_SignatureInputMethod>(
                        segments: const [
                          ButtonSegment<_SignatureInputMethod>(
                            value: _SignatureInputMethod.draw,
                            label: Text('Draw in-app'),
                            icon: Icon(Icons.draw_outlined),
                          ),
                          ButtonSegment<_SignatureInputMethod>(
                            value: _SignatureInputMethod.upload,
                            label: Text('Upload image'),
                            icon: Icon(Icons.upload_file_outlined),
                          ),
                          ButtonSegment<_SignatureInputMethod>(
                            value: _SignatureInputMethod.initials,
                            label: Text('Use initials'),
                            icon: Icon(Icons.text_fields_outlined),
                          ),
                        ],
                        selected: {_signatureInputMethod},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _signatureInputMethod = selection.first;
                            if (_signatureInputMethod ==
                                _SignatureInputMethod.draw) {}
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      if (_signatureInputMethod ==
                          _SignatureInputMethod.draw) ...[
                        Container(
                          width: double.infinity,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() => _signatureDrawPoints
                                  .add(details.localPosition));
                            },
                            onPanEnd: (_) =>
                                setState(() => _signatureDrawPoints.add(null)),
                            child: CustomPaint(
                              painter:
                                  _SignaturePadPainter(_signatureDrawPoints),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  setState(() => _signatureDrawPoints.clear()),
                              icon: const Icon(Icons.clear_outlined),
                              label: const Text('Clear drawing'),
                            ),
                          ],
                        ),
                      ],
                      if (_signatureInputMethod ==
                          _SignatureInputMethod.upload) ...[
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _pickSignatureImage,
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Choose signature image'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _uploadedSignatureName.isEmpty
                              ? 'No signature image selected.'
                              : 'Selected: $_uploadedSignatureName',
                        ),
                        if (_uploadedSignatureBytes != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(_uploadedSignatureBytes!,
                                height: 72),
                          ),
                        ],
                      ],
                      if (_signatureInputMethod ==
                          _SignatureInputMethod.initials) ...[
                        TextFormField(
                          controller: _signatureInitials,
                          maxLength: 8,
                          decoration: const InputDecoration(
                            labelText: 'Manager initials',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                    if (!_hasValidSignatureInput(
                        hasDisclaimerSignature: disclaimerReady)) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Complete the selected signature method before approval.',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (!canApproveDoor ||
                        !_hasValidSignatureInput(
                            hasDisclaimerSignature: disclaimerReady) ||
                        _isCompletingReviewAction ||
                        !disclaimerReady)
                    ? null
                    : () async {
                        if (_isCompletingReviewAction) return;
                        if (!_maintainerIdentityConfirmed) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Please confirm approved maintainer identity before approval.')),
                          );
                          return;
                        }
                        setState(() => _isCompletingReviewAction = true);
                        final List<int> signatureBytes =
                            _useManualSignatureOverride
                                ? await _signatureBytesForSave()
                                : disclaimerSignatureBytes;
                        final approvedBy = _approverName.text.trim().isEmpty
                            ? _currentUserIdentity(auth)
                            : _approverName.text.trim();
                        final defectPassByItemId = {
                          for (final item in door.remedialItems)
                            item.id: _defectPassById[item.id] == true,
                        };
                        controller.approveDoorRemedial(
                          surveyId: widget.surveyId,
                          doorId: widget.doorId,
                          approvedBy: approvedBy,
                          defectPassByItemId: defectPassByItemId,
                          comment: _finalManagerComments.text.trim(),
                          maintenanceLabelFitted: _maintenanceLabelFitted,
                          nextMaintenanceDueDate: _nextMaintenanceDueDate,
                          finalManagerComments:
                              _finalManagerComments.text.trim(),
                          signatureAssetPath: '',
                          signatureMethod: _useManualSignatureOverride
                              ? _signatureInputMethod.name
                              : 'disclaimer',
                          signatureInitials: _useManualSignatureOverride
                              ? _signatureInitials.text.trim()
                              : '',
                          signatureImageBytes: signatureBytes,
                          approvedMaintainerName: _maintainerName.text.trim(),
                          approvedMaintainerNumber:
                              _maintainerNumber.text.trim(),
                          certificateJobReferenceOverride:
                              _jobRefOverride.text.trim(),
                          maintenanceIntervalMonths: _maintenanceIntervalMonths,
                        );
                        if (kDebugMode) {
                          debugPrint(
                            'manager_approval action=approve survey=${widget.surveyId} door=${widget.doorId} items=${door.remedialItems.length} by=${_currentUserIdentity(auth)}',
                          );
                        }
                        if (!mounted) return;
                        setState(() => _isCompletingReviewAction = false);
                        await _showAfterApprovalSuccessDialog(
                          survey: survey,
                          currentDoorId: door.id,
                        );
                      },
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Approve Door'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (!canReturnForRework || _isCompletingReviewAction)
                    ? null
                    : () async {
                        if (_isCompletingReviewAction) return;
                        final failedItems = door.remedialItems
                            .where((item) => _defectPassById[item.id] == false)
                            .toList();
                        if (failedItems.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Select Fail for at least one defect before returning this door for rework.')),
                          );
                          return;
                        }
                        final hasMissingFailComment = failedItems.any(
                          (item) => _defectFailCommentById[item.id]!
                              .text
                              .trim()
                              .isEmpty,
                        );
                        if (hasMissingFailComment) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Add a manager rejection comment for each failed defect.')),
                          );
                          return;
                        }
                        setState(() => _isCompletingReviewAction = true);
                        final signatureBytes = await _signatureBytesForSave();
                        final defectPassByItemId = {
                          for (final item in door.remedialItems)
                            item.id: _defectPassById[item.id] == true,
                        };
                        final defectFailCommentByItemId = {
                          for (final item in failedItems)
                            item.id:
                                _defectFailCommentById[item.id]!.text.trim(),
                        };
                        controller.rejectDoorRemedial(
                          surveyId: widget.surveyId,
                          doorId: widget.doorId,
                          approvedBy: _currentUserIdentity(auth),
                          defectPassByItemId: defectPassByItemId,
                          defectFailCommentByItemId: defectFailCommentByItemId,
                          rejectionNote: _finalManagerComments.text.trim(),
                          maintenanceLabelFitted: _maintenanceLabelFitted,
                          nextMaintenanceDueDate: _nextMaintenanceDueDate,
                          finalManagerComments:
                              _finalManagerComments.text.trim(),
                          signatureAssetPath: '',
                          signatureMethod: _signatureInputMethod.name,
                          signatureInitials: _signatureInitials.text.trim(),
                          signatureImageBytes: signatureBytes,
                          approvedMaintainerName: _maintainerName.text.trim(),
                          approvedMaintainerNumber:
                              _maintainerNumber.text.trim(),
                          certificateJobReferenceOverride:
                              _jobRefOverride.text.trim(),
                          maintenanceIntervalMonths: _maintenanceIntervalMonths,
                        );
                        if (kDebugMode) {
                          final failedCount = door.remedialItems
                              .where((i) => _defectPassById[i.id] == false)
                              .length;
                          debugPrint(
                            'manager_approval action=reject survey=${widget.surveyId} door=${widget.doorId} failed=$failedCount by=${_currentUserIdentity(auth)}',
                          );
                        }
                        if (!context.mounted) return;
                        setState(() => _isCompletingReviewAction = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Door returned for rework with per-defect manager fail comments.')),
                        );
                        await _showAfterReviewChoice(
                          context: context,
                          survey: survey,
                          currentDoorId: door.id,
                        );
                      },
                icon: const Icon(Icons.undo_outlined),
                label: const Text('Reject / Return for Rework'),
              ),
            ),
          ],
        ),
        if (door.remedialStatus == RemedialStatus.approved) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Door Approved',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.green,
                      fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  'This door has been approved. You can generate the official remedial report or reopen the decision if approval was made in error.',
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isGeneratingPdf
                        ? null
                        : () => _downloadCertificate(
                            survey: survey, doorId: door.id),
                    icon: _isGeneratingPdf
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(_isGeneratingPdf
                        ? 'Generating…'
                        : 'Generate Approved Remedial Report'),
                    style:
                        FilledButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Reopen / Change Decision'),
                          content: const Text(
                            'This item is already approved. Reopening it will remove the approved/completed status and allow review again. Continue?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Continue'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      controller.reopenDoorRemedial(
                        surveyId: widget.surveyId,
                        doorId: widget.doorId,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Approval reopened. Generate a fresh PDF after the next final decision.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.restart_alt_outlined),
                    label: const Text('Reopen / Change Decision'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (kIsWeb) {
      final workspaceSlug = inspectionWorkspaceSlug(_workspace);
      return FireDoorWebShellScaffold(
        title: 'Manager Review - Door ${door.number}',
        workspaceKey: widget.workspaceKey,
        currentRoute:
            '/workspace/$workspaceSlug/remedials/${widget.surveyId}/doors/${widget.doorId}/review',
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
        title: Text('Manager Review - Door ${door.number}'),
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

  Widget _issueCard(RemedialItem item) {
    final controller =
        ref.read(surveyControllerFamilyProvider(_workspace).notifier);
    final decision = _defectPassById[item.id];
    final failController = _defectFailCommentById[item.id]!;
    final isPass = decision == true;
    final isFail = decision == false;
    final borderColor = isPass
        ? Colors.green.shade400
        : (isFail ? Colors.red.shade400 : Colors.grey.shade300);
    final fillColor = isPass
        ? Colors.green.withValues(alpha: 0.05)
        : (isFail ? Colors.red.withValues(alpha: 0.05) : Colors.transparent);

    return _sectionCard(
      title: _displayIssueTitle(item),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusBadge(item.status),
                _infoBadge('Severity', item.severity),
                _infoBadge(
                  'Worker Completion Evidence',
                  item.afterRepairPhotos.isEmpty ? 'Missing' : 'Completed',
                  color: item.afterRepairPhotos.isEmpty
                      ? Colors.red
                      : Colors.green,
                ),
                _infoBadge(
                  'Manager Decision',
                  isPass ? 'Pass' : (isFail ? 'Fail' : 'Pending'),
                  color: isPass
                      ? Colors.green
                      : (isFail ? Colors.red : const Color(0xFF1565C0)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Manager per-defect review',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppChoicePill(
                  label: 'Pass',
                  selected: isPass,
                  selectedColor: Colors.green,
                  onPressed: () =>
                      setState(() => _defectPassById[item.id] = true),
                ),
                AppChoicePill(
                  label: 'Fail',
                  selected: isFail,
                  selectedColor: AppSelectionColors.selectedFailRed,
                  onPressed: () =>
                      setState(() => _defectPassById[item.id] = false),
                ),
              ],
            ),
            if (isFail) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: failController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Manager rejection reason for this defect',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (failController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Fail comment: ${failController.text.trim()}',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 8),
            _summaryLine('Original inspection note',
                item.originalComment.isEmpty ? '-' : item.originalComment),
            _summaryLine('Worker completion note',
                item.workerNote.isEmpty ? '-' : item.workerNote),
            _optionalSummaryLine('Submitted by', item.submittedBy),
            _optionalSummaryLine('Submitted date', _fmtDate(item.submittedAt)),
            _optionalSummaryLine('Completed by', item.completedBy),
            _optionalSummaryLine(
                'Completed date', _fmtDate(item.completedDate)),
            _optionalSummaryLine('Approved by', item.approvedBy),
            _optionalSummaryLine('Approved date', _fmtDate(item.approvedAt)),
            _optionalSummaryLine('Rejected by', item.rejectedBy),
            _optionalSummaryLine('Rejected date', _fmtDate(item.rejectedAt)),
            _optionalSummaryLine('Rejection note', item.rejectionNote),
            const SizedBox(height: 8),
            const Text('Original inspection evidence',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (item.originalInspectionPhotos.isEmpty)
              const Text('No original inspection evidence attached.')
            else
              _photoWrap(
                  item.originalInspectionPhotos.map((p) => p.bytes).toList()),
            const SizedBox(height: 8),
            const Text('Worker completion evidence',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (item.afterRepairPhotos.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  'Missing completion evidence for this defect.',
                  style:
                      TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
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
                          color: Colors.green.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      item.completedBy.trim().isEmpty
                          ? 'Completion evidence uploaded.'
                          : 'Completion evidence uploaded by ${item.completedBy}.',
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _photoWrap(
                      item.afterRepairPhotos.map((p) => p.bytes).toList()),
                ],
              ),
            const SizedBox(height: 10),
            const Text('Manager approval evidence',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !isPass
                        ? null
                        : () async {
                            final photo = await _takeManagerEvidencePhoto(
                              remedialItemId: item.id,
                              issueId: item.issueId,
                              type: 'managerApproval',
                            );
                            if (photo == null) return;
                            controller.addRemedialManagerApprovalPhotos(
                              surveyId: widget.surveyId,
                              doorId: widget.doorId,
                              remedialItemId: item.id,
                              photos: [photo],
                            );
                          },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !isPass
                        ? null
                        : () async {
                            final photos = await _uploadManagerEvidencePhotos(
                              remedialItemId: item.id,
                              issueId: item.issueId,
                              type: 'managerApproval',
                            );
                            if (photos.isEmpty) return;
                            controller.addRemedialManagerApprovalPhotos(
                              surveyId: widget.surveyId,
                              doorId: widget.doorId,
                              remedialItemId: item.id,
                              photos: photos,
                            );
                          },
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload Photo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (item.managerApprovalPhotos.isEmpty)
              Text(
                isPass
                    ? 'Manager approval photo is optional but recommended for the certificate.'
                    : 'Set decision to Pass to add manager approval evidence.',
                style: TextStyle(
                  color: isPass ? Colors.orange.shade800 : Colors.black54,
                  fontWeight: isPass ? FontWeight.w600 : FontWeight.w400,
                ),
              )
            else
              _remedialPhotoWrap(
                photos: item.managerApprovalPhotos,
                onDelete: !isPass
                    ? null
                    : (index) {
                        final next = [...item.managerApprovalPhotos]
                          ..removeAt(index);
                        controller.setRemedialManagerApprovalPhotos(
                          surveyId: widget.surveyId,
                          doorId: widget.doorId,
                          remedialItemId: item.id,
                          photos: next,
                        );
                      },
              ),
            const SizedBox(height: 10),
            const Text('Manager rejection evidence',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !isFail
                        ? null
                        : () async {
                            final photo = await _takeManagerEvidencePhoto(
                              remedialItemId: item.id,
                              issueId: item.issueId,
                              type: 'managerRejection',
                            );
                            if (photo == null) return;
                            controller.addRemedialManagerRejectionPhotos(
                              surveyId: widget.surveyId,
                              doorId: widget.doorId,
                              remedialItemId: item.id,
                              photos: [photo],
                            );
                          },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !isFail
                        ? null
                        : () async {
                            final photos = await _uploadManagerEvidencePhotos(
                              remedialItemId: item.id,
                              issueId: item.issueId,
                              type: 'managerRejection',
                            );
                            if (photos.isEmpty) return;
                            controller.addRemedialManagerRejectionPhotos(
                              surveyId: widget.surveyId,
                              doorId: widget.doorId,
                              remedialItemId: item.id,
                              photos: photos,
                            );
                          },
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload Photo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (item.managerRejectionPhotos.isEmpty)
              Text(
                isFail
                    ? 'Manager rejection photo is optional. Only a rejection comment is required.'
                    : 'Set decision to Fail to add manager rejection evidence.',
                style: TextStyle(
                  color: isFail ? Colors.red : Colors.black54,
                  fontWeight: isFail ? FontWeight.w700 : FontWeight.w400,
                ),
              )
            else
              _remedialPhotoWrap(
                photos: item.managerRejectionPhotos,
                onDelete: !isFail
                    ? null
                    : (index) {
                        final next = [...item.managerRejectionPhotos]
                          ..removeAt(index);
                        controller.setRemedialManagerRejectionPhotos(
                          surveyId: widget.surveyId,
                          doorId: widget.doorId,
                          remedialItemId: item.id,
                          photos: next,
                        );
                      },
              ),
          ],
        ),
      ),
    );
  }

  Widget _photoWrap(List<List<int>> bytesList) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < bytesList.length; i++)
          GestureDetector(
            onTap: () => showPhotoViewer(
                context: context, photos: bytesList, initialIndex: i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(Uint8List.fromList(bytesList[i]),
                  width: 90, height: 90, fit: BoxFit.cover),
            ),
          ),
      ],
    );
  }

  Widget _remedialPhotoWrap({
    required List<RemedialPhoto> photos,
    void Function(int index)? onDelete,
  }) {
    final bytesList = photos.map((p) => p.bytes).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < photos.length; i++)
          Stack(
            children: [
              GestureDetector(
                onTap: () => showPhotoViewer(
                    context: context, photos: bytesList, initialIndex: i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(Uint8List.fromList(photos[i].bytes),
                      width: 90, height: 90, fit: BoxFit.cover),
                ),
              ),
              if (onDelete != null)
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

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
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
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _summaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87),
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _optionalSummaryLine(String label, String value) {
    if (value.trim().isEmpty || value.trim() == '-')
      return const SizedBox.shrink();
    return _summaryLine(label, value);
  }

  Widget _statusBadge(RemedialStatus status) {
    final data = switch (status) {
      RemedialStatus.pending => ('Pending', Colors.blueGrey),
      RemedialStatus.inProgress => ('In Progress', Colors.orange),
      RemedialStatus.completedByWorker => ('In Progress', Colors.orange),
      RemedialStatus.forApproval => ('For Approval', const Color(0xFF1565C0)),
      RemedialStatus.approved => ('Approved', Colors.green),
      RemedialStatus.rejectedNeedsRework => ('Returned for Rework', Colors.red),
    };
    return _infoBadge(data.$1, '', color: data.$2, compact: true);
  }

  Widget _infoBadge(String label, String value,
      {Color color = const Color(0xFF1565C0), bool compact = false}) {
    final text = compact || value.isEmpty ? label : '$label: $value';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  String _displayIssueTitle(RemedialItem item) {
    final raw = item.title.trim().isEmpty ? item.category : item.title;
    final noPrefix = raw.replaceFirst(RegExp(r'^CHECK:'), '');
    final spaced = noPrefix.replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    final words = spaced
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ')
        .trim();
    return words.isEmpty ? 'Inspection Issue' : words;
  }

  String _fmtDate(DateTime? date) {
    if (date == null) return '';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year}';
  }

  String _currentUserIdentity(AuthState auth) {
    final name = auth.currentUser?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = auth.email.trim();
    if (email.isNotEmpty) return email;
    return auth.uid.trim();
  }
}

class _SignaturePadPainter extends CustomPainter {
  final List<Offset?> points;

  _SignaturePadPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) {
        canvas.drawLine(a, b, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePadPainter oldDelegate) =>
      oldDelegate.points != points;
}
