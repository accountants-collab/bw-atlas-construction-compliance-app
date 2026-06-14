import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/branding_resolver.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../../auth/current_user_role.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../installation/pdf/preinstall_pdf.dart';
import '../../reports/domain/report_file_naming.dart';
import '../../settings/state/settings_controller.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/pdf/web_download_stub.dart'
    if (dart.library.html) '../../surveys/pdf/web_download.dart';
import '../../surveys/state/survey_controller.dart';
import '../../surveys/ui/project_drawing_viewer.dart';
import '../../disclaimer/data/disclaimer_providers.dart';
import '../../disclaimer/domain/disclaimer_models.dart';

enum _ExportType { singleDoor, combinedAllDoors, separatePerDoor }

enum _ExportAction { download, email }

enum _WorkflowChoice { specificationOrder, installationOnly }

String _installationSurveyTypeTitle(PreInstallSurveyType type) {
  if (isSpecificationOrderWorkflowType(type)) {
    return 'Specification / Order';
  }
  return 'Installation Only';
}

String _installationSurveyTypeDescription(PreInstallSurveyType type) {
  if (isSpecificationOrderWorkflowType(type)) {
    return 'Used when measuring/specifying a new doorset for manufacture, pricing, ordering and installation.';
  }
  return 'Used when the doorset is already supplied by the client/main contractor and only installation tracking/assignment is required.';
}

String _installationSurveyTypeWorkflow(PreInstallSurveyType type) {
  if (isSpecificationOrderWorkflowType(type)) {
    return 'Survey -> Factory PDF -> Await Delivery -> Release to Installation -> Worker Installation';
  }
  return 'Installation -> Approval -> Handover';
}

IconData _installationSurveyTypeIcon(PreInstallSurveyType type) {
  if (isSpecificationOrderWorkflowType(type)) {
    return Icons.assignment_outlined;
  }
  return Icons.handyman_outlined;
}

Color _installationSurveyTypeColor(PreInstallSurveyType type) {
  if (isSpecificationOrderWorkflowType(type)) {
    return Colors.blue.shade700;
  }
  return Colors.green.shade700;
}

String _preInstallStatusLabel(PreInstallationWorkflowStatus status) {
  switch (status) {
    case PreInstallationWorkflowStatus.draft:
      return 'Draft';
    case PreInstallationWorkflowStatus.survey_completed:
      return 'Specification Complete';
    case PreInstallationWorkflowStatus.approved_for_order:
      return 'Approved for Order';
    case PreInstallationWorkflowStatus.ready_for_factory_order:
      return 'Factory PDF Generated';
    case PreInstallationWorkflowStatus.ordered:
      return 'Awaiting Delivery';
    case PreInstallationWorkflowStatus.delivered_ready:
      return 'Delivery Confirmed';
    case PreInstallationWorkflowStatus.available_on_site:
      return 'Available on Site';
    case PreInstallationWorkflowStatus.released_to_installation:
      return 'Approved'; // Never shown in UI anymore
  }
}

Color _preInstallStatusColor(PreInstallationWorkflowStatus status) {
  switch (status) {
    case PreInstallationWorkflowStatus.draft:
      return Colors.grey.shade600;
    case PreInstallationWorkflowStatus.survey_completed:
      return Colors.blue.shade700;
    case PreInstallationWorkflowStatus.approved_for_order:
      return Colors.purple.shade700;
    case PreInstallationWorkflowStatus.ready_for_factory_order:
      return Colors.purple.shade700;
    case PreInstallationWorkflowStatus.ordered:
      return Colors.orange.shade800;
    case PreInstallationWorkflowStatus.delivered_ready:
      return Colors.teal.shade700;
    case PreInstallationWorkflowStatus.available_on_site:
      return Colors.teal.shade700;
    case PreInstallationWorkflowStatus.released_to_installation:
      return Colors.green.shade700;
  }
}

String _preInstallStatusLabelForItem(PreInstallItem item) {
  if (item.deliveryConfirmed) {
    return 'Delivery Confirmed';
  }
  return _preInstallStatusLabel(item.preInstallationStatus);
}

Color _preInstallStatusColorForItem(PreInstallItem item) {
  if (item.deliveryConfirmed) {
    return Colors.teal.shade700;
  }
  return _preInstallStatusColor(item.preInstallationStatus);
}

String _supplyResponsibilityLabel(PreInstallItem item) {
  switch (item.supplyResponsibility) {
    case PreInstallSupplyResponsibility.bw_supply_install:
      return 'Our company supply';
    case PreInstallSupplyResponsibility.client_supplied:
      return 'Client supplied';
    case PreInstallSupplyResponsibility.main_contractor_supplied:
      return 'Main contractor supplied';
    case PreInstallSupplyResponsibility.custom:
      final custom = item.customSupplyResponsibility.trim();
      return custom.isEmpty ? 'Other supplied' : custom;
  }
}

String _workflowSummaryLine(PreInstallItem item) {
  if (isSpecificationOrderWorkflowType(item.surveyType)) {
    if (item.existingDoorRemovalRequired) {
      return 'Existing door removal required';
    }
    return 'New opening (no removal)';
  }
  if (item.supplyResponsibility ==
      PreInstallSupplyResponsibility.client_supplied) {
    return 'Client supplied doorset';
  }
  if (item.supplyResponsibility ==
      PreInstallSupplyResponsibility.main_contractor_supplied) {
    return 'Main contractor supplied doorset';
  }
  return 'Externally supplied doorset';
}

String _configLabel(String raw) {
  switch (raw) {
    case 'singleLeaf':
      return 'Single leaf';
    case 'doubleLeaf':
      return 'Double leaf';
    case 'leafAndHalf':
      return 'Leaf and half';
    default:
      return raw;
  }
}

class PreInstallationSurveyBuilderListScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final String workspaceKey;

  const PreInstallationSurveyBuilderListScreen({
    super.key,
    required this.surveyId,
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<PreInstallationSurveyBuilderListScreen> createState() =>
      _PreInstallationSurveyBuilderListScreenState();
}

class _PreInstallationSurveyBuilderListScreenState
    extends ConsumerState<PreInstallationSurveyBuilderListScreen> {
  final Set<String> _selectedItemIds = <String>{};

  void _toggleSelection(String itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
      }
    });
  }

  void _setAllSelections(List<PreInstallItem> items, bool selected) {
    setState(() {
      if (selected) {
        _selectedItemIds
          ..clear()
          ..addAll(items.map((item) => item.id));
      } else {
        _selectedItemIds.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final surveyId = widget.surveyId;
    final workspaceKey = widget.workspaceKey;
    final settingsController = ref.read(settingsControllerProvider.notifier);
    if (ref.read(settingsControllerProvider).activeWorkspaceKey !=
        workspaceKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        settingsController.setActiveWorkspace(workspaceKey);
      });
    }
    final workspace = parseInspectionWorkspaceKey(workspaceKey) ??
        InspectionWorkspace.fireDoor;
    final workspaceSlug = inspectionWorkspaceSlug(workspace);
    ref.watch(surveyControllerFamilyProvider(workspace));
    final controller =
        ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final settings = ref.watch(settingsControllerProvider);
    final survey = controller.getById(surveyId);
    final role = ref.watch(currentUserRoleProvider);
    final auth = ref.watch(authControllerProvider);
    final isManagerLike = role == UserRole.manager ||
        role == UserRole.owner ||
        role == UserRole.admin ||
        role == UserRole.superAdmin;

    if (survey == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }

    if (role == UserRole.worker) {
      final restrictedBody =
          const Center(child: Text('Access restricted to managers only.'));

      if (kIsWeb && workspaceKey == 'fire-door') {
        return FireDoorWebShellScaffold(
          title: 'Installation Surveys',
          workspaceKey: workspaceKey,
          currentRoute: '/workspace/$workspaceSlug/modules/preinstall/projects',
          workflowLabel: 'Installation Surveys',
          drawerRoute: '/workspace/$workspaceSlug/modules/preinstall/projects',
          body: restrictedBody,
        );
      }

      return Scaffold(
        appBar: AppBar(title: const Text('Installation Surveys')),
        body: restrictedBody,
      );
    }

    Future<void> exportSpecs() async {
      final companyId = auth.companyId;
      final userId = auth.uid.trim();
      if (companyId != null &&
          companyId.isNotEmpty &&
          !isDisclaimerAcceptanceCurrent(
            record: survey.disclaimerAcceptance,
            moduleType: 'fire-door',
            userId: userId,
          )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Declaration signature is required before completing pre-installation exports.')),
        );
        return;
      }

      final specificationItems = survey.preInstallItems
          .where((item) => isSpecificationOrderWorkflowType(item.surveyType))
          .toList();

      if (specificationItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'No Specification / Order items are available for manufacturing export.')),
        );
        return;
      }

      final mode = await showModalBottomSheet<_ExportType>(
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
                    'Choose one specification - exports a direct PDF, no ZIP.'),
                onTap: () => Navigator.pop(ctx, _ExportType.singleDoor),
              ),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Combined PDF for all specifications'),
                subtitle: const Text('One PDF with all specifications.'),
                onTap: () => Navigator.pop(ctx, _ExportType.combinedAllDoors),
              ),
              ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: const Text('All Doors - ZIP (one PDF per door)'),
                subtitle: const Text(
                    'Individual PDF per specification, packaged as a ZIP file.'),
                onTap: () => Navigator.pop(ctx, _ExportType.separatePerDoor),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

      if (mode == null) return;

      final branding = resolvePdfBranding(settings);

      Future<void> exportPdf(
          {required Survey sourceSurvey, required String reportType}) async {
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
                        subtitle: const Text(
                            'Opens your share sheet (Mail / Gmail / Outlook etc).'),
                        onTap: () => Navigator.pop(ctx, _ExportAction.email),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );

        if (action == null) return;

        final bytes = await PreInstallPdfBuilder.buildCombinedProjectPdf(
          sourceSurvey,
          companyName: branding.companyName,
          companyLogoBytes: branding.logoBytes,
          reportHeaderText: branding.reportHeaderText,
          reportFooterText: branding.reportFooterText,
        );
        final fileName = buildReportFileName(
          settings: settings,
          survey: sourceSurvey,
          reportType: reportType,
          extension: 'pdf',
        );

        if (action == _ExportAction.download) {
          if (kIsWeb) {
            downloadBytesWeb(
                bytes: bytes, fileName: fileName, mimeType: 'application/pdf');
          } else {
            await Printing.layoutPdf(onLayout: (_) async => bytes);
          }
          return;
        }

        await Printing.sharePdf(bytes: bytes, filename: fileName);
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

        if (action == null) return;

        final sourceSurvey =
            survey.copyWith(preInstallItems: specificationItems);
        final bytes = await PreInstallPdfBuilder.buildSeparateItemsZip(
          sourceSurvey,
          companyName: branding.companyName,
          companyLogoBytes: branding.logoBytes,
          reportHeaderText: branding.reportHeaderText,
          reportFooterText: branding.reportFooterText,
        );
        final fileName = buildReportFileName(
          settings: settings,
          survey: survey,
          reportType: 'PreInstall',
          extension: 'zip',
        );

        if (action == _ExportAction.download) {
          if (kIsWeb) {
            downloadBytesWeb(
                bytes: bytes, fileName: fileName, mimeType: 'application/zip');
          } else {
            await Printing.sharePdf(bytes: bytes, filename: fileName);
          }
          return;
        }

        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }

      if (mode == _ExportType.singleDoor) {
        if (!context.mounted) return;
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
                    'Choose specification to export',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final i in specificationItems)
                        ListTile(
                          leading:
                              Icon(_installationSurveyTypeIcon(i.surveyType)),
                          title: Text(i.doorRef.trim().isEmpty
                              ? 'Installation survey'
                              : i.doorRef.trim()),
                          subtitle: Text([
                            _installationSurveyTypeTitle(i.surveyType),
                            if (i.level.trim().isNotEmpty) 'Level: ${i.level}',
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

        if (chosenItem == null) return;
        final single = survey.copyWith(preInstallItems: [chosenItem]);
        await exportPdf(sourceSurvey: single, reportType: 'DoorSpec');
        return;
      }

      if (mode == _ExportType.combinedAllDoors) {
        final sourceSurvey =
            survey.copyWith(preInstallItems: specificationItems);
        await exportPdf(sourceSurvey: sourceSurvey, reportType: 'PreInstall');
        return;
      }

      await exportZip();
    }

    Future<bool> ensurePreinstallDisclaimer() async {
      final companyId = auth.companyId;
      final userId = auth.uid.trim();
      if (companyId == null || companyId.isEmpty || userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Company or user context is missing.')),
        );
        return false;
      }

      const moduleType = 'fire-door';

      final existingLocal = survey.disclaimerAcceptance;
      if (isDisclaimerAcceptanceCurrent(
        record: existingLocal,
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

      if (!context.mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Declaration signature is required in Project Details before adding pre-installation items.'),
        ),
      );
      context.go(
          '/workspace/$workspaceSlug/modules/preinstall/projects/$surveyId/details');
      return false;
    }

    Future<void> createInstallationSurvey(
      PreInstallSurveyType surveyType, {
      required bool existingDoorRemovalRequired,
    }) async {
      final allowed = await ensurePreinstallDisclaimer();
      if (!allowed) return;
      controller.addPreInstallItem(
        surveyId,
        surveyType: surveyType,
        existingDoorRemovalRequired: existingDoorRemovalRequired,
      );
      final updated = controller.getById(surveyId);
      if (updated == null || updated.preInstallItems.isEmpty) {
        return;
      }
      final newItem = updated.preInstallItems.last;
      if (!context.mounted) return;
      context.go(
          '/workspace/$workspaceSlug/preinstall/$surveyId/items/${newItem.id}');
    }

    Future<void> openNewInstallationSurveySheet() async {
      final selected = await showModalBottomSheet<_WorkflowChoice>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'New Installation Survey',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose the workflow that matches what is on site. Drawing upload, viewing and PIN assignment stay aligned with Inspection Projects.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                for (final choice in _WorkflowChoice.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(ctx, choice),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (choice == _WorkflowChoice.specificationOrder
                                    ? Colors.blue.shade700
                                    : Colors.green.shade700)
                                .withValues(alpha: 0.35),
                          ),
                          color: (choice == _WorkflowChoice.specificationOrder
                                  ? Colors.blue.shade700
                                  : Colors.green.shade700)
                              .withValues(alpha: 0.06),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: (choice ==
                                            _WorkflowChoice.specificationOrder
                                        ? Colors.blue.shade700
                                        : Colors.green.shade700)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                choice == _WorkflowChoice.specificationOrder
                                    ? Icons.assignment_outlined
                                    : Icons.handyman_outlined,
                                color:
                                    choice == _WorkflowChoice.specificationOrder
                                        ? Colors.blue.shade700
                                        : Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    choice == _WorkflowChoice.specificationOrder
                                        ? 'Specification / Order Workflow'
                                        : 'Installation Only Workflow',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    choice == _WorkflowChoice.specificationOrder
                                        ? 'Used when measuring/specifying a new doorset for manufacture, pricing, ordering and installation.'
                                        : 'Used when the doorset is already supplied by the client/main contractor and only installation tracking/assignment is required.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade800,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    choice == _WorkflowChoice.specificationOrder
                                        ? 'Supports both replacement and new opening via one unified specification flow.'
                                        : 'Skips manufacturing/order stages and goes directly to installation tracking + release.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              color:
                                  choice == _WorkflowChoice.specificationOrder
                                      ? Colors.blue.shade700
                                      : Colors.green.shade700,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      if (selected == null) return;
      if (selected == _WorkflowChoice.installationOnly) {
        await createInstallationSurvey(
          PreInstallSurveyType.installation_only,
          existingDoorRemovalRequired: false,
        );
        return;
      }

      final removalRequired = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Existing Door Removal Required?',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 8),
                Text(
                  'YES: existing door must be removed before installation. NO: new opening only.',
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.construction_outlined),
                  label: const Text('YES - Existing door removal required'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, false),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('NO - New opening (no removal)'),
                ),
              ],
            ),
          ),
        ),
      );
      if (removalRequired == null) return;
      await createInstallationSurvey(
        PreInstallSurveyType.specification_order,
        existingDoorRemovalRequired: removalRequired,
      );
    }

    final selectedCount = _selectedItemIds.length;
    final allItemsSelected = survey.preInstallItems.isNotEmpty &&
        selectedCount == survey.preInstallItems.length;

    Future<bool> _confirmPermanentDelete(BuildContext context) async {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permanently delete survey?'),
          content: const Text(
            'This action cannot be undone. All survey data will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      );
      return result == true;
    }

    // Visibility dialog: returns null if dismissed, otherwise ({visible, from})
    Future<({bool visible, DateTime? from})?> _showWorkerVisibilityDialog(
        BuildContext ctx) async {
      int choice = 0; // 0=not now, 1=immediately, 2=choose date
      DateTime? chosenDate;

      return showModalBottomSheet<({bool visible, DateTime? from})>(
        context: ctx,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetCtx) => StatefulBuilder(
          builder: (sbCtx, setSS) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Make visible to workers / subcontractors?',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Workers can review upcoming scope, prepare pricing and plan — without receiving an active installation task.',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<int>(
                    value: 0,
                    groupValue: choice,
                    title: const Text('Not now'),
                    subtitle: const Text('Workers cannot see this item yet.'),
                    onChanged: (v) => setSS(() => choice = v!),
                  ),
                  RadioListTile<int>(
                    value: 1,
                    groupValue: choice,
                    title: const Text('Visible immediately'),
                    subtitle:
                        const Text('Workers can see this item straight away.'),
                    onChanged: (v) => setSS(() => choice = v!),
                  ),
                  RadioListTile<int>(
                    value: 2,
                    groupValue: choice,
                    title: const Text('Choose visibility date'),
                    subtitle: chosenDate == null
                        ? const Text('Select a future date.')
                        : Text(
                            'Visible from: ${chosenDate!.day.toString().padLeft(2, '0')}/${chosenDate!.month.toString().padLeft(2, '0')}/${chosenDate!.year}',
                          ),
                    onChanged: (v) async {
                      setSS(() => choice = v!);
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: sbCtx,
                        initialDate: now.add(const Duration(days: 1)),
                        firstDate: now,
                        lastDate: DateTime(now.year + 5),
                      );
                      if (picked != null) {
                        setSS(() => chosenDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      if (choice == 0) {
                        Navigator.pop(sbCtx, (visible: false, from: null));
                      } else if (choice == 1) {
                        Navigator.pop(sbCtx, (visible: true, from: null));
                      } else {
                        Navigator.pop(sbCtx, (visible: true, from: chosenDate));
                      }
                    },
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Future<void> _handlePreInstallItemAction(
        PreInstallItem item, String action) async {
      final actionBy = auth.currentUser?.name.trim().isNotEmpty == true
          ? auth.currentUser!.name.trim()
          : (auth.email.trim().isNotEmpty ? auth.email.trim() : auth.uid);
      final now = DateTime.now();

      if (action == 'approve_for_order') {
        final visibility = await _showWorkerVisibilityDialog(context);
        if (!mounted) return;
        controller.updatePreInstallItem(
          surveyId: surveyId,
          itemId: item.id,
          update: (current) => current.copyWith(
            preInstallationStatus:
                PreInstallationWorkflowStatus.approved_for_order,
            visibleToWorkers: visibility?.visible ?? false,
            workerVisibleFrom: visibility?.from,
            clearWorkerVisibleFrom: visibility == null || !visibility.visible,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item approved for order.')),
        );
      } else if (action == 'confirm_available_on_site') {
        controller.updatePreInstallItem(
          surveyId: surveyId,
          itemId: item.id,
          update: (current) => current.copyWith(
            preInstallationStatus:
                PreInstallationWorkflowStatus.available_on_site,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as available on site.')),
        );
      } else if (action == 'confirm_delivery') {
        controller.updatePreInstallItem(
          surveyId: surveyId,
          itemId: item.id,
          update: (current) => current.copyWith(
            deliveryConfirmed: true,
            deliveryConfirmedAt: now,
            deliveryConfirmedBy: actionBy,
            preInstallationStatus:
                PreInstallationWorkflowStatus.delivered_ready,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery confirmed.')),
        );
      } else if (action == 'delete') {
        final confirmed = await _confirmPermanentDelete(context);
        if (!confirmed) return;
        controller.deletePreInstallItem(surveyId: surveyId, itemId: item.id);
      }
    }

    Future<void> bulkDeleteSelected() async {
      if (_selectedItemIds.isEmpty) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete selected surveys?'),
          content: Text(
            'You are about to permanently delete $selectedCount selected survey item(s). This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete selected'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final idsToDelete = _selectedItemIds.toList(growable: false);
      for (final itemId in idsToDelete) {
        controller.deletePreInstallItem(surveyId: surveyId, itemId: itemId);
      }

      if (!mounted) return;
      setState(() => _selectedItemIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${idsToDelete.length} item(s).')),
      );
    }

    // Approve for Order — spec/order items only
    Future<void> bulkApproveForOrder() async {
      final specItems = survey.preInstallItems
          .where((i) =>
              _selectedItemIds.contains(i.id) &&
              isSpecificationOrderWorkflowType(i.surveyType))
          .toList();
      if (specItems.isEmpty) return;

      final visibility = await _showWorkerVisibilityDialog(context);
      if (!mounted) return;

      final now = DateTime.now();
      for (final item in specItems) {
        controller.updatePreInstallItem(
          surveyId: surveyId,
          itemId: item.id,
          update: (current) => current.copyWith(
            preInstallationStatus:
                PreInstallationWorkflowStatus.approved_for_order,
            visibleToWorkers: visibility?.visible ?? false,
            workerVisibleFrom: visibility?.from,
            clearWorkerVisibleFrom: visibility == null || !visibility.visible,
          ),
        );
      }

      final skipped = selectedCount - specItems.length;
      final msg = skipped > 0
          ? 'Approved ${specItems.length} item(s). $skipped Installation Only item(s) skipped.'
          : 'Approved ${specItems.length} item(s) for order.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    // Confirm Delivery — spec/order items only
    Future<void> bulkConfirmDelivery() async {
      if (_selectedItemIds.isEmpty) return;
      final actionBy = auth.currentUser?.name.trim().isNotEmpty == true
          ? auth.currentUser!.name.trim()
          : (auth.email.trim().isNotEmpty ? auth.email.trim() : auth.uid);
      final now = DateTime.now();
      var count = 0;
      for (final item in survey.preInstallItems) {
        if (!_selectedItemIds.contains(item.id)) continue;
        if (!isSpecificationOrderWorkflowType(item.surveyType)) continue;
        if (item.deliveryConfirmed) continue;
        controller.updatePreInstallItem(
          surveyId: surveyId,
          itemId: item.id,
          update: (current) => current.copyWith(
            deliveryConfirmed: true,
            deliveryConfirmedAt: now,
            deliveryConfirmedBy: actionBy,
            preInstallationStatus:
                PreInstallationWorkflowStatus.delivered_ready,
          ),
        );
        count += 1;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(count == 0
                ? 'No eligible items for delivery confirmation.'
                : 'Delivery confirmed for $count item(s).')),
      );
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
                      onPressed: () => ProjectDrawingAccess.showDrawingPicker(
                          context: context, survey: survey),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('View Drawing'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => context.go(
                          '/workspace/$workspaceSlug/modules/preinstall/projects/$surveyId/details'),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Upload Drawing'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: exportSpecs,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Generate Survey PDF'),
                    ),
                  ),
                ],
              ),
            ),
            if (isManagerLike)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'New Installation Survey',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: openNewInstallationSurveySheet,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('New Installation Survey'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blue.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue.shade600,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Use one entry point for every installation workflow. Drawing upload, viewing and PIN assignment stay consistent with Inspection Projects.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Selection header row
                    Row(
                      children: [
                        Checkbox(
                          value: allItemsSelected,
                          onChanged: survey.preInstallItems.isEmpty
                              ? null
                              : (value) => _setAllSelections(
                                  survey.preInstallItems, value ?? false),
                        ),
                        const Text('All'),
                        const Spacer(),
                        if (_selectedItemIds.isNotEmpty)
                          Text(
                            '$selectedCount selected',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                      ],
                    ),
                    // Contextual bulk action bar — only shown when items are selected
                    if (_selectedItemIds.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // Approve for Order — spec/order items only
                            if (survey.preInstallItems.any((i) =>
                                _selectedItemIds.contains(i.id) &&
                                isSpecificationOrderWorkflowType(i.surveyType)))
                              OutlinedButton.icon(
                                onPressed: bulkApproveForOrder,
                                icon: const Icon(Icons.approval_outlined,
                                    size: 18),
                                label: const Text('Approve for Order'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.purple.shade700,
                                  side:
                                      BorderSide(color: Colors.purple.shade300),
                                ),
                              ),
                            // Confirm Delivery — spec/order items only
                            if (survey.preInstallItems.any((i) =>
                                _selectedItemIds.contains(i.id) &&
                                isSpecificationOrderWorkflowType(
                                    i.surveyType) &&
                                !i.deliveryConfirmed))
                              OutlinedButton.icon(
                                onPressed: bulkConfirmDelivery,
                                icon: const Icon(Icons.local_shipping_outlined,
                                    size: 18),
                                label: const Text('Confirm Delivery'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.teal.shade700,
                                  side: BorderSide(color: Colors.teal.shade300),
                                ),
                              ),

                            // Delete selected
                            OutlinedButton.icon(
                              onPressed: bulkDeleteSelected,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: Text('Delete ($selectedCount)'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: survey.preInstallItems.isEmpty
                  ? const Center(
                      child: Text(
                        'No installation surveys added yet.\nCreate your first survey to start.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: survey.preInstallItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = survey.preInstallItems[index];
                        final title = item.doorRef.isEmpty
                            ? 'Installation Survey ${index + 1}'
                            : item.doorRef;
                        final isSpecOrder =
                            isSpecificationOrderWorkflowType(item.surveyType);
                        final workflowColor = isSpecOrder
                            ? Colors.blue.shade700
                            : Colors.green.shade700;
                        final statusLabel = _preInstallStatusLabelForItem(item);
                        final statusColor = _preInstallStatusColorForItem(item);

                        // Build contextual 3-dot menu items
                        final menuItems = <PopupMenuEntry<String>>[];
                        menuItems.add(const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ));
                        if (isManagerLike) {
                          if (isSpecOrder &&
                              item.preInstallationStatus ==
                                  PreInstallationWorkflowStatus
                                      .survey_completed) {
                            menuItems.add(const PopupMenuItem(
                              value: 'approve_for_order',
                              child: Text('Approve for Order'),
                            ));
                          }
                          if (!isSpecOrder &&
                              item.preInstallationStatus ==
                                  PreInstallationWorkflowStatus.draft) {
                            menuItems.add(const PopupMenuItem(
                              value: 'confirm_available_on_site',
                              child: Text('Confirm Available on Site'),
                            ));
                          }
                          if (isSpecOrder && !item.deliveryConfirmed) {
                            menuItems.add(const PopupMenuItem(
                              value: 'confirm_delivery',
                              child: Text('Confirm Delivery'),
                            ));
                          }

                          menuItems.add(const PopupMenuDivider());
                          menuItems.add(const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete permanently',
                                style: TextStyle(color: Colors.red)),
                          ));
                        }

                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: _selectedItemIds.contains(item.id)
                                  ? Colors.blue.shade400
                                  : Colors.grey.shade300,
                              width: _selectedItemIds.contains(item.id) ? 2 : 1,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => context.go(
                                '/workspace/$workspaceSlug/preinstall/$surveyId/items/${item.id}'),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Checkbox
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Checkbox(
                                      value: _selectedItemIds.contains(item.id),
                                      onChanged: (_) =>
                                          _toggleSelection(item.id),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Ref + workflow badge row
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                title,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 15),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: workflowColor.withValues(
                                                    alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                    color: workflowColor
                                                        .withValues(
                                                            alpha: 0.4)),
                                              ),
                                              child: Text(
                                                isSpecOrder
                                                    ? 'Spec / Order'
                                                    : 'Install Only',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: workflowColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // Workflow summary
                                        Text(
                                          _workflowSummaryLine(item),
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade700),
                                        ),
                                        // Fire rating / config / frame
                                        if (item.fireRating.trim().isNotEmpty ||
                                            item.configuration
                                                .trim()
                                                .isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              [
                                                if (item.fireRating
                                                    .trim()
                                                    .isNotEmpty)
                                                  item.fireRating
                                                      .trim()
                                                      .toUpperCase(),
                                                if (item.configuration
                                                    .trim()
                                                    .isNotEmpty)
                                                  _configLabel(item
                                                      .configuration
                                                      .trim()),
                                                item.hasFrame
                                                    ? 'Door + Frame'
                                                    : 'Door only',
                                              ].join('  •  '),
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600),
                                            ),
                                          ),
                                        // Level / location
                                        if (item.level.trim().isNotEmpty ||
                                            item.location.trim().isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              [
                                                if (item.level
                                                    .trim()
                                                    .isNotEmpty)
                                                  item.level.trim(),
                                                if (item.location
                                                    .trim()
                                                    .isNotEmpty)
                                                  item.location.trim(),
                                              ].join('  •  '),
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600),
                                            ),
                                          ),
                                        const SizedBox(height: 8),
                                        // Status + visibility chips
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            // Status chip
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                    alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                    color:
                                                        statusColor.withValues(
                                                            alpha: 0.4)),
                                              ),
                                              child: Text(
                                                statusLabel,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: statusColor),
                                              ),
                                            ),
                                            // Expected delivery date chip
                                            if (item.expectedDeliveryDate !=
                                                    null &&
                                                !item.deliveryConfirmed)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                      color: Colors
                                                          .orange.shade300),
                                                ),
                                                child: Text(
                                                  'Expected ${item.expectedDeliveryDate!.day.toString().padLeft(2, '0')}/${item.expectedDeliveryDate!.month.toString().padLeft(2, '0')}/${item.expectedDeliveryDate!.year}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors
                                                          .orange.shade800),
                                                ),
                                              ),
                                            // Worker visibility chip
                                            if (item.visibleToWorkers)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.indigo.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                      color: Colors
                                                          .indigo.shade300),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.visibility_outlined,
                                                      size: 13,
                                                      color: Colors
                                                          .indigo.shade700,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      item.workerVisibleFrom !=
                                                              null
                                                          ? 'Visible from ${item.workerVisibleFrom!.day.toString().padLeft(2, '0')}/${item.workerVisibleFrom!.month.toString().padLeft(2, '0')}/${item.workerVisibleFrom!.year}'
                                                          : 'Visible to workers',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors
                                                              .indigo.shade700),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 3-dot menu
                                  PopupMenuButton<String>(
                                    onSelected: (action) {
                                      if (action == 'edit') {
                                        context.go(
                                            '/workspace/$workspaceSlug/preinstall/$surveyId/items/${item.id}');
                                      } else {
                                        _handlePreInstallItemAction(
                                            item, action);
                                      }
                                    },
                                    itemBuilder: (ctx) => menuItems,
                                    child: const Icon(Icons.more_vert),
                                  ),
                                ],
                              ),
                            ),
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
        title: 'Installation Surveys',
        workspaceKey: workspaceKey,
        currentRoute: '/workspace/$workspaceSlug/modules/preinstall/projects',
        body: pageBody,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      drawer: AppDrawer(
          currentRoute:
              '/workspace/$workspaceSlug/modules/preinstall/projects'),
      appBar: AppBar(
        title: const Text('Installation Surveys'),
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
}
