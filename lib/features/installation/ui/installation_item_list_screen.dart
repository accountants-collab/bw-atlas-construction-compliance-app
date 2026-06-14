import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/branding_resolver.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../app/ui/selection_controls.dart';
import '../../../auth/auth_state.dart';
import '../../../auth/current_user_role.dart';
import '../../../core/files/pdf_download_saver.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../reports/domain/report_file_naming.dart';
import '../../settings/state/settings_controller.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/pdf/web_download_stub.dart'
    if (dart.library.html) '../../surveys/pdf/web_download.dart';
import '../../surveys/state/survey_controller.dart';
import '../../surveys/ui/project_drawing_viewer.dart';
import '../pdf/installation_pdf.dart';

enum InstallationFlowModule { preInstall, installation }

enum _InstallationStatusFilter {
  all,
  pending,
  inProgress,
  forApproval,
  approved,
  rejected
}

enum _InstallationExportType { singleDoor, combinedAllDoors, separatePerDoor }

enum _ExportAction { download, email }

class InstallationItemListScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final InstallationFlowModule module;
  final String workspaceKey;

  const InstallationItemListScreen({
    super.key,
    required this.surveyId,
    required this.module,
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<InstallationItemListScreen> createState() =>
      _InstallationItemListScreenState();
}

class _InstallationItemListScreenState
    extends ConsumerState<InstallationItemListScreen> {
  _InstallationStatusFilter _filter = _InstallationStatusFilter.all;

  @override
  Widget build(BuildContext context) {
    final settingsController = ref.read(settingsControllerProvider.notifier);
    if (ref.read(settingsControllerProvider).activeWorkspaceKey !=
        widget.workspaceKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        settingsController.setActiveWorkspace(widget.workspaceKey);
      });
    }
    final workspace = parseInspectionWorkspaceKey(widget.workspaceKey) ??
        InspectionWorkspace.fireDoor;
    final workspaceSlug = inspectionWorkspaceSlug(workspace);
    ref.watch(surveyControllerFamilyProvider(workspace));
    final controller =
        ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final settings = ref.watch(settingsControllerProvider);
    final survey = controller.getById(widget.surveyId);
    final role = ref.watch(currentUserRoleProvider);
    final isManagerLike = role == UserRole.manager ||
        role == UserRole.owner ||
        role == UserRole.admin ||
        role == UserRole.superAdmin;
    final auth = ref.watch(authControllerProvider);
    final workerGroupId = role == UserRole.worker
        ? ref
            .read(settingsControllerProvider.notifier)
            .workerGroupIdForWorkspace(
                workspaceKey: workspaceSlug, userId: auth.uid)
        : null;

    if (survey == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }

    if (role == UserRole.worker) {
      final hasProjectGroups = survey.assignedGroupIds.isNotEmpty;
      final allowed = !hasProjectGroups ||
          ((workerGroupId ?? '').isNotEmpty &&
              survey.assignedGroupIds.contains(workerGroupId));
      if (!allowed) {
        return const Scaffold(
          body: Center(
              child: Text('Access restricted for your group assignment.')),
        );
      }
    }

    final isFireDoorReplacementProject =
        workspace == InspectionWorkspace.fireDoor &&
            survey.type == SurveyType.survey;
    final items = isFireDoorReplacementProject
        ? survey.preInstallItems
            .where((item) => item.fullReplacementTask)
            .toList()
        : survey.preInstallItems;
    final visibleItems = items.where((i) {
      if (widget.module == InstallationFlowModule.installation &&
          role == UserRole.worker) {
        return i.releasedToInstallation;
      }
      return true;
    }).toList();
    final filteredItems = visibleItems.where((i) {
      if (widget.module != InstallationFlowModule.installation ||
          !isManagerLike) {
        return true;
      }
      switch (_filter) {
        case _InstallationStatusFilter.all:
          return true;
        case _InstallationStatusFilter.pending:
          return i.status == InstallationStatus.pending;
        case _InstallationStatusFilter.inProgress:
          return i.status == InstallationStatus.inProgress ||
              i.status == InstallationStatus.completedByWorker;
        case _InstallationStatusFilter.forApproval:
          return i.status == InstallationStatus.forApproval;
        case _InstallationStatusFilter.approved:
          return i.status == InstallationStatus.approved;
        case _InstallationStatusFilter.rejected:
          return i.status == InstallationStatus.rejectedNeedsRework;
      }
    }).toList();
    final approvedItems =
        items.where((i) => i.status == InstallationStatus.approved).toList();

    Future<void> exportApprovedInstall() async {
      if (approvedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No approved installation items to export yet.')),
        );
        return;
      }

      final type = await showModalBottomSheet<_InstallationExportType>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Single Door PDF'),
                subtitle: const Text(
                    'Choose one approved opening - exports a direct PDF, no ZIP.'),
                onTap: () =>
                    Navigator.pop(ctx, _InstallationExportType.singleDoor),
              ),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Combined PDF for approved openings'),
                subtitle: const Text('One PDF with all approved openings.'),
                onTap: () => Navigator.pop(
                    ctx, _InstallationExportType.combinedAllDoors),
              ),
              ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: const Text('All Doors - ZIP (one PDF per door)'),
                subtitle: const Text(
                    'Individual PDF per approved opening, packaged as a ZIP file.'),
                onTap: () =>
                    Navigator.pop(ctx, _InstallationExportType.separatePerDoor),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

      if (!context.mounted || type == null) return;

      try {
        final branding = resolvePdfBranding(settings);

        Future<void> exportPdf(
            {required PreInstallItem? singleItem,
            required String reportType}) async {
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
                          title: const Text('Download PDF'),
                          onTap: () =>
                              Navigator.pop(ctx, _ExportAction.download),
                        ),
                        ListTile(
                          leading: const Icon(Icons.email_outlined),
                          title: const Text('Share by email'),
                          subtitle: const Text(
                              'Opens your share sheet (Mail / Gmail / Outlook etc).'),
                          onTap: () => Navigator.pop(ctx, _ExportAction.email),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );

          if (!context.mounted || action == null) return;

          final bytes = singleItem == null
              ? await InstallationPdfBuilder.buildCombinedApprovedProjectPdf(
                  survey,
                  companyName: branding.companyName,
                  companyLogoBytes: branding.logoBytes,
                  reportHeaderText: branding.reportHeaderText,
                  reportFooterText: branding.reportFooterText,
                )
              : await InstallationPdfBuilder.buildSingleApprovedItemPdf(
                  survey,
                  singleItem,
                  companyName: branding.companyName,
                  companyLogoBytes: branding.logoBytes,
                  reportHeaderText: branding.reportHeaderText,
                  reportFooterText: branding.reportFooterText,
                );

          final name = buildReportFileName(
            settings: settings,
            survey: survey,
            reportType: reportType,
            extension: 'pdf',
          );

          if (action == _ExportAction.download) {
            if (kIsWeb) {
              downloadBytesWeb(
                  bytes: bytes, fileName: name, mimeType: 'application/pdf');
            } else {
              try {
                final saved = await PdfDownloadSaver.savePdf(
                    bytes: bytes, fileName: name);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PDF saved: ${saved.fileName}')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Could not save PDF to device storage: $e')),
                );
              }
            }
            return;
          }

          await Printing.sharePdf(bytes: bytes, filename: name);
        }

        Future<void> exportZip() async {
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
                          onTap: () =>
                              Navigator.pop(ctx, _ExportAction.download),
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

          final bytes =
              await InstallationPdfBuilder.buildSeparateApprovedItemsZip(
            survey,
            companyName: branding.companyName,
            companyLogoBytes: branding.logoBytes,
            reportHeaderText: branding.reportHeaderText,
            reportFooterText: branding.reportFooterText,
          );
          final name = buildReportFileName(
            settings: settings,
            survey: survey,
            reportType: 'Installation',
            extension: 'zip',
          );

          if (action == _ExportAction.download) {
            if (kIsWeb) {
              downloadBytesWeb(
                  bytes: bytes, fileName: name, mimeType: 'application/zip');
            } else {
              await Printing.sharePdf(bytes: bytes, filename: name);
            }
            return;
          }

          await Printing.sharePdf(bytes: bytes, filename: name);
        }

        if (type == _InstallationExportType.singleDoor) {
          final chosenItem = await showModalBottomSheet<PreInstallItem>(
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
                    child: Text(
                      'Choose approved opening to export',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final i in approvedItems)
                          ListTile(
                            leading: const Icon(Icons.door_front_door_outlined),
                            title: Text(i.doorRef.trim().isEmpty
                                ? 'Opening'
                                : i.doorRef.trim()),
                            subtitle: Text([
                              if (i.level.trim().isNotEmpty)
                                'Level: ${i.level}',
                              if (i.location.trim().isNotEmpty) i.location,
                            ].join(' · ')),
                            onTap: () => Navigator.pop(ctx, i),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );

          if (!context.mounted || chosenItem == null) return;
          await exportPdf(singleItem: chosenItem, reportType: 'Installation');
          return;
        }

        if (type == _InstallationExportType.combinedAllDoors) {
          await exportPdf(singleItem: null, reportType: 'Installation');
          return;
        }

        await exportZip();
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Installation PDF is available only after manager approval.')),
        );
      }
    }

    void openItem(PreInstallItem item) {
      if (isManagerLike) {
        context.go(
            '/workspace/$workspaceSlug/installation/${widget.surveyId}/items/${item.id}/review');
      } else {
        context.go(
            '/workspace/$workspaceSlug/installation/${widget.surveyId}/items/${item.id}');
      }
    }

    final pageBody = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          children: [
            if (isManagerLike)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: exportApprovedInstall,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Generate Installation PDF'),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => ProjectDrawingAccess.showDrawingPicker(
                      context: context, survey: survey),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('View Drawing'),
                ),
              ),
            ),
            if (widget.module == InstallationFlowModule.installation &&
                isManagerLike)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(_InstallationStatusFilter.all, 'All'),
                      _filterChip(_InstallationStatusFilter.pending, 'Pending'),
                      _filterChip(
                          _InstallationStatusFilter.inProgress, 'In Progress'),
                      _filterChip(_InstallationStatusFilter.forApproval,
                          'For Approval'),
                      _filterChip(
                          _InstallationStatusFilter.approved, 'Approved'),
                      _filterChip(
                          _InstallationStatusFilter.rejected, 'Rejected'),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: filteredItems.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          isFireDoorReplacementProject
                              ? 'No active full replacement installation tasks are available yet.'
                              : 'No installation openings are available yet.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final done = item.installationTasks
                            .where(
                              (t) =>
                                  t.status ==
                                      InstallationTaskStatus.completed ||
                                  t.status ==
                                      InstallationTaskStatus.notApplicable,
                            )
                            .length;

                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(14),
                            title: Text(
                              item.doorRef.isEmpty
                                  ? 'Unnamed opening'
                                  : item.doorRef,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                Text(
                                    'Level: ${item.level.isEmpty ? '-' : item.level} • Location: ${item.location.isEmpty ? '-' : item.location}'),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _pill(
                                        'Tasks',
                                        '$done/${item.installationTasks.length}',
                                        const Color(0xFF1565C0)),
                                    _pill('Status', _statusLabel(item.status),
                                        _statusColor(item.status)),
                                    if (isManagerLike)
                                      _pill(
                                        'Workflow',
                                        _workflowStageLabel(item),
                                        _workflowStageColor(item),
                                      ),
                                    _pill(
                                        'Pre photos',
                                        '${item.preInstallPhotos.length}',
                                        Colors.blueGrey),
                                    _pill(
                                        'Install photos',
                                        '${item.installationPhotos.length}',
                                        Colors.orange),
                                  ],
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => openItem(item),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        title: 'Installation & Handover',
        workspaceKey: widget.workspaceKey,
        currentRoute: '/workspace/$workspaceSlug/modules/installation/projects',
        body: pageBody,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      drawer: AppDrawer(
          currentRoute:
              '/workspace/$workspaceSlug/modules/installation/projects'),
      appBar: AppBar(
        title: const Text('Installation & Handover'),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: workspaceSlug),
        actions: [
          IconButton(
            onPressed: () => ProjectDrawingAccess.showDrawingPicker(
                context: context, survey: survey),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'View Drawing',
          ),
        ],
      ),
      body: pageBody,
    );
  }

  Widget _filterChip(_InstallationStatusFilter value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AppChoicePill(
        label: label,
        selected: selected,
        selectedColor: AppSelectionColors.selectedGreen,
        onPressed: () => setState(() => _filter = value),
      ),
    );
  }

  static String _statusLabel(InstallationStatus status) {
    switch (status) {
      case InstallationStatus.pending:
        return 'Pending';
      case InstallationStatus.inProgress:
        return 'In Progress';
      case InstallationStatus.completedByWorker:
        return 'In Progress';
      case InstallationStatus.forApproval:
        return 'For Approval';
      case InstallationStatus.approved:
        return 'Approved';
      case InstallationStatus.rejectedNeedsRework:
        return 'Rejected / Needs Rework';
    }
  }

  static Color _statusColor(InstallationStatus status) {
    switch (status) {
      case InstallationStatus.pending:
        return Colors.blueGrey;
      case InstallationStatus.inProgress:
        return Colors.orange;
      case InstallationStatus.completedByWorker:
        return const Color(0xFF1565C0);
      case InstallationStatus.forApproval:
        return const Color(0xFF1565C0);
      case InstallationStatus.approved:
        return Colors.green;
      case InstallationStatus.rejectedNeedsRework:
        return Colors.red;
    }
  }

  static Widget _pill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style:
            TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  static String _workflowStageLabel(PreInstallItem item) {
    if (item.releasedToInstallation) {
      switch (item.status) {
        case InstallationStatus.pending:
          return 'Released to Installation';
        case InstallationStatus.inProgress:
        case InstallationStatus.completedByWorker:
          return 'Installation In Progress';
        case InstallationStatus.forApproval:
          return 'For Approval';
        case InstallationStatus.approved:
          return 'Approved';
        case InstallationStatus.rejectedNeedsRework:
          return 'Rejected - Rework Required';
      }
    }

    switch (item.preInstallationStatus) {
      case PreInstallationWorkflowStatus.draft:
        return 'Draft';
      case PreInstallationWorkflowStatus.survey_completed:
        return 'Survey Complete';
      case PreInstallationWorkflowStatus.approved_for_order:
      case PreInstallationWorkflowStatus.ready_for_factory_order:
      case PreInstallationWorkflowStatus.ordered:
      case PreInstallationWorkflowStatus.delivered_ready:
        return 'Ready for Factory Order';
      case PreInstallationWorkflowStatus.available_on_site:
        return 'Available on Site';
      case PreInstallationWorkflowStatus.released_to_installation:
        return 'Released to Installation';
    }
  }

  static Color _workflowStageColor(PreInstallItem item) {
    final label = _workflowStageLabel(item);
    switch (label) {
      case 'Draft':
        return Colors.blueGrey;
      case 'Survey Complete':
        return const Color(0xFF1565C0);
      case 'Ready for Factory Order':
        return const Color(0xFF6A1B9A);
      case 'Released to Installation':
        return const Color(0xFF2E7D32);
      case 'Installation In Progress':
        return Colors.orange;
      case 'For Approval':
        return const Color(0xFF1565C0);
      case 'Approved':
        return Colors.green;
      case 'Rejected - Rework Required':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }
}
