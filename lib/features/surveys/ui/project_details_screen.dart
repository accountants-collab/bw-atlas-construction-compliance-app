import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_service.dart';
import '../../../auth/auth_state.dart';
import '../../notifications/data/firebase_email_queue_service.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_controller.dart';
import '../../storage/data/company_file_providers.dart';
import '../../storage/domain/company_file_record.dart';
import '../../disclaimer/ui/disclaimer_acceptance_section.dart';
import '../../disclaimer/ui/disclaimer_capture_sheet.dart';
import '../domain/models.dart';
import '../state/survey_controller.dart';
import 'project_drawing_viewer.dart';

class ProjectDetailsScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final String moduleKey;
  final String workspaceKey;
  const ProjectDetailsScreen({
    super.key,
    required this.surveyId,
    required this.moduleKey,
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends ConsumerState<ProjectDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _reportNameController = TextEditingController();
  final _referenceController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityTownController = TextEditingController();
  final _postCodeController = TextEditingController();
  final _clientNameController = TextEditingController();
  final _clientEmailController = TextEditingController();
  final _clientPhoneController = TextEditingController();
  DateTime _reportDate = DateTime.now();
  final Set<String> _selectedGroupIds = <String>{};
  String? _quickWorkerId;

  bool _loaded = false;
  bool _cloudSynced = false;

  @override
  void dispose() {
    _reportNameController.dispose();
    _referenceController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityTownController.dispose();
    _postCodeController.dispose();
    _clientNameController.dispose();
    _clientEmailController.dispose();
    _clientPhoneController.dispose();
    super.dispose();
  }

  bool _canManageProjectAccess(AuthState auth) {
    final role = auth.userRole ?? UserRole.worker;
    final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
    return role == UserRole.manager || role == UserRole.owner || isSuperAdmin;
  }

  Future<void> _quickCreateGroup({
    required SettingsController settingsCtrl,
    required String workspaceKey,
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (confirmed != true) return;

    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    settingsCtrl.createWorkspaceGroup(workspaceKey: workspaceKey, name: name);
  }

  Future<void> _showGroupInviteActions({
    required AuthController authCtrl,
    required SettingsController settingsCtrl,
    required AppSettings settings,
    required List<WorkspaceWorkerGroup> availableGroups,
    required List<AppUser> users,
  }) async {
    if (availableGroups.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a group first, then invite or assign team members.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Invite to Group',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose how to add access to this group.',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAssignExistingMemberDialog(
                    settingsCtrl: settingsCtrl,
                    availableGroups: availableGroups,
                    users: users,
                  );
                },
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Add Existing Team Member'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showSendGroupInviteDialog(
                    authCtrl: authCtrl,
                    settings: settings,
                    availableGroups: availableGroups,
                  );
                },
                icon: const Icon(Icons.link_outlined),
                label: const Text('Send Invite Link'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAssignExistingMemberDialog({
    required SettingsController settingsCtrl,
    required List<WorkspaceWorkerGroup> availableGroups,
    required List<AppUser> users,
  }) async {
    final activeMembers = users
        .where((u) => u.status == UserAccountStatus.active && !u.isInternalAdmin)
        .toList();
    try {
      if (activeMembers.length > 1) {
        activeMembers.sort((a, b) {
          final aName = a.name.toLowerCase();
          final bName = b.name.toLowerCase();
          return aName.compareTo(bName);
        });
      }
    } catch (e) {
      debugPrint('Sort error (project details): $e');
    }

    if (activeMembers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active team members available to assign.')),
      );
      return;
    }

    String selectedUserId = _quickWorkerId != null && activeMembers.any((u) => u.id == _quickWorkerId)
        ? _quickWorkerId!
        : activeMembers.first.id;
    String selectedGroupId = _selectedGroupIds.isNotEmpty &&
            availableGroups.any((g) => g.id == _selectedGroupIds.first)
        ? _selectedGroupIds.first
        : availableGroups.first.id;

    final assigned = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Assign Existing Team Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedGroupId,
                decoration: const InputDecoration(
                  labelText: 'Group',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: availableGroups
                    .map((g) => DropdownMenuItem<String>(value: g.id, child: Text(g.name)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setLocalState(() => selectedGroupId = v);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedUserId,
                decoration: const InputDecoration(
                  labelText: 'Team member',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: activeMembers
                    .map(
                      (u) => DropdownMenuItem<String>(
                        value: u.id,
                        child: Text('${u.name} (${u.email})'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setLocalState(() => selectedUserId = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    if (assigned != true) return;

    settingsCtrl.assignWorkerToGroup(
      workspaceKey: widget.workspaceKey,
      userId: selectedUserId,
      groupId: selectedGroupId,
    );
    setState(() => _quickWorkerId = selectedUserId);

    final member = activeMembers.firstWhere((u) => u.id == selectedUserId);
    final group = availableGroups.firstWhere((g) => g.id == selectedGroupId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${member.name} assigned to ${group.name}.')),
    );
  }

  Future<void> _showSendGroupInviteDialog({
    required AuthController authCtrl,
    required AppSettings settings,
    required List<WorkspaceWorkerGroup> availableGroups,
  }) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    InviteRole role = InviteRole.worker;
    String selectedGroupId = _selectedGroupIds.isNotEmpty &&
            availableGroups.any((g) => g.id == _selectedGroupIds.first)
        ? _selectedGroupIds.first
        : availableGroups.first.id;

    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Send Group Invite Link'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This invite assigns the new member directly to the selected group after acceptance.',
                  style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.35),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<InviteRole>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: InviteRole.worker, child: Text('Worker')),
                    DropdownMenuItem(value: InviteRole.manager, child: Text('Manager')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocalState(() => role = v);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedGroupId,
                  decoration: const InputDecoration(
                    labelText: 'Group',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: availableGroups
                      .map((g) => DropdownMenuItem<String>(value: g.id, child: Text(g.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setLocalState(() => selectedGroupId = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Create & Send'),
            ),
          ],
        ),
      ),
    );

    if (send != true) return;

    final invitedName = nameCtrl.text.trim();
    final invitedEmail = emailCtrl.text.trim();
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(invitedEmail);
    if (invitedName.isEmpty || invitedEmail.isEmpty || !validEmail) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid name and email.')),
      );
      return;
    }

    try {
      final link = await authCtrl.createInviteLink(
        invitedName: invitedName,
        invitedEmail: invitedEmail,
        role: role,
        workspaceKey: widget.workspaceKey,
        targetGroupId: selectedGroupId,
      );

      await Clipboard.setData(ClipboardData(text: link));

      var emailQueued = false;
      try {
        await FirebaseEmailQueueService().queueInviteEmail(
          toEmail: invitedEmail,
          invitedName: invitedName,
          inviteLink: link,
          companyName: settings.companyProfile.companyName.trim().isEmpty
              ? 'BW Fire Door Inspection'
              : settings.companyProfile.companyName.trim(),
        );
        emailQueued = true;
      } catch (_) {
        emailQueued = false;
      }

      if (!mounted) return;
      final group = availableGroups.firstWhere((g) => g.id == selectedGroupId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            emailQueued
                ? 'Invite sent for ${group.name}. Link copied to clipboard.'
                : 'Invite link created for ${group.name}. Link copied to clipboard.',
          ),
        ),
      );
    } on AuthFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static const _accent = Color(0xFF1565C0);

  static const _drawingLevelHints = [
    'Ground Floor',
    'Level 1',
    'Level 2',
    'Basement',
    'Other',
  ];

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

  Future<void> _editDrawingMetadata({
    required Survey survey,
    required SurveyController controller,
    required ProjectDrawing drawing,
  }) async {
    final nameCtrl = TextEditingController(text: drawing.name);
    final levelCtrl = TextEditingController(text: drawing.level);
    final descCtrl = TextEditingController(text: drawing.description);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameCtrl,
              decoration: _dec('Drawing name *'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: levelCtrl,
              decoration: _dec('Floor / Level (optional)'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final lvl in _drawingLevelHints)
                  ActionChip(
                    label: Text(lvl),
                    onPressed: () => levelCtrl.text = lvl,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: descCtrl,
              maxLines: 3,
              decoration: _dec('Description (optional)'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  controller.updateProjectDrawingMetadata(
                    surveyId: survey.id,
                    drawingId: drawing.id,
                    name: nameCtrl.text.trim(),
                    level: levelCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                  );
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Drawing Metadata'),
              ),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    levelCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _uploadDrawings(Survey survey, SurveyController controller) async {
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

  Future<ProjectDrawing?> _resolveDrawingBytes({
    required String surveyId,
    required ProjectDrawing drawing,
    required SurveyController controller,
  }) async {
    if (drawing.bytes.isNotEmpty) return drawing;
    if (drawing.cloudDownloadUrl.trim().isEmpty) return drawing;

    try {
      final uri = Uri.parse(drawing.cloudDownloadUrl);
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.isEmpty) {
        throw Exception('Download failed');
      }

      controller.setProjectDrawingBytes(
        surveyId: surveyId,
        drawingId: drawing.id,
        bytes: response.bodyBytes,
      );

      return drawing.copyWith(bytes: response.bodyBytes);
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load drawing file from cloud storage.')),
      );
      return null;
    }
  }

  Future<void> _syncCloudDrawingMetadata({
    required String companyId,
    required Survey survey,
    required SurveyController controller,
  }) async {
    if (_cloudSynced) return;
    _cloudSynced = true;

    final repo = ref.read(companyFileRepositoryProvider);
    try {
      final files = await repo.listEntityFiles(
        companyId: companyId,
        entityType: 'surveyDrawing',
        entityId: survey.id,
      );
      if (!mounted || files.isEmpty) return;

      final stubs = files
          .map(
            (f) => ProjectDrawing(
              id: f.fileId,
              name: _displayNameFromFile(f.originalName),
              fileName: f.originalName,
              mimeType: f.mimeType,
              level: f.tags.isEmpty ? '' : f.tags.first,
              description: '',
              bytes: const [],
              cloudStoragePath: f.storagePath,
              cloudDownloadUrl: f.downloadUrl,
              createdAt: f.createdAt,
            ),
          )
          .toList();

      controller.upsertProjectDrawings(surveyId: survey.id, drawings: stubs);
    } catch (_) {
      // Non-blocking: local drawings still work.
    }
  }

  String _fmtDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }

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

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? headerTrailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: _accent,
                  ),
                ),
              ),
              if (headerTrailing != null) ...[
                const SizedBox(width: 8),
                headerTrailing,
              ],
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Future<void> _openDisclaimerForm({
    required Survey survey,
    required SurveyController controller,
    required String companyId,
    required String moduleType,
  }) async {
    final accepted = await showDisclaimerCaptureSheet(
      context: context,
      ref: ref,
      companyId: companyId,
      projectId: survey.id,
      reportId: survey.id,
      moduleType: moduleType,
      projectName: survey.reportName.trim().isEmpty ? survey.siteName : survey.reportName,
      projectNumber: survey.reference,
      reportReference: survey.registerReference,
    );
    if (accepted == null) return;
    controller.setSurveyDisclaimerRecord(surveyId: survey.id, record: accepted);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = parseInspectionWorkspaceKey(widget.workspaceKey) ?? InspectionWorkspace.fireDoor;
    ref.watch(surveyControllerFamilyProvider(workspace));
    final controller = ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final settingsCtrl = ref.read(settingsControllerProvider.notifier);
    final usersAsync = ref.watch(companyUsersProvider);
    final repo = ref.read(companyFileRepositoryProvider);
    final survey = controller.getById(widget.surveyId);
    final availableGroups = settings.workspaceGroups[widget.workspaceKey] ?? const <WorkspaceWorkerGroup>[];
    final canManageProjectAccess = _canManageProjectAccess(auth);

    if (survey == null) {
      return const Scaffold(
        body: Center(child: Text('Project not found')),
      );
    }

    if (!_loaded) {
      _loaded = true;
      _reportDate = survey.reportDate;
      _reportNameController.text = survey.reportName;
      _referenceController.text = survey.reference;
      _addressLine1Controller.text = survey.addressLine1;
      _addressLine2Controller.text = survey.addressLine2;
      _cityTownController.text = survey.cityTown;
      _postCodeController.text = survey.postCode;
      _clientNameController.text = survey.clientName;
      _clientEmailController.text = survey.clientEmail;
      _clientPhoneController.text = survey.clientPhone;
      _selectedGroupIds
        ..clear()
        ..addAll(survey.assignedGroupIds);
    }

    final companyId = auth.companyId;
    final declarationModuleType = widget.moduleKey == 'preinstall'
      ? 'pre-installation'
      : inspectionWorkspaceSlug(survey.workspace);

    if (companyId != null && companyId.isNotEmpty) {
      _syncCloudDrawingMetadata(
        companyId: companyId,
        survey: survey,
        controller: controller,
      );
    }

    final isFireStopping = survey.type == SurveyType.fireStopping;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(isFireStopping ? 'Project Details' : 'Project Details'),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: widget.workspaceKey),
        actions: [
          IconButton(
            onPressed: survey.projectDrawings.isEmpty
                ? null
                : () => ProjectDrawingAccess.showDrawingPicker(context: context, survey: survey),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'View Drawing',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _sectionCard(
              title: 'Report / Project Information',
              icon: Icons.description_outlined,
              headerTrailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmtDateCompact(_reportDate),
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
                        initialDate: _reportDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) return;
                      setState(() => _reportDate = picked);
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: const Size(0, 0),
                    ),
                    child: const Text('Change'),
                  ),
                ],
              ),
              children: [
                TextFormField(
                  controller: _reportNameController,
                  decoration: _dec('Project Name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _referenceController,
                  decoration: _dec('Project Number'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Reports use the active company profile. If no custom company logo has been uploaded, the default app logo is used automatically.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.35),
                ),
              ],
            ),

            const SizedBox(height: 16),

            _sectionCard(
              title: 'Site Address',
              icon: Icons.location_on_outlined,
              children: [
                TextFormField(
                  controller: _addressLine1Controller,
                  decoration: _dec('Site Address Line 1'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressLine2Controller,
                  decoration: _dec('Site Address Line 2'),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _cityTownController,
                        decoration: _dec('City / Town'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _postCodeController,
                        decoration: _dec('Post Code'),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            _sectionCard(
              title: 'Client',
              icon: Icons.business_outlined,
              children: [
                TextFormField(
                  controller: _clientNameController,
                  decoration: _dec('Client Name'),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 760;
                    final fieldWidth = isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: TextFormField(
                            controller: _clientEmailController,
                            decoration: _dec('Client Email'),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextFormField(
                            controller: _clientPhoneController,
                            decoration: _dec('Client Phone'),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            _sectionCard(
              title: 'Worker / Access Groups',
              icon: Icons.groups_2_outlined,
              children: [
                Text(
                  'Assign one or more workspace groups only if this project should be restricted. If no group is selected, access stays open to all team members.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 8),
                Text(
                  availableGroups.isEmpty
                      ? 'No workspace groups created yet. Access remains open to all team members.'
                      : _selectedGroupIds.isEmpty
                          ? 'No group assigned.'
                          : availableGroups.where((g) => _selectedGroupIds.contains(g.id)).map((g) => g.name).join(', '),
                  style: TextStyle(
                    fontSize: 13,
                    color: _selectedGroupIds.isEmpty ? Colors.grey.shade600 : Colors.black87,
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
                          label: Text(group.name, style: const TextStyle(fontSize: 12)),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canManageProjectAccess)
                      TextButton.icon(
                        onPressed: () => _quickCreateGroup(
                          settingsCtrl: settingsCtrl,
                          workspaceKey: widget.workspaceKey,
                        ),
                        icon: const Icon(Icons.add, size: 15),
                        label: const Text('Create Group'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    if (canManageProjectAccess && availableGroups.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _showGroupInviteActions(
                          authCtrl: ref.read(authControllerProvider.notifier),
                          settingsCtrl: settingsCtrl,
                          settings: settings,
                          availableGroups: availableGroups,
                          users: usersAsync.valueOrNull ?? const <AppUser>[],
                        ),
                        icon: const Icon(Icons.person_add_alt_1_outlined, size: 15),
                        label: const Text('Invite to Group'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            _sectionCard(
              title: 'Project Drawings / Plans (DRW)',
              icon: Icons.map_outlined,
              children: [
                Text(
                  'Upload PDF, JPG or PNG plans to support shared navigation and drawing pins across the project.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 8),
                Text(
                  survey.projectDrawings.isEmpty
                      ? 'No drawings uploaded yet. You can continue without one.'
                      : '${survey.projectDrawings.length} drawing(s) available for this project.',
                  style: TextStyle(
                    fontSize: 13,
                    color: survey.projectDrawings.isEmpty ? Colors.grey.shade600 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _uploadDrawings(survey, controller),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload Drawing'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: survey.projectDrawings.isEmpty
                            ? null
                            : () async {
                                final result = await ProjectDrawingAccess.showDrawingPicker(
                                  context: context,
                                  survey: survey,
                                  beforeOpen: (drawing) => _resolveDrawingBytes(
                                    surveyId: survey.id,
                                    drawing: drawing,
                                    controller: controller,
                                  ),
                                );
                                if (!context.mounted || result?.addDefect != true) return;
                                context.go('/workspace/${inspectionWorkspaceSlug(survey.workspace)}/inspection/projects/${widget.surveyId}/doors');
                              },
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('View Drawing'),
                      ),
                    ),
                  ],
                ),
                if (survey.projectDrawings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final drawing in survey.projectDrawings)
                    Card(
                      elevation: 0,
                      color: const Color(0xFFF8FAFD),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: ListTile(
                        leading: Icon(
                          drawing.mimeType.contains('pdf') ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                          color: _accent,
                        ),
                        title: Text(drawing.name.trim().isEmpty ? drawing.fileName : drawing.name),
                        subtitle: Text(
                          [
                            'Level: ${drawing.level.trim().isEmpty ? 'Other' : drawing.level.trim()}',
                            if (drawing.description.trim().isNotEmpty) drawing.description.trim(),
                            'Uploaded: ${_fmtDate(drawing.createdAt)}',
                          ].join(' | '),
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            IconButton(
                              tooltip: 'Edit metadata',
                              onPressed: () => _editDrawingMetadata(survey: survey, controller: controller, drawing: drawing),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Remove drawing',
                              onPressed: () async {
                                if (companyId != null && companyId.isNotEmpty) {
                                  try {
                                    await repo.deleteFile(companyId: companyId, fileId: drawing.id);
                                  } catch (_) {}
                                }
                                controller.removeProjectDrawing(surveyId: survey.id, drawingId: drawing.id);
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        onTap: () async {
                          final resolved = await _resolveDrawingBytes(
                            surveyId: survey.id,
                            drawing: drawing,
                            controller: controller,
                          );
                          if (!context.mounted || resolved == null) return;
                          final result = await ProjectDrawingAccess.showDrawingViewer(
                            context: context,
                            surveyId: survey.id,
                            drawingId: resolved.id,
                            fallbackTitle: resolved.fileName,
                            drawingOverride: resolved,
                            workspaceOverride: survey.workspace,
                          );
                          if (!context.mounted || result?.addDefect != true) return;
                          context.go('/workspace/${inspectionWorkspaceSlug(survey.workspace)}/inspection/projects/${widget.surveyId}/doors');
                        },
                      ),
                    ),
                ],
              ],
            ),

            if (companyId != null && companyId.isNotEmpty) ...[
              const SizedBox(height: 16),
              DisclaimerAcceptanceSection(
                companyId: companyId,
                reportId: survey.id,
                moduleType: declarationModuleType,
                onOpenDisclaimerForm: () => _openDisclaimerForm(
                  survey: survey,
                  controller: controller,
                  companyId: companyId,
                  moduleType: declarationModuleType,
                ),
              ),
            ],

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                  isFireStopping ? 'Save Project Details' : 'Save & Continue',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                onPressed: () async {
                  if (!(_formKey.currentState?.validate() ?? false)) return;

                  controller.updateSurveyMeta(
                    surveyId: widget.surveyId,
                    reportDate: _reportDate,
                    reportName: _reportNameController.text.trim(),
                    addressLine1: _addressLine1Controller.text.trim(),
                    addressLine2: _addressLine2Controller.text.trim(),
                    cityTown: _cityTownController.text.trim(),
                    postCode: _postCodeController.text.trim(),
                    clientName: _clientNameController.text.trim(),
                    clientEmail: _clientEmailController.text.trim(),
                    clientPhone: _clientPhoneController.text.trim(),
                    reference: _referenceController.text.trim(),
                    assignedGroupIds: _selectedGroupIds.toList(),
                  );

                  if (isFireStopping) {
                    final next = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Project Details Saved'),
                        content: const Text('Choose your next step.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, 'back'),
                            child: const Text('Back to Projects'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, 'inspection'),
                            child: const Text('Go to Fire Stopping Inspection'),
                          ),
                        ],
                      ),
                    );
                    if (!context.mounted) return;
                    if (next == 'back') {
                      context.go('/workspace/${widget.workspaceKey}/inspection/projects');
                      return;
                    }
                    if (next != 'inspection') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Project Details saved.')),
                      );
                      return;
                    }
                  }

                  switch (widget.moduleKey) {
                    case 'inspection':
                    case 'fire-door':
                    case 'fire-stopping':
                    case 'snagging':
                      context.go('/workspace/${inspectionWorkspaceSlug(survey.workspace)}/inspection/projects/${widget.surveyId}/doors');
                      break;
                    case 'preinstall':
                      context.go('/workspace/${widget.workspaceKey}/preinstall/${widget.surveyId}/items');
                      break;
                    case 'installation':
                      context.go('/workspace/${widget.workspaceKey}/installation/${widget.surveyId}/items');
                      break;
                    case 'remedials':
                      context.go('/workspace/${widget.workspaceKey}/remedials/${widget.surveyId}/doors');
                      break;
                    default:
                      context.go('/workspace/${inspectionWorkspaceSlug(survey.workspace)}/inspection/projects/${widget.surveyId}/doors');
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}