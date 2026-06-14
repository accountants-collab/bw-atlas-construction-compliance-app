import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../app/ui/app_visual_system.dart';
import '../../../app/ui/branding_resolver.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../../core/files/pdf_download_saver.dart';
import '../../../core/media/camera_capture_helper.dart';
import '../../disclaimer/data/disclaimer_providers.dart';
import '../../disclaimer/domain/disclaimer_models.dart';
import '../../disclaimer/ui/disclaimer_capture_sheet.dart';
import '../../fire_door/inspection/domain/models.dart';
import '../../fire_door/inspection/state/survey_controller.dart';
import '../../fire_door/inspection/ui/project_drawing_viewer.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../settings/state/settings_controller.dart';
import '../domain/snagging_models.dart';
import '../pdf/snagging_pdf_builder.dart';
import '../state/snagging_module_controller.dart';

class SnaggingIssuesScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String? issueId;
  const SnaggingIssuesScreen(
      {super.key, required this.projectId, this.issueId});

  @override
  ConsumerState<SnaggingIssuesScreen> createState() =>
      _SnaggingIssuesScreenState();
}

class _SnaggingIssuesScreenState extends ConsumerState<SnaggingIssuesScreen> {
  bool _isLinkingSurvey = false;
  final Set<String> _selectedIssueIds = <String>{};

  void _toggleIssueSelection(String issueId) {
    setState(() {
      if (_selectedIssueIds.contains(issueId)) {
        _selectedIssueIds.remove(issueId);
      } else {
        _selectedIssueIds.add(issueId);
      }
    });
  }

  void _setAllIssueSelections(List<SnaggingIssue> issues, bool selected) {
    setState(() {
      if (selected) {
        _selectedIssueIds
          ..clear()
          ..addAll(issues.map((issue) => issue.id));
      } else {
        _selectedIssueIds.clear();
      }
    });
  }

  Future<bool> _ensureSnaggingDisclaimer({
    required SnaggingProject project,
    required Survey linkedSurvey,
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

    const moduleType = 'snagging';

    final existingLocal = linkedSurvey.disclaimerAcceptance;
    if (isDisclaimerAcceptanceCurrent(
      record: existingLocal,
      moduleType: moduleType,
      userId: userId,
    )) {
      return true;
    }

    final surveyController = ref.read(
        surveyControllerFamilyProvider(InspectionWorkspace.snagging).notifier);
    final repo = ref.read(disclaimerRepositoryProvider);
    final existing = await repo.findUserModuleRecord(
      companyId: companyId,
      moduleType: moduleType,
      userId: userId,
    );

    if (existing != null) {
      surveyController.setSurveyDisclaimerRecord(
          surveyId: linkedSurvey.id, record: existing);
      return true;
    }

    if (!mounted) return false;
    final accepted = await showDisclaimerCaptureSheet(
      context: context,
      ref: ref,
      companyId: companyId,
      projectId: project.id,
      reportId: linkedSurvey.id,
      moduleType: moduleType,
      projectName: project.name,
      projectNumber: linkedSurvey.reference,
      reportReference: linkedSurvey.registerReference,
    );

    if (accepted == null) {
      return false;
    }

    surveyController.setSurveyDisclaimerRecord(
        surveyId: linkedSurvey.id, record: accepted);
    return true;
  }

  void _ensureLinkedSurvey(SnaggingProject project) {
    if (_isLinkingSurvey) return;
    _isLinkingSurvey = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final snaggingController =
          ref.read(snaggingModuleControllerProvider.notifier);
      final surveyController = ref.read(
          surveyControllerFamilyProvider(InspectionWorkspace.snagging)
              .notifier);

      var survey = project.surveyId.isEmpty
          ? null
          : surveyController.getById(project.surveyId);
      if (survey == null) {
        survey = surveyController.createSurvey(SurveyType.snagging);
        surveyController.updateSurveyMeta(
          surveyId: survey.id,
          reportName: project.name,
          clientName: project.client,
          addressLine1: project.addressLine1,
          addressLine2: project.addressLine2,
          cityTown: project.city,
          postCode: project.postcode,
          clientEmail: project.clientEmail,
          clientPhone: project.clientPhone,
          reportDate: project.date,
        );
        snaggingController.updateProject(
            project.id, (p) => p.copyWith(surveyId: survey!.id));
      }

      _isLinkingSurvey = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(snaggingModuleControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);
    final project = ref.watch(
      snaggingModuleControllerProvider.select((state) {
        for (final item in state.projects) {
          if (item.id == widget.projectId) {
            return item;
          }
        }
        return null;
      }),
    );
    if (project == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }

    final linkedSurvey = ref.watch(
      surveyControllerFamilyProvider(InspectionWorkspace.snagging)
          .select((state) {
        if (project.surveyId.isEmpty) return null;
        for (final item in state.surveys) {
          if (item.id == project.surveyId) {
            return item;
          }
        }
        return null;
      }),
    );

    if (linkedSurvey == null) {
      _ensureLinkedSurvey(project);
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedIssue = widget.issueId == null
        ? null
        : project.issues
            .where((e) => e.id == widget.issueId)
            .cast<SnaggingIssue?>()
            .firstWhere((e) => e != null, orElse: () => null);

    if (widget.issueId != null && selectedIssue == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Snag not found'),
          bottom:
              const WorkspaceSwitchCardsBar(currentWorkspaceKey: 'snagging'),
        ),
        body: Center(
          child: FilledButton.icon(
            onPressed: () => context.go(
                '/workspace/snagging/inspection/projects/${widget.projectId}/items'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to Snag List'),
          ),
        ),
      );
    }

    bool canDeleteIssue(SnaggingIssue issue) {
      final role = auth.role;
      if (role == UserRole.owner ||
          role == UserRole.admin ||
          role == UserRole.manager ||
          role == UserRole.superAdmin) {
        return true;
      }

      if (role == UserRole.worker) {
        return issue.status == SnaggingStatus.open &&
            issue.assignedToUserId.trim().isNotEmpty &&
            issue.assignedToUserId.trim() == auth.uid.trim();
      }

      return false;
    }

    Future<void> exportPdf() async {
      try {
        final settings = ref.read(settingsControllerProvider);
        final cp = settings.companyProfile;
        final branding = resolvePdfBranding(settings);
        Uint8List effectiveLogoBytes = Uint8List.fromList(branding.logoBytes);
        if (effectiveLogoBytes.isEmpty) {
          try {
            final fallback = await rootBundle.load(kDefaultSystemLogoAssetPath);
            effectiveLogoBytes = fallback.buffer.asUint8List();
          } catch (_) {
            // Keep empty if asset loading fails; PDF will still generate.
          }
        }
        final bytes = await SnaggingPdfBuilder.buildProjectReport(
          project,
          disclaimerRecord: linkedSurvey.disclaimerAcceptance,
          companyName: branding.companyName,
          companyAddress: cp.address,
          companyEmail: cp.email,
          companyPhone: cp.phone,
          logoBytes: effectiveLogoBytes,
          reportHeaderText: branding.reportHeaderText,
          reportFooterText: branding.reportFooterText,
        );
        final filename = SnaggingPdfBuilder.buildFilename(project);

        if (!context.mounted) return;

        if (!kIsWeb) {
          final action = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Download PDF'),
                    onTap: () => Navigator.pop(ctx, 'download'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Share by email'),
                    subtitle: const Text(
                        'Opens your share sheet (Mail / Gmail / Outlook etc).'),
                    onTap: () => Navigator.pop(ctx, 'share'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );

          if (!context.mounted || action == null) return;

          if (action == 'download') {
            try {
              final saved = await PdfDownloadSaver.savePdf(
                  bytes: bytes, fileName: filename);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('PDF saved: ${saved.fileName}')),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('Could not save PDF to device storage: $e')),
              );
            }
            return;
          }
        }

        try {
          await Printing.sharePdf(bytes: bytes, filename: filename);
        } catch (_) {
          await Printing.layoutPdf(
            name: filename,
            onLayout: (_) async => bytes,
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $e')),
        );
      }
    }

    Future<bool> confirmDeleteSnag(SnaggingIssue issue) async {
      if (!canDeleteIssue(issue)) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('You do not have permission to delete this snag item.'),
          ),
        );
        return false;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete snag?'),
          content:
              Text('Snag #${issue.snagNumber} will be permanently removed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        controller.removeIssue(projectId: widget.projectId, issueId: issue.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Snag #${issue.snagNumber} deleted.')),
          );
        }
        return true;
      }
      return false;
    }

    Future<void> bulkDeleteSelectedSnags() async {
      final selected = project.issues
          .where((e) => _selectedIssueIds.contains(e.id))
          .toList();
      if (selected.isEmpty) return;

      final undeletable =
          selected.where((issue) => !canDeleteIssue(issue)).toList();
      if (undeletable.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You do not have permission to delete ${undeletable.length} selected snag(s).',
            ),
          ),
        );
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete selected snags?'),
          content: Text(
            'You are about to permanently delete ${selected.length} selected snag(s). This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              child: const Text('Delete selected'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      for (final issue in selected) {
        controller.removeIssue(projectId: widget.projectId, issueId: issue.id);
      }

      if (!mounted) return;
      setState(() => _selectedIssueIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${selected.length} snag(s).')),
      );
    }

    final selectedCount =
        project.issues.where((e) => _selectedIssueIds.contains(e.id)).length;
    final allSelected =
        project.issues.isNotEmpty && selectedCount == project.issues.length;

    final content = widget.issueId == null
        ? ListView(
            padding: const EdgeInsets.all(AppSpace.m),
            children: [
              FilledButton.icon(
                onPressed: () async {
                  final allowed = await _ensureSnaggingDisclaimer(
                      project: project, linkedSurvey: linkedSurvey);
                  if (!allowed) return;
                  if (!context.mounted) return;
                  final issue = controller.addIssue(widget.projectId);
                  context.go(
                      '/workspace/snagging/inspection/projects/${widget.projectId}/items/${issue.id}');
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Snag'),
              ),
              const SizedBox(height: AppSpace.s),
              OutlinedButton.icon(
                onPressed: exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF'),
              ),
              const SizedBox(height: AppSpace.s),
              if (project.issues.isNotEmpty) ...[
                Row(
                  children: [
                    Checkbox(
                      value: allSelected,
                      onChanged: (value) => _setAllIssueSelections(
                          project.issues, value ?? false),
                    ),
                    const Text('All'),
                    const Spacer(),
                    if (selectedCount > 0)
                      TextButton.icon(
                        onPressed: bulkDeleteSelectedSnags,
                        icon: Icon(Icons.delete_outline,
                            color: Colors.red.shade700),
                        label: Text(
                          'Delete Selected ($selectedCount)',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.s),
              ],
              if (project.issues.isEmpty)
                AppEmptyState(
                  icon: Icons.assignment_late_outlined,
                  title: 'No snags yet',
                  message: 'Add your first snag to start the inspection.',
                  actionLabel: 'Add Snag',
                  onAction: () async {
                    final allowed = await _ensureSnaggingDisclaimer(
                        project: project, linkedSurvey: linkedSurvey);
                    if (!allowed) return;
                    if (!context.mounted) return;
                    final issue = controller.addIssue(widget.projectId);
                    context.go(
                        '/workspace/snagging/inspection/projects/${widget.projectId}/items/${issue.id}');
                  },
                )
              else
                ...project.issues.map(
                  (issue) => Card(
                    child: ListTile(
                      leading: Checkbox(
                        value: _selectedIssueIds.contains(issue.id),
                        onChanged: (_) => _toggleIssueSelection(issue.id),
                      ),
                      title: Row(
                        children: [
                          _PriorityDot(priority: issue.priority),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Snag #${issue.snagNumber} — ${issue.assignedToName.isEmpty ? 'Unassigned' : issue.assignedToName}',
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${issue.location.isEmpty ? 'No location' : issue.location}  ·  ${_statusLabel(issue.status)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canDeleteIssue(issue))
                            IconButton(
                              tooltip: 'Delete snag',
                              onPressed: () => confirmDeleteSnag(issue),
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red.shade700,
                            ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => context.go(
                          '/workspace/snagging/inspection/projects/${widget.projectId}/items/${issue.id}'),
                    ),
                  ),
                ),
            ],
          )
        : _SnaggingIssueEditor(
            key: ValueKey('snag-editor-${selectedIssue!.id}'),
            projectId: widget.projectId,
            surveyId: linkedSurvey.id,
            issue: selectedIssue,
            onDeleteIssue: (issueId, snagNumber) async {
              if (!canDeleteIssue(selectedIssue)) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'You do not have permission to delete this snag item.'),
                  ),
                );
                return;
              }

              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete snag?'),
                  content:
                      Text('Snag #$snagNumber will be permanently removed.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                controller.removeIssue(
                    projectId: widget.projectId, issueId: issueId);
                if (context.mounted) {
                  context.go(
                      '/workspace/snagging/inspection/projects/${widget.projectId}/items');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Snag #$snagNumber deleted.')),
                  );
                }
              }
            },
          );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: widget.issueId == null
            ? '/workspace/snagging/inspection/projects/${widget.projectId}/items'
            : '/workspace/snagging/inspection/projects/${widget.projectId}/items/${widget.issueId}',
        title: 'Snagging Inspection',
        workflowLabel: 'Snagging Inspection',
        drawerRoute: '/workspace/snagging/inspection/projects',
        workspaceKey: 'snagging',
        surveyId: linkedSurvey.id,
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.issueId == null ? 'Snagging Inspection' : 'Snag Details'),
        bottom: const WorkspaceSwitchCardsBar(currentWorkspaceKey: 'snagging'),
        actions: [
          IconButton(
              onPressed: exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined)),
        ],
      ),
      body: content,
    );
  }
}

class _SnaggingIssueEditor extends ConsumerStatefulWidget {
  final String projectId;
  final String surveyId;
  final SnaggingIssue issue;
  final Future<void> Function(String issueId, int snagNumber) onDeleteIssue;

  const _SnaggingIssueEditor({
    super.key,
    required this.projectId,
    required this.surveyId,
    required this.issue,
    required this.onDeleteIssue,
  });

  @override
  ConsumerState<_SnaggingIssueEditor> createState() =>
      _SnaggingIssueEditorState();
}

class _SnaggingIssueEditorState extends ConsumerState<_SnaggingIssueEditor> {
  static const _responsiblePartyOptions = <ResponsibleParty>[
    ResponsibleParty.mainContractor,
    ResponsibleParty.subcontractor,
    ResponsibleParty.other,
  ];

  static const _locationModes = <_SnaggingLocationMode>[
    _SnaggingLocationMode.manual,
    _SnaggingLocationMode.drawingPin,
  ];

  final _assignedTo = TextEditingController();
  final _location = TextEditingController();
  final _reference = TextEditingController();

  bool _loaded = false;
  DateTime _dateTime = DateTime.now();
  SnagPriority _priority = SnagPriority.medium;
  SnagProgrammeImpact _programmeImpact = SnagProgrammeImpact.na;
  SnaggingStatus _status = SnaggingStatus.open;
  // Responsibility and company assignment
  ResponsibleParty _responsibleParty = ResponsibleParty.unknown;
  final _customResponsibleParty = TextEditingController();

  _SnaggingLocationMode _locationMode = _SnaggingLocationMode.manual;
  String _drawingFileName = '';
  String _drawingMimeType = '';
  String _sharedDrawingId = '';
  String _sharedPinId = '';
  Uint8List? _drawingBytes;
  Uint8List? _drawingPreviewBytes;
  double? _previewImageNaturalWidth;
  double? _previewImageNaturalHeight;
  double? _pinX;
  double? _pinY;

  final List<Uint8List> _originalPhotos = <Uint8List>[];
  final List<String> _photoDescriptions = <String>[]; // Per-photo descriptions

  String _autoPinReference() {
    return 'PIN-${widget.issue.snagNumber.toString().padLeft(3, '0')}';
  }

  void _normalizePhotoDescriptions() {
    if (_photoDescriptions.length < _originalPhotos.length) {
      _photoDescriptions.addAll(
        List<String>.filled(
            _originalPhotos.length - _photoDescriptions.length, ''),
      );
    } else if (_photoDescriptions.length > _originalPhotos.length) {
      _photoDescriptions.removeRange(
          _originalPhotos.length, _photoDescriptions.length);
    }
  }

  @override
  void dispose() {
    _assignedTo.dispose();
    _location.dispose();
    _reference.dispose();
    _customResponsibleParty.dispose();
    super.dispose();
  }

  Future<Uint8List?> _buildDrawingPreviewBytes(
      Uint8List drawingBytes, String mimeType) async {
    if (mimeType == 'application/pdf') {
      try {
        await for (final raster
            in Printing.raster(drawingBytes, pages: const [0], dpi: 120)) {
          return await raster.toPng();
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    return drawingBytes;
  }

  Future<void> _refreshDrawingPreview() async {
    final source = _drawingBytes;
    if (source == null || source.isEmpty) {
      if (!mounted) return;
      setState(() {
        _drawingPreviewBytes = null;
        _previewImageNaturalWidth = null;
        _previewImageNaturalHeight = null;
      });
      return;
    }

    final preview = await _buildDrawingPreviewBytes(source, _drawingMimeType);
    if (!mounted) return;
    setState(() => _drawingPreviewBytes = preview);
    if (preview != null) {
      _loadPreviewNaturalSize(preview);
    }
  }

  Future<void> _loadPreviewNaturalSize(Uint8List bytes) async {
    try {
      final decoded = await decodeImageFromList(bytes);
      if (!mounted) return;
      setState(() {
        _previewImageNaturalWidth = decoded.width.toDouble();
        _previewImageNaturalHeight = decoded.height.toDouble();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      _loaded = true;
      _assignedTo.text = widget.issue.assignedToName;
      _location.text = widget.issue.location;
      _reference.text = widget.issue.reference;
      _dateTime = widget.issue.dateTime;
      _priority = widget.issue.priority;
      _programmeImpact = widget.issue.programmeImpact;
      _status = widget.issue.status;
      _locationMode = widget.issue.useDrawingPin
          ? _SnaggingLocationMode.drawingPin
          : _SnaggingLocationMode.manual;
      _drawingFileName = widget.issue.drawingFileName;
      _drawingMimeType = widget.issue.drawingMimeType;
      _sharedDrawingId = widget.issue.sharedDrawingId;
      _sharedPinId = widget.issue.sharedPinId;

      final surveyController = ref.read(
          surveyControllerFamilyProvider(InspectionWorkspace.snagging)
              .notifier);
      final survey = surveyController.getById(widget.surveyId);
      final sharedDrawingMatches =
          (_sharedDrawingId.isNotEmpty && survey != null)
              ? survey.projectDrawings
                  .where((d) => d.id == _sharedDrawingId)
                  .toList()
              : const <ProjectDrawing>[];
      final sharedDrawing =
          sharedDrawingMatches.isEmpty ? null : sharedDrawingMatches.first;

      if (sharedDrawing != null && sharedDrawing.bytes.isNotEmpty) {
        _drawingBytes = Uint8List.fromList(sharedDrawing.bytes);
        _drawingFileName = sharedDrawing.fileName;
        _drawingMimeType = sharedDrawing.mimeType;
      } else if (widget.issue.drawingBytesBase64.trim().isNotEmpty) {
        try {
          _drawingBytes = base64Decode(widget.issue.drawingBytesBase64.trim());
        } catch (_) {
          _drawingBytes = null;
        }
      }

      if (_drawingBytes != null && _drawingBytes!.isNotEmpty) {
        if (_drawingMimeType == 'application/pdf') {
          _drawingPreviewBytes = null;
          _refreshDrawingPreview();
        } else {
          _drawingPreviewBytes = _drawingBytes;
          _loadPreviewNaturalSize(_drawingBytes!);
        }
      } else {
        _drawingPreviewBytes = null;
      }
      _pinX = widget.issue.pinX >= 0 ? widget.issue.pinX : null;
      _pinY = widget.issue.pinY >= 0 ? widget.issue.pinY : null;
      if (_pinX != null && _pinY != null && _reference.text.trim().isEmpty) {
        _reference.text = _autoPinReference();
      }
      _originalPhotos
        ..clear()
        ..addAll(widget.issue.originalPhotoBase64
            .map((e) => _decodeImage(e))
            .whereType<Uint8List>());
      _photoDescriptions
        ..clear()
        ..addAll(widget.issue.photoDescriptions);
      _normalizePhotoDescriptions();
      _responsibleParty =
          _responsiblePartyOptions.contains(widget.issue.responsibleParty)
              ? widget.issue.responsibleParty
              : ResponsibleParty.other;
      _customResponsibleParty.text = widget.issue.responsiblePartyCustom;

      // Auto-fill assigned to from current user
      final auth = ref.read(authControllerProvider);
      if (_assignedTo.text.isEmpty && auth.currentUser != null) {
        _assignedTo.text = auth.currentUser!.name;
      }
    }

    final controller = ref.read(snaggingModuleControllerProvider.notifier);
    final surveyController = ref.read(
        surveyControllerFamilyProvider(InspectionWorkspace.snagging).notifier);
    final survey = ref.watch(
      surveyControllerFamilyProvider(InspectionWorkspace.snagging)
          .select((state) {
        for (final item in state.surveys) {
          if (item.id == widget.surveyId) {
            return item;
          }
        }
        return null;
      }),
    );
    if (survey == null) {
      return const Center(child: CircularProgressIndicator());
    }

    Future<void> uploadDrawingToProjectPool() async {
      final latestSurvey = surveyController.getById(widget.surveyId);
      if (latestSurvey == null) return;

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final ext = (file.extension ?? '').toLowerCase();
      final mime = ext == 'pdf' ? 'application/pdf' : 'image/*';

      surveyController.addProjectDrawings(
        surveyId: latestSurvey.id,
        drawings: [
          ProjectDrawing(
            fileName: file.name,
            mimeType: mime,
            bytes: bytes,
          ),
        ],
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Drawing ${file.name} added to project drawing pool.')),
      );
    }

    Future<void> uploadDrawing() async {
      await uploadDrawingToProjectPool();
    }

    Future<void> pickImages(
        {required bool completion, required bool fromCamera}) async {
      final bytes = <Uint8List>[];

      if (fromCamera) {
        final shot =
            await CameraCaptureHelper.pickImage(context, imageQuality: 85);
        if (shot == null) return;
        final data = await shot.readAsBytes();
        if (data.isEmpty) return;
        bytes.add(data);
      } else {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          withData: true,
          type: FileType.image,
        );
        if (result == null || result.files.isEmpty) return;
        bytes.addAll(
          result.files
              .map((f) => f.bytes)
              .whereType<Uint8List>()
              .where((b) => b.isNotEmpty),
        );
      }

      if (bytes.isEmpty) return;
      setState(() {
        _originalPhotos.addAll(bytes);
        // Add empty descriptions for new photos (keep lists in sync)
        _photoDescriptions.addAll(List<String>.filled(bytes.length, ''));
      });
    }

    Future<void> placePinOnDrawing() async {
      final latestSurvey = surveyController.getById(widget.surveyId);
      if (latestSurvey == null) return;

      final hasExistingPin = _sharedPinId.trim().isNotEmpty;
      final result = await ProjectDrawingAccess.showDrawingPicker(
        context: context,
        survey: latestSurvey,
        selectionConfig: DrawingViewerSelectionConfig(
          enablePinPlacement: true,
          allowExistingPinSelection: hasExistingPin,
          autoAssignPinNumbers: false,
          highlightedPinId: _sharedPinId,
          hideOtherPins: true,
        ),
      );
      if (!mounted || result == null) return;

      setState(() {
        _sharedDrawingId = result.drawing.id;
        _sharedPinId = result.pin.id;
        _drawingFileName = result.drawing.fileName;
        _drawingMimeType = result.drawing.mimeType;
        _drawingBytes = Uint8List.fromList(result.drawing.bytes);
        _pinX = result.pin.x;
        _pinY = result.pin.y;
        _drawingPreviewBytes = null;
        final label = result.pin.label.trim().isNotEmpty
            ? result.pin.label.trim()
            : result.pin.doorNumber.trim();
        if (label.isNotEmpty) {
          _reference.text = label;
        } else if (_reference.text.trim().isEmpty) {
          _reference.text = _autoPinReference();
        }
      });
      await _refreshDrawingPreview();

      if (!mounted) return;
      if (result.addDefect) {
        final projectId = widget.projectId;
        final newIssue = controller.addIssue(projectId);
        controller.updateIssue(
          projectId: projectId,
          issueId: newIssue.id,
          update: (item) => item.copyWith(useDrawingPin: true),
        );
        if (context.mounted) {
          context.go(
              '/workspace/snagging/inspection/projects/$projectId/items/${newIssue.id}');
        }
      }
    }

    Future<void> pickOrMovePin() async {
      await placePinOnDrawing();
    }

    Future<void> pickDateTime() async {
      final date = await showDatePicker(
        context: context,
        initialDate: _dateTime,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (date == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_dateTime),
      );
      if (time == null) return;
      setState(() {
        _dateTime =
            DateTime(date.year, date.month, date.day, time.hour, time.minute);
      });
    }

    Future<void> saveIssue() async {
      if (_assignedTo.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assigned To is required.')),
        );
        return;
      }

      _normalizePhotoDescriptions();
      if (_locationMode == _SnaggingLocationMode.drawingPin &&
          _pinX != null &&
          _pinY != null) {
        if (_reference.text.trim().isEmpty) {
          _reference.text = _autoPinReference();
        }
      }

      controller.updateIssue(
        projectId: widget.projectId,
        issueId: widget.issue.id,
        update: (current) => current.copyWith(
          reference: _reference.text.trim(),
          location: _location.text.trim(),
          useDrawingPin: _locationMode == _SnaggingLocationMode.drawingPin,
          drawingFileName: _drawingFileName,
          drawingMimeType: _drawingMimeType,
          drawingBytesBase64: (_drawingBytes == null || _drawingBytes!.isEmpty)
              ? ''
              : base64Encode(_drawingBytes!),
          sharedDrawingId: _sharedDrawingId,
          sharedPinId: _sharedPinId,
          pinX: _pinX ?? -1,
          pinY: _pinY ?? -1,
          assignedToName: _assignedTo.text.trim(),
          dateTime: _dateTime,
          priority: _priority,
          programmeImpact: _programmeImpact,
          originalPhotoBase64: _originalPhotos.map(base64Encode).toList(),
          photoDescriptions: _photoDescriptions,
          status: _status,
          responsibleParty: _responsibleParty,
          responsiblePartyCustom: _responsibleParty == ResponsibleParty.other
              ? _customResponsibleParty.text.trim()
              : '',
          assignedCompanyId: '',
          assignedCompanyName: '',
        ),
      );

      if (!mounted) return;
      final nextAction = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Snag saved'),
            content: const Text('Choose what you want to do next.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop('back_to_report');
                },
                child: const Text('Back to Report'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop('add_new_snag');
                },
                child: const Text('Add New Snag'),
              ),
            ],
          );
        },
      );

      if (!context.mounted) return;
      if (nextAction == 'add_new_snag') {
        final newIssue = controller.addIssue(widget.projectId);
        controller.updateIssue(
          projectId: widget.projectId,
          issueId: newIssue.id,
          update: (item) => item.copyWith(useDrawingPin: true),
        );
        if (!context.mounted) return;
        context.go(
            '/workspace/snagging/inspection/projects/${widget.projectId}/items/${newIssue.id}');
        return;
      }

      context.go(
          '/workspace/snagging/inspection/projects/${widget.projectId}/items');
    }

    Widget section(
        {required String title,
        required IconData icon,
        required List<Widget> children}) {
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
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpace.m),
      children: [
        section(
          title: 'Snag Details',
          icon: Icons.assignment_outlined,
          children: [
            Text('Snag #${widget.issue.snagNumber}',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            _AssignedToField(
              controller: _assignedTo,
              onUserSelected: (name) => setState(() => _assignedTo.text = name),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date & Time'),
              subtitle: Text(_formatDateTime(_dateTime)),
              trailing: TextButton(
                  onPressed: pickDateTime, child: const Text('Edit')),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s),
        section(
          title: 'Responsible Party',
          icon: Icons.business_outlined,
          children: [
            DropdownButtonFormField<ResponsibleParty>(
              initialValue: _responsibleParty,
              decoration: const InputDecoration(
                labelText: 'Who is responsible for resolving this snag?',
                border: OutlineInputBorder(),
              ),
              items: _responsiblePartyOptions.map((party) {
                return DropdownMenuItem(
                  value: party,
                  child: Text(responsiblePartyLabel(party)),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _responsibleParty = value;
                  if (value != ResponsibleParty.other) {
                    _customResponsibleParty.clear();
                  }
                });
              },
            ),
            if (_responsibleParty == ResponsibleParty.other) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _customResponsibleParty,
                decoration: const InputDecoration(
                  labelText: 'Custom responsible party',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.s),
        const SizedBox(height: AppSpace.s),
        section(
          title: 'Location',
          icon: Icons.place_outlined,
          children: [
            for (final mode in _locationModes)
              RadioListTile<_SnaggingLocationMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: mode,
                groupValue: _locationMode,
                title: Text(mode == _SnaggingLocationMode.manual
                    ? 'Enter manually'
                    : 'Use drawing pin'),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _locationMode = value);
                },
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Reference / PIN (manual fallback available)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            if (_locationMode == _SnaggingLocationMode.drawingPin) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: pickOrMovePin,
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(_pinX == null || _pinY == null
                        ? 'Select Drawing & Place Pin'
                        : 'Move Pin'),
                  ),
                  OutlinedButton.icon(
                    onPressed: uploadDrawing,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload to Project Drawings'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (survey.projectDrawings.isEmpty)
                const Text(
                    'No project drawings yet. Upload once and reuse across all snags in this job.'),
              if (_drawingPreviewBytes != null)
                RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 170,
                      width: double.infinity,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final maxW = constraints.maxWidth;
                          const maxH = 170.0;
                          double drawLeft = 0,
                              drawTop = 0,
                              drawW = maxW,
                              drawH = maxH;
                          if (_previewImageNaturalWidth != null &&
                              _previewImageNaturalHeight != null &&
                              _previewImageNaturalWidth! > 0 &&
                              _previewImageNaturalHeight! > 0) {
                            final imgRatio = _previewImageNaturalWidth! /
                                _previewImageNaturalHeight!;
                            final boxRatio = maxW / maxH;
                            if (imgRatio > boxRatio) {
                              drawW = maxW;
                              drawH = drawW / imgRatio;
                              drawLeft = 0;
                              drawTop = (maxH - drawH) / 2;
                            } else {
                              drawH = maxH;
                              drawW = drawH * imgRatio;
                              drawLeft = (maxW - drawW) / 2;
                              drawTop = 0;
                            }
                          }
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Image.memory(
                                _drawingPreviewBytes!,
                                height: maxH,
                                width: maxW,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                                cacheWidth: 1400,
                              ),
                              if (_pinX != null && _pinY != null)
                                Positioned(
                                  left: drawLeft +
                                      (_pinX!.clamp(0.0, 1.0) * drawW) -
                                      9,
                                  top: drawTop +
                                      (_pinY!.clamp(0.0, 1.0) * drawH) -
                                      18,
                                  child: const Icon(Icons.location_on,
                                      color: Color(0xFFD32F2F), size: 26),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                )
              else if (_drawingMimeType == 'application/pdf')
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Rendering PDF preview...'),
                ),
            ],
            const SizedBox(height: 10),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                  labelText: 'Location', border: OutlineInputBorder()),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s),
        section(
          title: 'Issue',
          icon: Icons.report_problem_outlined,
          children: [
            _PrioritySegment(
              value: _priority,
              onChanged: (v) => setState(() => _priority = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<SnagProgrammeImpact>(
              initialValue: _programmeImpact,
              decoration: const InputDecoration(
                  labelText: 'Programme Impact', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: SnagProgrammeImpact.yes, child: Text('Yes')),
                DropdownMenuItem(
                    value: SnagProgrammeImpact.no, child: Text('No')),
                DropdownMenuItem(
                    value: SnagProgrammeImpact.na, child: Text('N/A')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _programmeImpact = v);
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s),
        section(
          title: 'Inspector Photos',
          icon: Icons.photo_library_outlined,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        pickImages(completion: false, fromCamera: true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        pickImages(completion: false, fromCamera: false),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload Photo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_originalPhotos.isEmpty)
              const Text('No photos selected yet.')
            else
              RepaintBoundary(
                child: _PhotoStrip(
                  photos: _originalPhotos,
                  descriptions: _photoDescriptions,
                  onRemoveAt: (idx) => setState(() {
                    _originalPhotos.removeAt(idx);
                    if (idx < _photoDescriptions.length) {
                      _photoDescriptions.removeAt(idx);
                    }
                    _normalizePhotoDescriptions();
                  }),
                  onDescriptionChanged: (idx, desc) => setState(() {
                    if (idx >= _photoDescriptions.length) {
                      _normalizePhotoDescriptions();
                    }
                    if (idx < _photoDescriptions.length) {
                      _photoDescriptions[idx] = desc;
                    }
                  }),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.m),
        OutlinedButton.icon(
          onPressed: () =>
              widget.onDeleteIssue(widget.issue.id, widget.issue.snagNumber),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete Snag'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
        ),
        const SizedBox(height: AppSpace.s),
        FilledButton.icon(
          onPressed: saveIssue,
          icon: const Icon(Icons.save),
          label: const Text('Save Snag'),
        ),
      ],
    );
  }
}

enum _SnaggingLocationMode { manual, drawingPin }

class _PhotoStrip extends StatelessWidget {
  final List<Uint8List> photos;
  final List<String> descriptions;
  final void Function(int index) onRemoveAt;
  final void Function(int index, String description) onDescriptionChanged;

  const _PhotoStrip({
    required this.photos,
    required this.descriptions,
    required this.onRemoveAt,
    required this.onDescriptionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact photo preview strip
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      photos[index],
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      cacheWidth: 240,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () => onRemoveAt(index),
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black87,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Description fields for each photo
        ...List<Widget>.generate(
          photos.length,
          (index) {
            final currentDescription =
                index < descriptions.length ? descriptions[index] : '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextFormField(
                initialValue: currentDescription,
                onChanged: (value) => onDescriptionChanged(index, value),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Defect ${index + 1} Description',
                  border: const OutlineInputBorder(),
                  hintText: 'Describe what you see in this photo',
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PinPlacementDialogWithNumber extends StatefulWidget {
  final Uint8List imageBytes;

  const _PinPlacementDialogWithNumber({
    required this.imageBytes,
  });

  @override
  State<_PinPlacementDialogWithNumber> createState() =>
      _PinPlacementDialogWithNumberState();
}

class _PinPlacementDialogWithNumberState
    extends State<_PinPlacementDialogWithNumber> {
  double? _x;
  double? _y;
  double? _imageWidth;
  double? _imageHeight;
  late TextEditingController _pinNumberController;

  @override
  void initState() {
    super.initState();
    _x = null;
    _y = null;
    _pinNumberController = TextEditingController(text: '');
    _loadImageSize();
  }

  @override
  void dispose() {
    _pinNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadImageSize() async {
    try {
      final decoded = await decodeImageFromList(widget.imageBytes);
      if (!mounted) return;
      setState(() {
        _imageWidth = decoded.width.toDouble();
        _imageHeight = decoded.height.toDouble();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imageWidth = null;
        _imageHeight = null;
      });
    }
  }

  ({double left, double top, double width, double height}) _containRect(
    BoxConstraints constraints,
  ) {
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;
    if (_imageWidth == null ||
        _imageHeight == null ||
        _imageWidth == 0 ||
        _imageHeight == 0) {
      return (left: 0, top: 0, width: maxW, height: maxH);
    }

    final imageRatio = _imageWidth! / _imageHeight!;
    final boxRatio = maxW / maxH;

    if (imageRatio > boxRatio) {
      final drawW = maxW;
      final drawH = drawW / imageRatio;
      return (left: 0, top: (maxH - drawH) / 2, width: drawW, height: drawH);
    }

    final drawH = maxH;
    final drawW = drawH * imageRatio;
    return (left: (maxW - drawW) / 2, top: 0, width: drawW, height: drawH);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.location_on_outlined),
                SizedBox(width: 8),
                Text('Place Pin on Drawing',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 600,
              height: 360,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final rect = _containRect(constraints);

                  return GestureDetector(
                    onTapDown: (details) {
                      final local = details.localPosition;
                      final withinX = local.dx >= rect.left &&
                          local.dx <= rect.left + rect.width;
                      final withinY = local.dy >= rect.top &&
                          local.dy <= rect.top + rect.height;
                      if (!withinX || !withinY) return;

                      setState(() {
                        _x = ((local.dx - rect.left) / rect.width)
                            .clamp(0.0, 1.0);
                        _y = ((local.dy - rect.top) / rect.height)
                            .clamp(0.0, 1.0);
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          cacheWidth: 1600,
                        ),
                        if (_x != null && _y != null)
                          Positioned(
                            left:
                                rect.left + (_x!.clamp(0, 1) * rect.width) - 9,
                            top:
                                rect.top + (_y!.clamp(0, 1) * rect.height) - 18,
                            child: const Icon(Icons.location_on,
                                color: Color(0xFFD32F2F), size: 26),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pinNumberController,
              decoration: InputDecoration(
                labelText: 'Pin Reference (e.g., A1, PIN-001)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_x == null || _y == null)
                      ? null
                      : () => Navigator.pop(
                            context,
                            (
                              x: _x!,
                              y: _y!,
                              pinNumber:
                                  _pinNumberController.text.trim().isNotEmpty
                                      ? _pinNumberController.text.trim()
                                      : null,
                            ),
                          ),
                  child: const Text('Save Pin'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(SnaggingStatus status) {
  switch (status) {
    case SnaggingStatus.open:
      return 'Open';
    case SnaggingStatus.awaitingVerification:
      return 'For Approval';
    case SnaggingStatus.approved:
      return 'Approved';
    case SnaggingStatus.returned:
      return 'Rejected - Rework Required';
  }
}

String _formatDateTime(DateTime value) {
  final dd = value.day.toString().padLeft(2, '0');
  final mm = value.month.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final min = value.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${value.year} $hh:$min';
}

Uint8List? _decodeImage(String raw) {
  if (raw.trim().isEmpty) return null;
  try {
    return base64Decode(raw.trim());
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Priority colour helpers
// ---------------------------------------------------------------------------

Color _priorityColor(SnagPriority p) {
  switch (p) {
    case SnagPriority.low:
      return const Color(0xFFFBC02D); // yellow
    case SnagPriority.medium:
      return const Color(0xFFF57C00); // orange
    case SnagPriority.high:
      return const Color(0xFFD32F2F); // red
  }
}

String _priorityLabel(SnagPriority p) {
  switch (p) {
    case SnagPriority.low:
      return 'Low';
    case SnagPriority.medium:
      return 'Medium';
    case SnagPriority.high:
      return 'High';
  }
}

class _PriorityDot extends StatelessWidget {
  final SnagPriority priority;
  const _PriorityDot({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(priority);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _PrioritySegment extends StatelessWidget {
  final SnagPriority value;
  final ValueChanged<SnagPriority> onChanged;
  const _PrioritySegment({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Priority',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: SnagPriority.values.map((p) {
            final selected = p == value;
            final color = _priorityColor(p);
            return ChoiceChip(
              label: Text(_priorityLabel(p),
                  style: TextStyle(
                      color: selected ? Colors.white : color,
                      fontWeight: FontWeight.w700)),
              selected: selected,
              selectedColor: color,
              side: BorderSide(color: color),
              backgroundColor: color.withValues(alpha: 0.08),
              onSelected: (_) => onChanged(p),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Assigned To field with manager dropdown
// ---------------------------------------------------------------------------

class _AssignedToField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onUserSelected;

  const _AssignedToField({
    required this.controller,
    required this.onUserSelected,
  });

  @override
  ConsumerState<_AssignedToField> createState() => _AssignedToFieldState();
}

class _AssignedToFieldState extends ConsumerState<_AssignedToField> {
  @override
  Widget build(BuildContext context) {
    final role = ref
        .watch(authControllerProvider.select((auth) => auth.currentUser?.role));
    final teamUsers = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.teamUsers.where((u) => u.isActive).toList(),
      ),
    );

    // Only show dropdown if user is manager/admin
    final isManager = role == UserRole.manager ||
        role == UserRole.admin ||
        role == UserRole.owner;

    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: widget.controller,
            decoration: const InputDecoration(
              labelText: 'Assigned To *',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        if (isManager && teamUsers.isNotEmpty) ...[
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Select team member',
            itemBuilder: (context) => teamUsers
                .map((user) => PopupMenuItem<String>(
                      value: user.name,
                      child: Text(user.name),
                    ))
                .toList(),
            onSelected: widget.onUserSelected,
          ),
        ],
      ],
    );
  }
}
