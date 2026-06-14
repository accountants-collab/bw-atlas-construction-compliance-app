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
import '../pdf/remedial_pdf.dart';

enum _DoorStatusFilter { all, pending, inProgress, forApproval, approved, rejected }
enum _RemedialExportType { singleDoor, combinedAllDoors, separatePerDoor }
enum _ExportAction { download, email }

class RemedialDoorListScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final String workspaceKey;

  const RemedialDoorListScreen({
    super.key,
    required this.surveyId,
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<RemedialDoorListScreen> createState() => _RemedialDoorListScreenState();
}

class _RemedialDoorListScreenState extends ConsumerState<RemedialDoorListScreen> {
  _DoorStatusFilter _filter = _DoorStatusFilter.all;

  bool _hasRemedialDoor(Door d) {
    if (d.replacementRequired) return false;
    if (d.remedialItems.any((i) => i.severity.toLowerCase() != 'advisory')) return true;
    if (d.issues.any((i) => i.severity == IssueSeverity.fail || i.severity == IssueSeverity.criticalFail)) {
      return true;
    }
    return d.result == DoorResult.fail;
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
    final workspaceSlug = inspectionWorkspaceSlug(workspace);
    ref.watch(surveyControllerFamilyProvider(workspace));
    final controller = ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final settings = ref.watch(settingsControllerProvider);
    final survey = controller.getById(widget.surveyId);
    final role = ref.watch(currentUserRoleProvider);
    final auth = ref.watch(authControllerProvider);
    final isManagerLike = role == UserRole.manager ||
      role == UserRole.owner ||
      role == UserRole.admin ||
      role == UserRole.superAdmin;
    final workerGroupId = role == UserRole.worker
        ? ref
            .read(settingsControllerProvider.notifier)
            .workerGroupIdForWorkspace(workspaceKey: workspaceSlug, userId: auth.uid)
        : null;

    if (survey == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }

    if (role == UserRole.worker) {
      final allowed = (workerGroupId == null || workerGroupId.isEmpty)
          ? true
          : (survey.assignedGroupIds.isEmpty || survey.assignedGroupIds.contains(workerGroupId));
      if (kDebugMode) {
        debugPrint(
          'remedial_doors_access role=${role.name} workspace=$workspaceSlug survey=${survey.id} group=${workerGroupId ?? ''} assigned=${survey.assignedGroupIds.join(',')} allowed=$allowed',
        );
      }
      if (!allowed) {
        return const Scaffold(
          body: Center(child: Text('Access restricted for your group assignment.')),
        );
      }
    }

    final defectiveDoors = survey.doors.where(_hasRemedialDoor).toList();
    final approvedDoors = defectiveDoors.where((d) => d.remedialStatus == RemedialStatus.approved).toList();

    final filteredDoors = defectiveDoors.where((d) {
      switch (_filter) {
        case _DoorStatusFilter.all:
          return true;
        case _DoorStatusFilter.pending:
          return d.remedialStatus == RemedialStatus.pending;
        case _DoorStatusFilter.inProgress:
          return d.remedialStatus == RemedialStatus.inProgress || d.remedialStatus == RemedialStatus.completedByWorker;
        case _DoorStatusFilter.forApproval:
          return d.remedialStatus == RemedialStatus.forApproval;
        case _DoorStatusFilter.approved:
          return d.remedialStatus == RemedialStatus.approved;
        case _DoorStatusFilter.rejected:
          return d.remedialStatus == RemedialStatus.rejectedNeedsRework;
      }
    }).toList();

    if (kDebugMode) {
      debugPrint(
        'remedial_doors_query role=${role.name} workspace=$workspaceSlug survey=${survey.id} group=${workerGroupId ?? ''} doors=${defectiveDoors.length} filtered=${filteredDoors.length} filter=${_filter.name}',
      );
    }

    Future<void> exportApprovedRemedial() async {
      if (approvedDoors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No approved remedial doors to export yet.')),
        );
        return;
      }

      final type = await showModalBottomSheet<_RemedialExportType>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Single Door PDF'),
                subtitle: const Text('Choose one approved door - exports a direct PDF, no ZIP.'),
                onTap: () => Navigator.pop(ctx, _RemedialExportType.singleDoor),
              ),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Combined PDF for approved doors'),
                subtitle: const Text('One PDF with all approved doors.'),
                onTap: () => Navigator.pop(ctx, _RemedialExportType.combinedAllDoors),
              ),
              ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: const Text('All Doors - ZIP (one PDF per door)'),
                subtitle: const Text('Individual PDF per approved door, packaged as a ZIP file.'),
                onTap: () => Navigator.pop(ctx, _RemedialExportType.separatePerDoor),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

      if (!context.mounted || type == null) return;

      try {
        final branding = resolvePdfBranding(settings);

        Future<void> exportPdf({required Door? singleDoor, required String reportType}) async {
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

          if (!context.mounted || action == null) return;

          final bytes = singleDoor == null
              ? await RemedialPdfBuilder.buildCombinedApprovedProjectPdf(
                  survey,
                  companyName: branding.companyName,
                  companyLogoBytes: branding.logoBytes,
                  reportHeaderText: branding.reportHeaderText,
                  reportFooterText: branding.reportFooterText,
                )
              : await RemedialPdfBuilder.buildSingleApprovedDoorPdf(
                  survey,
                  singleDoor,
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
              downloadBytesWeb(bytes: bytes, fileName: name, mimeType: 'application/pdf');
            } else {
              try {
                final saved = await PdfDownloadSaver.savePdf(bytes: bytes, fileName: name);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PDF saved: ${saved.fileName}')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not save PDF to device storage: $e')),
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

          final bytes = await RemedialPdfBuilder.buildSeparateApprovedDoorsZip(
            survey,
            companyName: branding.companyName,
            companyLogoBytes: branding.logoBytes,
            reportHeaderText: branding.reportHeaderText,
            reportFooterText: branding.reportFooterText,
          );
          final name = buildReportFileName(
            settings: settings,
            survey: survey,
            reportType: 'Remedial',
            extension: 'zip',
          );

          if (action == _ExportAction.download) {
            if (kIsWeb) {
              downloadBytesWeb(bytes: bytes, fileName: name, mimeType: 'application/zip');
            } else {
              await Printing.sharePdf(bytes: bytes, filename: name);
            }
            return;
          }

          await Printing.sharePdf(bytes: bytes, filename: name);
        }

        if (type == _RemedialExportType.singleDoor) {
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
                    child: Text(
                      'Choose approved door to export',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final d in approvedDoors)
                          ListTile(
                            leading: const Icon(Icons.door_front_door_outlined),
                            title: Text(d.doorIdTag.trim().isEmpty ? 'Door No: ${d.number}' : 'Door No: ${d.doorIdTag.trim()}'),
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
          await exportPdf(singleDoor: chosenDoor, reportType: 'Remedial');
          return;
        }

        if (type == _RemedialExportType.combinedAllDoors) {
          await exportPdf(singleDoor: null, reportType: 'Remedial');
          return;
        }

        await exportZip();
      } catch (e) {
        if (!context.mounted) return;
        final message = e is StateError ? e.message : 'Failed to generate remedial PDF.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }

    Future<void> exportApprovedDoorPdf(Door door) async {
      if (door.remedialStatus != RemedialStatus.approved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only approved remedial doors can be exported.')),
        );
        return;
      }

      try {
        final branding = resolvePdfBranding(settings);
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

        if (!context.mounted || action == null) return;

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
          reportType: 'Remedial',
          extension: 'pdf',
        );

        if (action == _ExportAction.download) {
          if (kIsWeb) {
            downloadBytesWeb(bytes: bytes, fileName: name, mimeType: 'application/pdf');
          } else {
            await Printing.layoutPdf(onLayout: (_) async => bytes);
          }
          return;
        }

        await Printing.sharePdf(bytes: bytes, filename: name);
      } catch (e) {
        if (!context.mounted) return;
        final message = e is StateError ? e.message : 'Failed to generate remedial PDF.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }

    final pageBody = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ProjectDrawingAccess.showDrawingPicker(context: context, survey: survey),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('View Drawing'),
                  ),
                ),
              ],
            ),
          ),
          if (isManagerLike)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: exportApprovedRemedial,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Generate Approved Remedial Report'),
                      ),
                    ),
                  ],
                ),
              ),
            if (isManagerLike)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(_DoorStatusFilter.all, 'All'),
                    _filterChip(_DoorStatusFilter.pending, 'Pending'),
                    _filterChip(_DoorStatusFilter.inProgress, 'In Progress'),
                    _filterChip(_DoorStatusFilter.forApproval, 'For Approval'),
                    _filterChip(_DoorStatusFilter.approved, 'Approved'),
                    _filterChip(_DoorStatusFilter.rejected, 'Returned for Rework'),
                  ],
                ),
              ),
            ),
          Expanded(
            child: filteredDoors.isEmpty
                ? const Center(child: Text('No remedial doors in this project.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredDoors.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final door = filteredDoors[index];
                      final totalIssues = door.remedialItems.length;
                      final doneIssues = door.remedialItems
                          .where((i) => i.status == RemedialStatus.completedByWorker || i.status == RemedialStatus.forApproval || i.status == RemedialStatus.approved)
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
                            door.doorIdTag.trim().isEmpty ? 'Door No: ${door.number}' : 'Door No: ${door.doorIdTag.trim()}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Text('Level: ${door.floor.isEmpty ? '-' : door.floor} • Location: ${door.area.isEmpty ? '-' : door.area}'),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _pill('Issues', '$doneIssues/$totalIssues', const Color(0xFF1565C0)),
                                  _pill('Status', _statusLabel(door.remedialStatus), _statusColor(door.remedialStatus)),
                                ],
                              ),
                              if (isManagerLike && door.remedialStatus == RemedialStatus.approved) ...[
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton.tonalIcon(
                                    onPressed: () => exportApprovedDoorPdf(door),
                                    icon: const Icon(Icons.picture_as_pdf_outlined),
                                    label: const Text('Generate PDF Report'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            if (isManagerLike) {
                              context.go('/workspace/$workspaceSlug/remedials/${widget.surveyId}/doors/${door.id}/review');
                            } else {
                              context.go('/workspace/$workspaceSlug/remedials/${widget.surveyId}/doors/${door.id}');
                            }
                          },
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
        currentRoute: '/workspace/$workspaceSlug/remedials/${widget.surveyId}/doors',
        title: 'Remedial Works',
        workflowLabel: 'Remedial Works',
        drawerRoute: '/workspace/$workspaceSlug/modules/remedials/projects',
        workspaceKey: workspaceSlug,
        surveyId: widget.surveyId,
        body: pageBody,
        backgroundColor: const Color(0xFFF6F7F9),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      drawer: const AppDrawer(currentRoute: '/modules/remedials/projects'),
      appBar: AppBar(
        title: Text('Remedial Doors - ${survey.reportName.isEmpty ? survey.id : survey.reportName}'),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: workspaceSlug),
      ),
      body: pageBody,
    );
  }

  Widget _filterChip(_DoorStatusFilter value, String label) {
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

  static String _statusLabel(RemedialStatus status) {
    switch (status) {
      case RemedialStatus.pending:
        return 'Pending';
      case RemedialStatus.inProgress:
        return 'In Progress';
      case RemedialStatus.completedByWorker:
        return 'In Progress';
      case RemedialStatus.forApproval:
        return 'For Approval';
      case RemedialStatus.approved:
        return 'Approved';
      case RemedialStatus.rejectedNeedsRework:
        return 'Returned for Rework';
    }
  }

  static Color _statusColor(RemedialStatus status) {
    switch (status) {
      case RemedialStatus.pending:
        return Colors.blueGrey;
      case RemedialStatus.inProgress:
        return Colors.orange;
      case RemedialStatus.completedByWorker:
        return const Color(0xFF1565C0);
      case RemedialStatus.forApproval:
        return const Color(0xFF1565C0);
      case RemedialStatus.approved:
        return Colors.green;
      case RemedialStatus.rejectedNeedsRework:
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
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
