// DEPRECATED: Legacy shared survey inspection flow.
// Active runtime flow uses workspace module routes under /workspace/*/inspection/*.
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/branding_resolver.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_controller.dart';
import '../../storage/data/company_file_providers.dart';
import '../../storage/domain/company_file_record.dart';
import '../domain/models.dart';
import '../pdf/survey_pdf.dart';
import '../pdf/web_download_stub.dart'
  if (dart.library.html) '../pdf/web_download.dart';
import '../../../auth/auth_state.dart';
import '../state/survey_controller.dart';
import 'door_detail_screen.dart';
import 'project_drawing_viewer.dart';

class DoorsScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final String moduleKey;
  final String routePrefix;
  final String workspaceKey;

  const DoorsScreen({
    super.key,
    required this.surveyId,
    this.moduleKey = 'inspection',
    this.routePrefix = '/surveys',
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<DoorsScreen> createState() => _DoorsScreenState();
}

enum _ExportType { singleDoor, separatePerDoor, combinedAllDoors }

enum _ExportAction { download, email }

class _DoorsScreenState extends ConsumerState<DoorsScreen> {
  bool _shownDisclaimer = false;
  bool _creatingNewReport = false;

  bool _isSavedDoor(Door d) => d.doorIdTag.trim().isNotEmpty;

  String _mimeForName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  String _displayNameFromFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return fileName;
    return fileName.substring(0, dot);
  }

  String _levelHintFromFile(String fileName) {
    final n = fileName.toLowerCase();
    if (n.contains('ground')) return 'Ground Floor';
    if (n.contains('level 1') || n.contains('l1') || n.contains('first')) return 'Level 1';
    if (n.contains('level 2') || n.contains('l2') || n.contains('second')) return 'Level 2';
    if (n.contains('basement') || n.contains('lower ground') || n.contains('b1')) return 'Basement';
    return 'Other';
  }

  Future<void> _uploadDrawings({
    required Survey survey,
    required SurveyController controller,
  }) async {
    final auth = ref.read(authControllerProvider);
    final companyId = auth.companyId;
    if (companyId == null || companyId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company workspace is missing.')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null) return;

    final repo = ref.read(companyFileRepositoryProvider);
    final drawings = <ProjectDrawing>[];
    var failed = 0;

    for (final f in result.files) {
      if (f.bytes == null || f.bytes!.isEmpty) continue;
      final mime = _mimeForName(f.name);
      try {
        final record = await repo.uploadBytes(
          companyId: companyId,
          entityType: 'surveyDrawing',
          entityId: survey.id,
          createdByUid: auth.uid,
          fileName: f.name,
          bytes: f.bytes!,
          mimeType: mime,
          kind: CompanyFileKind.drawing,
          tags: [_levelHintFromFile(f.name)],
        );

        drawings.add(
          ProjectDrawing(
            id: record.fileId,
            name: _displayNameFromFile(f.name),
            fileName: f.name,
            mimeType: mime,
            level: _levelHintFromFile(f.name),
            bytes: f.bytes!,
            cloudStoragePath: record.storagePath,
            cloudDownloadUrl: record.downloadUrl,
          ),
        );
      } catch (_) {
        failed++;
      }
    }

    if (drawings.isEmpty || !mounted) return;
    controller.addProjectDrawings(surveyId: survey.id, drawings: drawings);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '${drawings.length} drawing(s) uploaded and synced.'
              : '${drawings.length} drawing(s) synced, $failed failed.',
        ),
      ),
    );
  }

  Future<void> _openDrawingOrPrompt({
    required Survey survey,
    required SurveyController controller,
    String? preferredLevel,
  }) async {
    if (survey.projectDrawings.isEmpty) {
      final uploadNow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No drawing uploaded. Upload now?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload Drawing')),
          ],
        ),
      );
      if (uploadNow == true) {
        await _uploadDrawings(survey: survey, controller: controller);
      }
      return;
    }

    final result = await ProjectDrawingAccess.showDrawingPicker(
      context: context,
      survey: survey,
      preferredLevel: preferredLevel,
    );
    if (!mounted || result?.addDefect != true) return;

    controller.addDoor(widget.surveyId);
    final updatedSurvey = controller.getById(widget.surveyId);
    if (updatedSurvey == null || updatedSurvey.doors.isEmpty) return;
    final newDoorId = updatedSurvey.doors.last.id;

    controller.updateDoor(
      surveyId: widget.surveyId,
      doorId: newDoorId,
      update: (d) => d.copyWith(
        doorIdTag: result!.pin.label.trim().isNotEmpty ? result.pin.label.trim() : result.pin.doorNumber.trim(),
        fireStoppingItemType: 'drawing=${result.drawing.id};pin=${result.pin.id}',
      ),
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoorDetailScreen(
          surveyId: widget.surveyId,
          mode: DoorDetailMode.edit,
          existingDoorId: newDoorId,
          isTempDraft: true,
          moduleKey: widget.moduleKey,
          routePrefix: widget.routePrefix,
          workspaceKey: widget.workspaceKey,
        ),
      ),
    );
  }

  Future<void> _exportPdf({
    required BuildContext context,
    required Survey survey,
    Door? door,
    required List<int> companyLogoBytes,
    required String companyName,
    required String reportHeaderText,
    required String reportFooterText,
    required AppSettings settings,
    required String fileName,
    _ExportAction? presetAction,
  }) async {
    final action = presetAction ??
        await showModalBottomSheet<_ExportAction>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Download PDF'),
                  onTap: () => Navigator.pop(ctx, _ExportAction.download),
                ),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Share by email'),
                  subtitle: const Text('Opens your share sheet (Mail / Gmail / Outlook etc).'),
                  onTap: () => Navigator.pop(ctx, _ExportAction.email),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );

    if (!context.mounted) return;
    if (action == null) return;

    try {
      final Uint8List bytes;
      if (door == null) {
        bytes = await SurveyPdfBuilder.buildWholeObjectPdf(
          survey,
          companyLogoBytes: companyLogoBytes,
          companyName: companyName,
          companyAddress: settings.companyProfile.address,
          companyEmail: settings.companyProfile.email,
          companyPhone: settings.companyProfile.phone,
          reportHeaderText: reportHeaderText,
          reportFooterText: reportFooterText,
          generatedBy: _generatedBy(survey),
        );
      } else {
        bytes = await SurveyPdfBuilder.buildSingleDoorPdf(
          survey,
          door,
          companyLogoBytes: companyLogoBytes,
          companyName: companyName,
          companyAddress: settings.companyProfile.address,
          companyEmail: settings.companyProfile.email,
          companyPhone: settings.companyProfile.phone,
          reportHeaderText: reportHeaderText,
          reportFooterText: reportFooterText,
          generatedBy: _generatedBy(survey),
        );
      }

      if (!context.mounted) return;

      if (action == _ExportAction.download) {
        if (kIsWeb) {
          downloadBytesWeb(bytes: bytes, fileName: fileName, mimeType: 'application/pdf');
        } else {
          await Printing.layoutPdf(onLayout: (_) async => bytes);
        }
        return;
      }

      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e')),
      );
    }
  }

  String _sanitizeFileName(String input) {
    var s = input
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    s = s.replaceAll(RegExp(r'[ .]+$'), '');
    if (s.length > 80) s = s.substring(0, 80);
    return s;
  }

  String _jobNumberOrEmpty(Survey survey) {
    return survey.reference.trim();
  }

  String _projectNameOrFallback(Survey survey) {
    final name = survey.reportName.trim().isNotEmpty ? survey.reportName.trim() : survey.siteName.trim();
    return name.isEmpty ? 'Project' : name;
  }

  String _dateTag(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    return '$day-$month-$year';
  }

  String _surveyPdfBaseName(Survey survey) {
    final parts = <String>['RMA-058', _dateTag(survey.reportDate)];
    final jobNo = _jobNumberOrEmpty(survey);
    if (jobNo.isNotEmpty) parts.add(jobNo);
    parts.add(_projectNameOrFallback(survey));
    return _sanitizeFileName(parts.join('_'));
  }

  String _singleDoorPdfFileName(Survey survey, AppSettings settings) {
    final _ = settings;
    return '${_surveyPdfBaseName(survey)}.pdf';
  }

  String _combinedPdfFileName(Survey survey, AppSettings settings) {
    final _ = settings;
    return '${_surveyPdfBaseName(survey)}.pdf';
  }

  String _zipExportFileName(Survey survey, AppSettings settings) {
    final _ = settings;
    return '${_surveyPdfBaseName(survey)}.zip';
  }

  String _generatedBy(Survey survey) {
    final inspector = survey.reportCompletedBy.trim();
    return inspector.isEmpty ? 'System User' : inspector;
  }

  Future<Uint8List> _buildSeparateDoorZip(
    Survey survey, {
    required List<int> companyLogoBytes,
    required String companyName,
    required String reportHeaderText,
    required String reportFooterText,
    required AppSettings settings,
  }) async {
    final archive = Archive();
    final savedDoors = survey.doors.where(_isSavedDoor).toList();

    for (final door in savedDoors) {
      final pdfBytes = await SurveyPdfBuilder.buildSingleDoorPdf(
        survey,
        door,
        companyLogoBytes: companyLogoBytes,
        companyName: companyName,
        companyAddress: settings.companyProfile.address,
        companyEmail: settings.companyProfile.email,
        companyPhone: settings.companyProfile.phone,
        reportHeaderText: reportHeaderText,
        reportFooterText: reportFooterText,
        generatedBy: _generatedBy(survey),
      );
      final name = _sanitizeFileName(
        'Door-${door.number.toString().padLeft(3, '0')}-${door.doorIdTag.trim().isEmpty ? door.id : door.doorIdTag.trim()}.pdf',
      );
      archive.addFile(ArchiveFile(name, pdfBytes.length, pdfBytes));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> _showProjectExportDialog({
    required BuildContext context,
    required Survey survey,
    required AppSettings settings,
  }) async {
    final isFireStopping = widget.workspaceKey == 'fire-stopping';
    final type = await showModalBottomSheet<_ExportType>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(isFireStopping ? 'Single Item PDF' : 'Single Door PDF'),
              subtitle: Text(
                isFireStopping
                    ? 'Choose one item — exports a direct PDF, no ZIP.'
                    : 'Choose one door — exports a direct PDF, no ZIP.',
              ),
              onTap: () => Navigator.pop(ctx, _ExportType.singleDoor),
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: Text(isFireStopping ? 'All Items — Combined PDF' : 'All Doors — Combined PDF'),
              subtitle: Text(
                isFireStopping
                    ? 'One PDF with every item on successive pages.'
                    : 'One PDF with every door on successive pages.',
              ),
              onTap: () => Navigator.pop(ctx, _ExportType.combinedAllDoors),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(isFireStopping ? 'All Items — ZIP (one PDF per item)' : 'All Doors — ZIP (one PDF per door)'),
              subtitle: Text(
                isFireStopping
                    ? 'Individual PDF per item, packaged as a ZIP file.'
                    : 'Individual PDF per door, packaged as a ZIP file.',
              ),
              onTap: () => Navigator.pop(ctx, _ExportType.separatePerDoor),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!context.mounted) return;
    if (type == null) return;

    final savedDoors = survey.doors.where(_isSavedDoor).toList();
    if (savedDoors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFireStopping
                ? 'No saved reports to export yet. Create a report and save it first.'
                : 'No saved doors to export yet. Add Door ID / Ref and save first.',
          ),
        ),
      );
      return;
    }
    final branding = resolvePdfBranding(settings);

    // ── Single item/door PDF ───────────────────────────────────────────────────
    if (type == _ExportType.singleDoor) {
      final chosenDoor = await showModalBottomSheet<Door>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Choose record to export', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in savedDoors)
                      ListTile(
                        leading: Icon(isFireStopping ? Icons.inventory_2_outlined : Icons.door_front_door_outlined),
                        title: Text(d.doorIdTag.trim()),
                        subtitle: Text([
                          if (d.floor.trim().isNotEmpty) 'Level: ${d.floor}',
                          if (d.area.trim().isNotEmpty) d.area,
                        ].join(' · ')),
                        onTap: () => Navigator.pop(ctx, d),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (!context.mounted || chosenDoor == null) return;
      await _exportPdf(
        context: context,
        survey: survey,
        door: chosenDoor,
        companyLogoBytes: branding.logoBytes,
        companyName: branding.companyName,
        reportHeaderText: branding.reportHeaderText,
        reportFooterText: branding.reportFooterText,
        settings: settings,
        fileName: _singleDoorPdfFileName(survey, settings),
        presetAction: kIsWeb ? _ExportAction.download : null,
      );
      return;
    }

    // ── All records — Combined PDF ─────────────────────────────────────────────
    if (type == _ExportType.combinedAllDoors) {
      await _exportPdf(
        context: context,
        survey: survey,
        companyLogoBytes: branding.logoBytes,
        companyName: branding.companyName,
        reportHeaderText: branding.reportHeaderText,
        reportFooterText: branding.reportFooterText,
        settings: settings,
        fileName: _combinedPdfFileName(survey, settings),
        presetAction: kIsWeb ? _ExportAction.download : null,
      );
      return;
    }

    // ── All records — ZIP (one PDF per record) ────────────────────────────────
    final action = kIsWeb
        ? _ExportAction.download
        : await showModalBottomSheet<_ExportAction>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Download ZIP'),
                    onTap: () => Navigator.pop(ctx, _ExportAction.download),
                  ),
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Share ZIP'),
                    onTap: () => Navigator.pop(ctx, _ExportAction.email),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );

    if (!context.mounted || action == null) return;

    try {
      final zipBytes = await _buildSeparateDoorZip(
        survey,
        companyLogoBytes: branding.logoBytes,
        companyName: branding.companyName,
        reportHeaderText: branding.reportHeaderText,
        reportFooterText: branding.reportFooterText,
        settings: settings,
      );
      final zipName = _zipExportFileName(survey, settings);

      if (action == _ExportAction.download) {
        if (kIsWeb) {
          downloadBytesWeb(bytes: zipBytes, fileName: zipName, mimeType: 'application/zip');
        } else {
          await Printing.sharePdf(bytes: zipBytes, filename: zipName);
        }
        return;
      }

      await Printing.sharePdf(bytes: zipBytes, filename: zipName);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ZIP export failed: $e')),
      );
    }
  }

  Future<void> _showApproveDialog({
    required BuildContext context,
    required Door door,
  }) async {
    final isFireStopping = widget.workspaceKey == 'fire-stopping';
    final workspace = parseInspectionWorkspaceKey(widget.workspaceKey) ?? InspectionWorkspace.fireDoor;
    final controller = ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final nameCtrl = TextEditingController(text: door.approvedMaintainerName);
    final numberCtrl = TextEditingController(text: door.approvedMaintainerNumber);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFireStopping ? 'Approve Item' : 'Approve Door'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (door.approvedAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Currently approved by ${door.approvedMaintainerName} on '
                  '${door.approvedAt!.day.toString().padLeft(2, "0")}/${door.approvedAt!.month.toString().padLeft(2, "0")}/${door.approvedAt!.year}.',
                  style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                ),
              ),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Approved Maintainer Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: numberCtrl,
              decoration: const InputDecoration(
                labelText: 'Approved Maintainer Number',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final number = numberCtrl.text.trim();
              if (name.isEmpty || number.isEmpty) return;
              controller.approveDoor(
                surveyId: widget.surveyId,
                doorId: door.id,
                approvedMaintainerName: name,
                approvedMaintainerNumber: number,
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(isFireStopping ? 'Item approved.' : 'Door approved.')),
              );
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Approve'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    numberCtrl.dispose();
  }

  String _fireStoppingStatusLabel(Door door) {
    if (door.approvedAt != null) return 'Completed';
    return 'Action Required';
  }

  ({Color bg, Color border, Color text}) _fireStoppingStatusColors(String label) {
    switch (label) {
      case 'Completed':
        return (
          bg: const Color(0xFFE8F5E9),
          border: const Color(0xFF2E7D32),
          text: const Color(0xFF2E7D32),
        );
      case 'Action Required':
        return (
          bg: const Color(0xFFFFEBEE),
          border: const Color(0xFFC62828),
          text: const Color(0xFFC62828),
        );
      default:
        return (
          bg: const Color(0xFFF5F5F5),
          border: const Color(0xFF9E9E9E),
          text: const Color(0xFF616161),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = ref.read(settingsControllerProvider.notifier);
    if (ref.read(settingsControllerProvider).activeWorkspaceKey != widget.workspaceKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        settingsController.setActiveWorkspace(widget.workspaceKey);
      });
    }
    final workspace = parseInspectionWorkspaceKey(widget.workspaceKey) ?? InspectionWorkspace.fireDoor;
    final state = ref.watch(surveyControllerFamilyProvider(workspace));
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final survey = controller.getById(widget.surveyId);

    if (survey == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }

    final isFireStopping = survey.type == SurveyType.fireStopping;

    final reportDetailsCompleted =
      survey.addressLine1.trim().isNotEmpty || survey.siteAddress.trim().isNotEmpty;
    final needsDisclaimer = reportDetailsCompleted && survey.disclaimerAcceptedAt == null;

    if (needsDisclaimer && !_shownDisclaimer) {
      _shownDisclaimer = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final accepted = await showModalBottomSheet<_DisclaimerResult>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          useSafeArea: true,
          builder: (ctx) => _DisclaimerSheet(isFireStopping: isFireStopping),
        );

        if (!context.mounted) return;

        if (accepted == null || !accepted.accepted) {
          context.go(widget.routePrefix);
          return;
        }

        controller.acceptSurveyDisclaimer(
          surveyId: widget.surveyId,
          inspectorName: accepted.inspectorName,
        );
      });
    }

    final doors = state.surveys.firstWhere((s) => s.id == widget.surveyId).doors;

    Future<void> openActionsSheet({required String doorId}) async {
      final isFireStopping = survey.type == SurveyType.fireStopping;
      final action = await showModalBottomSheet<_DoorAction>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => _DoorActionsSheet(isFireStopping: isFireStopping),
      );

      if (!context.mounted) return;
      if (action == null) return;

      switch (action) {
        case _DoorAction.edit:
          context.go('${widget.routePrefix}/${widget.surveyId}/doors/$doorId');
          return;

        case _DoorAction.duplicate:
          final original = controller.getDoorById(surveyId: widget.surveyId, doorId: doorId);
          if (original == null) return;

          controller.addDoor(widget.surveyId);

          final updatedSurvey = controller.getById(widget.surveyId);
          if (updatedSurvey == null || updatedSurvey.doors.isEmpty) return;
          final newDoorId = updatedSurvey.doors.last.id;

          controller.updateDoor(
            surveyId: widget.surveyId,
            doorId: newDoorId,
            update: (d) => d.copyWith(
              doorIdTag: '',
              floor: original.floor,
              area: original.area,
              doorType: original.doorType,
              doorFunction: original.doorFunction,
              material: original.material,
              classification: original.classification,
              fireRating: original.fireRating,
              gradingLevel: original.gradingLevel,
              configuration: original.configuration,
              isFireExit: original.isFireExit,
              result: original.result,
              doorPhotos: original.doorPhotos,
              issues: original.issues,
              inspectionResults: original.inspectionResults,
            ),
          );

          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DoorDetailScreen(
                surveyId: widget.surveyId,
                mode: DoorDetailMode.edit,
                existingDoorId: newDoorId,
                isTempDraft: true,
                moduleKey: widget.moduleKey,
                routePrefix: widget.routePrefix,
              ),
            ),
          );
          return;

        case _DoorAction.approve:
          final door = controller.getDoorById(surveyId: widget.surveyId, doorId: doorId);
          if (door == null) return;
          await _showApproveDialog(context: context, door: door);
          return;

        case _DoorAction.delete:
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(isFireStopping ? 'Delete item?' : 'Delete door?'),
              content: Text(
                isFireStopping
                    ? 'This will permanently delete the item and all its inspection data.'
                    : 'This will permanently delete the door and all its inspection data.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );

          if (!context.mounted) return;
          if (ok != true) return;

          controller.deleteDoor(surveyId: widget.surveyId, doorId: doorId);
          return;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          survey.reportName.trim().isEmpty
              ? (isFireStopping ? 'Reports' : 'Doors')
              : '${isFireStopping ? 'Reports' : 'Doors'} - ${survey.reportName}',
        ),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: widget.workspaceKey),
        actions: [
          IconButton(
            tooltip: 'View Drawing',
            onPressed: () => _openDrawingOrPrompt(
              survey: survey,
              controller: controller,
            ),
            icon: const Icon(Icons.map_outlined),
          ),
          IconButton(
            tooltip: 'Generate PDF Report',
            onPressed: () => _showProjectExportDialog(context: context, survey: survey, settings: settings),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      drawer: AppDrawer(currentRoute: widget.routePrefix),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
          if (!reportDetailsCompleted) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  isFireStopping
                      ? 'Complete Report Header before starting Item Inspection.'
                      : 'Complete Report Details before starting Doors / Inspection.',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openDrawingOrPrompt(
                    survey: survey,
                    controller: controller,
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('View Drawing'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _uploadDrawings(
                    survey: survey,
                    controller: controller,
                  ),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Upload Drawing'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _showProjectExportDialog(context: context, survey: survey, settings: settings),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Generate PDF Report'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _creatingNewReport
                      ? null
                      : () async {
                          setState(() => _creatingNewReport = true);
                          try {
                            final project = controller.getById(widget.surveyId);
                            if (project == null) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Project not found. Please refresh project list.')),
                              );
                              return;
                            }

                            controller.addDoor(project.id);
                            final updatedSurvey = controller.getById(project.id);
                            if (updatedSurvey == null || updatedSurvey.doors.isEmpty) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Could not create report item. Try again.')),
                              );
                              return;
                            }

                            final newDoorId = updatedSurvey.doors.last.id;

                            if (!mounted) return;
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DoorDetailScreen(
                                  surveyId: project.id,
                                  mode: DoorDetailMode.edit,
                                  existingDoorId: newDoorId,
                                  isTempDraft: true,
                                  moduleKey: widget.moduleKey,
                                  routePrefix: widget.routePrefix,
                                  workspaceKey: widget.workspaceKey,
                                ),
                              ),
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _creatingNewReport = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: Text(isFireStopping ? 'New Report' : 'Add Door'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final d in doors)
            Builder(builder: (context) {
              final fireStoppingStatus = isFireStopping ? _fireStoppingStatusLabel(d) : '';
              final fireStoppingStatusColors =
                  isFireStopping ? _fireStoppingStatusColors(fireStoppingStatus) : null;
              final fireStoppingDefectCount = d.fireStoppingDefects.isNotEmpty
                  ? d.fireStoppingDefects.length
                  : (d.fireStoppingDefectDescription.trim().isNotEmpty ||
                          d.fireStoppingRecommendedAction.trim().isNotEmpty
                      ? 1
                      : 0);

              return
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: ListTile(
                title: Text(
                  d.doorIdTag.trim().isEmpty
                      ? (isFireStopping ? 'Report No: ${d.number}' : 'Door No: ${d.number}')
                      : '${isFireStopping ? 'Report' : 'Door'}: ${d.doorIdTag.trim()}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text([
                  if (d.floor.trim().isNotEmpty) '${isFireStopping ? 'Room / Area' : 'Level'}: ${d.floor}',
                  if (d.area.trim().isNotEmpty) '${isFireStopping ? 'Exact Location' : 'Location'}: ${d.area}',
                  if (isFireStopping) 'Defects: $fireStoppingDefectCount',
                  'Status: ${isFireStopping ? fireStoppingStatus : (d.issues.any((i) => i.severity == IssueSeverity.criticalFail) ? 'CRITICAL' : (d.issues.isNotEmpty ? 'FAIL' : (d.result == DoorResult.pass ? 'PASS' : 'NOT STARTED')))}',
                  'Photos: ${d.doorPhotos.length}',
                  '${isFireStopping ? 'Issues' : 'ART issues'}: ${d.issues.length}',
                  '${isFireStopping ? 'Inspection' : 'Inspection'}: ${d.inspectionDate.day.toString().padLeft(2, '0')}/${d.inspectionDate.month.toString().padLeft(2, '0')}/${d.inspectionDate.year}',
                ].join(' • ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      constraints: const BoxConstraints(minWidth: 86),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isFireStopping
                            ? fireStoppingStatusColors!.bg
                            : d.issues.any((i) => i.severity == IssueSeverity.criticalFail)
                                ? const Color(0xFFFFEBEE)
                                : (d.issues.isNotEmpty
                                    ? const Color(0xFFFFEBEE)
                                    : (d.result == DoorResult.pass ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1))),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isFireStopping
                              ? fireStoppingStatusColors!.border
                              : d.issues.any((i) => i.severity == IssueSeverity.criticalFail)
                                  ? const Color(0xFFB71C1C)
                                  : (d.issues.isNotEmpty
                                      ? const Color(0xFFC62828)
                                      : (d.result == DoorResult.pass ? const Color(0xFF2E7D32) : const Color(0xFFF9A825))),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        isFireStopping
                            ? fireStoppingStatus
                            : d.issues.any((i) => i.severity == IssueSeverity.criticalFail)
                                ? 'CRITICAL'
                                : (d.issues.isNotEmpty ? 'FAIL' : (d.result == DoorResult.pass ? 'PASS' : 'DRAFT')),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: isFireStopping
                              ? fireStoppingStatusColors!.text
                              : d.issues.any((i) => i.severity == IssueSeverity.criticalFail)
                                  ? const Color(0xFFB71C1C)
                                  : (d.issues.isNotEmpty
                                      ? const Color(0xFFC62828)
                                      : (d.result == DoorResult.pass ? const Color(0xFF2E7D32) : const Color(0xFFF9A825))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => context.go('${widget.routePrefix}/${widget.surveyId}/doors/${d.id}'),
                onLongPress: () => openActionsSheet(doorId: d.id),
              ),
            );
            }),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DoorAction { edit, duplicate, approve, delete }

class _DoorActionsSheet extends StatelessWidget {
  final bool isFireStopping;

  const _DoorActionsSheet({this.isFireStopping = false});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit / Inspect'),
            onTap: () => Navigator.pop(context, _DoorAction.edit),
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Duplicate'),
            onTap: () => Navigator.pop(context, _DoorAction.duplicate),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32)),
            title: Text(
              isFireStopping ? 'Approve Item' : 'Approve Door',
              style: const TextStyle(color: Color(0xFF2E7D32)),
            ),
            onTap: () => Navigator.pop(context, _DoorAction.approve),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pop(context, _DoorAction.delete),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DisclaimerResult {
  final bool accepted;
  final String inspectorName;
  const _DisclaimerResult({required this.accepted, required this.inspectorName});
}

class _DisclaimerSheet extends StatefulWidget {
  final bool isFireStopping;

  const _DisclaimerSheet({this.isFireStopping = false});

  @override
  State<_DisclaimerSheet> createState() => _DisclaimerSheetState();
}

// (Disclaimer body stays the same as you already have; keep it unchanged)
class _DisclaimerSheetState extends State<_DisclaimerSheet> {
  final _name = TextEditingController();
  bool _checked = false;
  bool _showValidation = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasName = _name.text.trim().isNotEmpty;
    final canAccept = _checked && hasName;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: isMobile ? 1 : 0.92,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.isFireStopping
                              ? 'Fire Stopping Inspection Disclaimer'
                              : 'Fire Door Inspection Disclaimer',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(
                          context,
                          const _DisclaimerResult(accepted: false, inspectorName: ''),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      children: [
                        _DisclaimerBody(isFireStopping: widget.isFireStopping),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _name,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Inspector name (required)',
                            border: const OutlineInputBorder(),
                            errorText: _showValidation && !hasName ? 'Inspector name is required.' : null,
                          ),
                        ),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _checked,
                          onChanged: (v) => setState(() => _checked = v ?? false),
                          title: const Text(
                            'I confirm that I have read and understood the disclaimer and agree to proceed.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: _showValidation && !_checked
                              ? const Text(
                                  'You must confirm the checkbox before continuing.',
                                  style: TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w700),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (!canAccept) {
                          setState(() => _showValidation = true);
                          return;
                        }
                        Navigator.pop(
                          context,
                          _DisclaimerResult(accepted: true, inspectorName: _name.text.trim()),
                        );
                      },
                      child: const Text('I Agree & Continue'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisclaimerBody extends StatelessWidget {
  final bool isFireStopping;

  const _DisclaimerBody({this.isFireStopping = false});

  @override
  Widget build(BuildContext context) {
    final text = isFireStopping
      ? '''
  1) Scope & limitations
  This fire stopping inspection is a visual, non-destructive survey of accessible areas only. No intrusive opening-up, laboratory testing, or certification validation is carried out unless explicitly stated. Concealed defects may exist and may not be identified.

  2) Basis of findings
  Findings are based on conditions observed at the time of inspection. Results may change due to building use, maintenance, alterations, or environmental conditions.

  3) Competence & responsibility
  This inspection does not replace a full fire risk assessment. The Responsible Person / Duty Holder remains responsible for ensuring compliance with applicable legislation and standards, and for acting on recommendations.

  4) Access & safety
  Where access is restricted, obstructed, unsafe, or refused, this will limit the inspection and may affect conclusions.

  5) Photos & data
  Photos may be taken as evidence and stored within the report for audit purposes. Personal data should not be intentionally captured; any incidental capture will be handled in accordance with the project data handling procedures.

  6) Urgent defects
  Where critical defects are identified, immediate mitigation and/or repair may be required. This report does not constitute permission to leave a non-compliant penetration untreated.
  '''
      : '''
1) Scope & limitations
This fire door inspection is a visual, non-destructive survey of accessible areas only. No intrusive opening-up, laboratory testing, or certification validation is carried out unless explicitly stated. Hidden defects may exist and may not be identified.

2) Basis of findings
Findings are based on conditions observed at the time of inspection. Results may change due to building use, maintenance, alterations, or environmental conditions.

3) Competence & responsibility
The inspection does not replace a competent person’s full fire risk assessment. The Responsible Person / Duty Holder remains responsible for ensuring compliance with applicable legislation and standards, and for acting on recommendations.

4) Access & safety
Where access is restricted, obstructed, unsafe, or refused, this will limit the inspection and may affect conclusions.

5) Photos & data
Photos may be taken as evidence and stored within the report for audit purposes. Personal data should not be intentionally captured; any incidental capture will be handled in accordance with the project’s data handling procedures.

6) Urgent defects
Where Critical Fail defects are identified, immediate mitigation and/or repair may be required. This report does not constitute permission to keep a non-compliant door in service.
''';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          text,
          style: TextStyle(height: 1.3),
        ),
      ),
    );
  }
}

