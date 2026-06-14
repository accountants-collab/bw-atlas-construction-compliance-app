import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../../../auth/auth_state.dart';
import '../../../app/ui/app_visual_system.dart';
import '../../../app/ui/branding_resolver.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../disclaimer/ui/disclaimer_acceptance_section.dart';
import '../../disclaimer/ui/disclaimer_capture_sheet.dart';
import '../../fire_door/inspection/domain/models.dart';
import '../../fire_door/inspection/state/survey_controller.dart';
import '../../fire_door/inspection/ui/project_drawing_viewer.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_controller.dart';
import '../state/snagging_module_controller.dart';

class SnaggingProjectDetailsScreen extends ConsumerStatefulWidget {
  final String projectId;
  const SnaggingProjectDetailsScreen({super.key, required this.projectId});

  @override
  ConsumerState<SnaggingProjectDetailsScreen> createState() =>
      _SnaggingProjectDetailsScreenState();
}

class _SnaggingProjectDetailsScreenState
    extends ConsumerState<SnaggingProjectDetailsScreen> {
  final _name = TextEditingController();
  final _reference = TextEditingController();
  final _client = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _postcode = TextEditingController();
  final _city = TextEditingController();
  final _clientEmail = TextEditingController();
  final _clientPhone = TextEditingController();
  final _preparedFor = TextEditingController();
  DateTime _date = DateTime.now();
  final Set<String> _selectedGroupIds = <String>{};
  bool _loaded = false;
  bool _showLinkExisting = false;
  String? _linkedFromWorkspace;

  void _goBackToProjects() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/workspace/snagging/inspection/projects');
  }

  Future<void> _showExistingProjectsDialog() async {
    final surveyCtrl = ref.read(
        surveyControllerFamilyProvider(InspectionWorkspace.snagging).notifier);
    final projects = await surveyCtrl.listProjectDetailsFromAllWorkspaces();

    if (!mounted) return;
    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No projects found in other modules.')),
      );
      return;
    }

    final selected = await showDialog<Survey>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link Existing Project'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: projects.length,
            itemBuilder: (ctx, idx) {
              final p = projects[idx];
              final displayName = p.reportName.trim().isNotEmpty
                  ? p.reportName
                  : p.siteName.trim().isNotEmpty
                      ? p.siteName
                      : p.addressLine1.trim().isNotEmpty
                          ? p.addressLine1
                          : 'Unnamed Project';
              return ListTile(
                title: Text(displayName),
                subtitle: Text(
                  '${p.addressLine1.isNotEmpty ? p.addressLine1 : ''} ${p.cityTown.isNotEmpty ? p.cityTown : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  p.workspace.toString().split('.').last.toUpperCase(),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                onTap: () => Navigator.of(ctx).pop(p),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected == null || !mounted) return;

    setState(() {
      _name.text =
          selected.reportName.isEmpty ? selected.siteName : selected.reportName;
      _reference.text = selected.reference;
      _client.text = selected.clientName;
      _address1.text = selected.addressLine1;
      _address2.text = selected.addressLine2;
      _postcode.text = selected.postCode;
      _city.text = selected.cityTown;
      _clientEmail.text = selected.clientEmail;
      _clientPhone.text = selected.clientPhone;
      _preparedFor.text = selected.reportCompletedBy;
      _date = selected.reportDate;
      _linkedFromWorkspace = selected.workspace.toString().split('.').last;
      _showLinkExisting = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Project linked from ${_linkedFromWorkspace ?? 'module'}')),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _reference.dispose();
    _client.dispose();
    _address1.dispose();
    _address2.dispose();
    _postcode.dispose();
    _city.dispose();
    _clientEmail.dispose();
    _clientPhone.dispose();
    _preparedFor.dispose();
    super.dispose();
  }

  bool _canManageProjectAccess(AuthState auth) {
    final role = auth.userRole ?? UserRole.worker;
    final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
    return role == UserRole.manager || role == UserRole.owner || isSuperAdmin;
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      );

  String _fmtDateCompact(DateTime d) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool isOptional = false,
    Widget? headerTrailing,
  }) {
    const accent = Color(0xFF1E3A5F);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isOptional ? Colors.grey.shade200 : Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 16, color: isOptional ? Colors.grey.shade500 : accent),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: isOptional ? 13 : 15,
                  color: isOptional ? Colors.grey.shade600 : accent,
                ),
              ),
              const Spacer(),
              if (headerTrailing != null) headerTrailing,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Future<void> _quickCreateGroup({
    required SettingsController settingsCtrl,
  }) async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Group'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
            hintText: 'Group 1 / Subcontractor',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (confirmed != true) return;

    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    settingsCtrl.createWorkspaceGroup(workspaceKey: 'snagging', name: name);
  }

  Future<void> _openDisclaimerForm({
    required Survey survey,
    required SurveyController controller,
    required String companyId,
  }) async {
    final accepted = await showDisclaimerCaptureSheet(
      context: context,
      ref: ref,
      companyId: companyId,
      projectId: survey.id,
      reportId: survey.id,
      moduleType: 'snagging',
      projectName: survey.reportName.trim().isEmpty
          ? survey.siteName
          : survey.reportName,
      projectNumber: survey.reference,
      reportReference: survey.registerReference,
    );
    if (accepted == null) return;
    controller.setSurveyDisclaimerRecord(surveyId: survey.id, record: accepted);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(snaggingModuleControllerProvider.notifier);
    final surveyController = ref.read(
        surveyControllerFamilyProvider(InspectionWorkspace.snagging).notifier);
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final settingsCtrl = ref.read(settingsControllerProvider.notifier);
    final project = controller.getProject(widget.projectId);
    if (project == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }

    final linkedSurvey = project.surveyId.isEmpty
        ? null
        : surveyController.getById(project.surveyId);
    final availableGroups =
        settings.workspaceGroups['snagging'] ?? const <WorkspaceWorkerGroup>[];
    final canManageProjectAccess = _canManageProjectAccess(auth);
    final activeLogo = getActiveLogo(settings.companyProfile);
    final activeCompanyName = getActiveCompanyName(settings.companyProfile);

    if (!_loaded) {
      _loaded = true;
      _name.text = project.name;
      _reference.text = linkedSurvey?.reference ?? '';
      _client.text = project.client;
      _address1.text = project.addressLine1;
      _address2.text = project.addressLine2;
      _postcode.text = project.postcode;
      _city.text = project.city;
      _clientEmail.text = project.clientEmail;
      _clientPhone.text = project.clientPhone;
      _preparedFor.text = project.preparedFor;
      _date = project.date;
      _selectedGroupIds
        ..clear()
        ..addAll(linkedSurvey?.assignedGroupIds ?? const <String>[]);
    }

    Future<void> uploadDrawings() async {
      if (linkedSurvey == null) return;
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );
      if (result == null) return;
      final drawings = result.files
          .where((f) => f.bytes != null && f.bytes!.isNotEmpty)
          .map((f) {
        final ext = (f.extension ?? '').toLowerCase();
        final mime = ext == 'pdf' ? 'application/pdf' : 'image/*';
        return ProjectDrawing(
          fileName: f.name,
          mimeType: mime,
          bytes: f.bytes!,
        );
      }).toList();
      if (drawings.isEmpty) return;
      surveyController.addProjectDrawings(
          surveyId: linkedSurvey.id, drawings: drawings);
    }

    final content = ListView(
      padding:
          const EdgeInsets.fromLTRB(AppSpace.m, AppSpace.s, AppSpace.m, 32),
      children: [
        // ── QUICK LINK: Link Existing Project ─────────────────
        if (!_showLinkExisting)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reuse Project Details',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Link an existing project from Fire Door, Fire Stopping, or another module.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _showExistingProjectsDialog,
                    icon: const Icon(Icons.link_outlined, size: 18),
                    label: const Text('Link', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        if (_linkedFromWorkspace != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outlined,
                      color: Color(0xFF2E7D32), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Project linked from $_linkedFromWorkspace module',
                      style: const TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _linkedFromWorkspace = null),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0)),
                    child: const Text(
                      'Unlink',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── SECTION 1: Core Project Details ──────────────────
        _sectionCard(
          title: 'Project & Inspection Details',
          icon: Icons.description_outlined,
          headerTrailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmtDateCompact(_date),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked == null) return;
                  setState(() => _date = picked);
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: const Size(0, 0),
                ),
                child: const Text('Change'),
              ),
            ],
          ),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;
                final fieldWidth = isWide
                    ? (constraints.maxWidth - AppSpace.s) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: AppSpace.s,
                  runSpacing: AppSpace.s,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _name,
                        decoration: _dec('Project Name'),
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _reference,
                        decoration: _dec('Project Number'),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Reports use the active company profile. If no custom company logo has been uploaded, the default app logo is used automatically.',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600, height: 1.35),
            ),
          ],
        ),

        const SizedBox(height: 10),

        _sectionCard(
          title: 'Site Address',
          icon: Icons.location_on_outlined,
          children: [
            TextFormField(
              controller: _address1,
              decoration: _dec('Site Address Line 1'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _address2,
              decoration: _dec('Site Address Line 2'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _city,
                    decoration: _dec('City / Town'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _postcode,
                    decoration: _dec('Post Code'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 10),

        // ── SECTION 2: Additional Details ─────────────────────
        _sectionCard(
          title: 'Client',
          icon: Icons.business_outlined,
          children: [
            TextFormField(
              controller: _client,
              decoration: _dec('Client Name'),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;
                final fieldWidth = isWide
                    ? (constraints.maxWidth - AppSpace.s) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: AppSpace.s,
                  runSpacing: AppSpace.s,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _clientEmail,
                        decoration: _dec('Client Email'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: TextFormField(
                        controller: _clientPhone,
                        decoration: _dec('Client Phone'),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _preparedFor,
              decoration: _dec('Prepared For / Responsible Company'),
            ),
          ],
        ),

        const SizedBox(height: 10),

        _sectionCard(
          title: 'Company / Report Branding',
          icon: Icons.verified_user_outlined,
          children: [
            Text(
              'Active company: ${activeCompanyName.trim().isEmpty ? kDefaultSystemCompanyName : activeCompanyName}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              activeLogo.hasCompanyLogo
                  ? 'Custom company logo is active for reports.'
                  : 'No custom company logo uploaded. The default app/company logo is used automatically.',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade700, height: 1.35),
            ),
          ],
        ),

        const SizedBox(height: 10),

        _sectionCard(
          title: 'Worker / Access Groups',
          icon: Icons.groups_2_outlined,
          children: [
            Text(
              'Assign one or more workspace groups only if this project should be restricted. If no group is selected, access stays open to all team members.',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade700, height: 1.35),
            ),
            const SizedBox(height: 8),
            Text(
              availableGroups.isEmpty
                  ? 'No workspace groups created yet. Access remains open to all team members.'
                  : _selectedGroupIds.isEmpty
                      ? 'No group assigned.'
                      : availableGroups
                          .where((g) => _selectedGroupIds.contains(g.id))
                          .map((g) => g.name)
                          .join(', '),
              style: TextStyle(
                fontSize: 13,
                color: _selectedGroupIds.isEmpty
                    ? Colors.grey.shade600
                    : Colors.black87,
              ),
            ),
            if (availableGroups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final group in availableGroups)
                    FilterChip(
                      label: Text(group.name,
                          style: const TextStyle(fontSize: 12)),
                      selected: _selectedGroupIds.contains(group.id),
                      onSelected: canManageProjectAccess
                          ? (v) {
                              setState(() {
                                if (v) {
                                  _selectedGroupIds.add(group.id);
                                } else {
                                  _selectedGroupIds.remove(group.id);
                                }
                              });
                            }
                          : null,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (canManageProjectAccess)
              TextButton.icon(
                onPressed: () => _quickCreateGroup(settingsCtrl: settingsCtrl),
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Create Group'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
          ],
        ),

        if (linkedSurvey != null) ...[
          const SizedBox(height: 10),
          _sectionCard(
            title: 'Project Drawings / Plans (DRW)',
            icon: Icons.map_outlined,
            children: [
              Text(
                'Upload PDF, JPG or PNG plans to support shared navigation and drawing pins across the project.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 8),
              Text(
                linkedSurvey.projectDrawings.isEmpty
                    ? 'No drawings uploaded yet. You can continue without one.'
                    : '${linkedSurvey.projectDrawings.length} drawing(s) available for this project.',
                style: TextStyle(
                  fontSize: 13,
                  color: linkedSurvey.projectDrawings.isEmpty
                      ? Colors.grey.shade600
                      : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: uploadDrawings,
                    icon: const Icon(Icons.upload_file_outlined, size: 16),
                    label: const Text('Upload Drawing'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: linkedSurvey.projectDrawings.isEmpty
                        ? null
                        : () async {
                            await ProjectDrawingAccess.showDrawingPicker(
                              context: context,
                              survey: linkedSurvey,
                            );
                          },
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View Drawing'),
                  ),
                ],
              ),
            ],
          ),
        ],

        if (linkedSurvey != null &&
            auth.companyId != null &&
            auth.companyId!.isNotEmpty) ...[
          const SizedBox(height: 10),
          DisclaimerAcceptanceSection(
            companyId: auth.companyId!,
            reportId: linkedSurvey.id,
            moduleType: 'snagging',
            onOpenDisclaimerForm: () => _openDisclaimerForm(
              survey: linkedSurvey,
              controller: surveyController,
              companyId: auth.companyId!,
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ── Save button ────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              controller.updateProject(
                widget.projectId,
                (p) => p.copyWith(
                  name: _name.text.trim(),
                  client: _client.text.trim(),
                  addressLine1: _address1.text.trim(),
                  addressLine2: _address2.text.trim(),
                  postcode: _postcode.text.trim(),
                  city: _city.text.trim(),
                  clientEmail: _clientEmail.text.trim(),
                  clientPhone: _clientPhone.text.trim(),
                  preparedFor: _preparedFor.text.trim(),
                  date: _date,
                ),
              );

              if (project.surveyId.isNotEmpty) {
                surveyController.updateSurveyMeta(
                  surveyId: project.surveyId,
                  reportName: _name.text.trim(),
                  reference: _reference.text.trim(),
                  clientName: _client.text.trim(),
                  addressLine1: _address1.text.trim(),
                  addressLine2: _address2.text.trim(),
                  cityTown: _city.text.trim(),
                  postCode: _postcode.text.trim(),
                  clientEmail: _clientEmail.text.trim(),
                  clientPhone: _clientPhone.text.trim(),
                  reportDate: _date,
                  assignedGroupIds: _selectedGroupIds.toList(),
                );
              }

              context.go(
                  '/workspace/snagging/inspection/projects/${widget.projectId}/items');
            },
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text(
              'Save & Continue',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute:
            '/workspace/snagging/inspection/projects/${widget.projectId}/details',
        title: 'Snagging Inspection',
        workflowLabel: 'Inspection Projects',
        drawerRoute: '/workspace/snagging/inspection/projects',
        workspaceKey: 'snagging',
        surveyId: widget.projectId,
        body: content,
      );
    }

    final isApplePlatform = defaultTargetPlatform == TargetPlatform.iOS;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBackToProjects();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(
                isApplePlatform ? Icons.arrow_back_ios_new : Icons.arrow_back),
            onPressed: _goBackToProjects,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          title: const Text('Snagging Inspection'),
          bottom:
              const WorkspaceSwitchCardsBar(currentWorkspaceKey: 'snagging'),
        ),
        body: content,
      ),
    );
  }
}
