// DEPRECATED: Legacy shared survey inspection flow.
// Active runtime flow uses workspace module routes under /workspace/*/inspection/*.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../domain/inspection_definitions.dart';
import '../domain/models.dart';
import '../state/survey_controller.dart';
import 'project_drawing_viewer.dart';

class DoorListScreen extends ConsumerStatefulWidget {
  final String surveyId;

  const DoorListScreen({
    super.key,
    required this.surveyId,
  });

  @override
  ConsumerState<DoorListScreen> createState() => _DoorListScreenState();
}

class _DoorListScreenState extends ConsumerState<DoorListScreen> {
  @override
  Widget build(BuildContext context) {
    ref.watch(surveyControllerProvider);
    final controller = ref.read(surveyControllerProvider.notifier);
    final survey = controller.getById(widget.surveyId);

    if (survey == null) {
      return const Scaffold(
        body: Center(child: Text('Project not found')),
      );
    }

    final doors = survey.doors.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(_projectTitle(survey)),
        actions: [
          IconButton(
            tooltip: 'View Drawing',
            onPressed: () => ProjectDrawingAccess.showDrawingPicker(context: context, survey: survey),
            icon: const Icon(Icons.map_outlined),
          ),
          IconButton(
            tooltip: 'Export',
            onPressed: () => _showExportPlaceholder(context),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/modules/inspection/projects'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDoor(context, controller),
        icon: const Icon(Icons.add),
        label: const Text('Add Door'),
      ),
      body: doors.isEmpty
          ? _EmptyDoorState(
              onAdd: () => _addDoor(context, controller),
              onExport: () => _showExportPlaceholder(context),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
              itemCount: doors.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _ProjectSummaryCard(
                    survey: survey,
                    doorCount: doors.length,
                    onExport: () => _showExportPlaceholder(context),
                  );
                }

                final door = doors[index - 1];
                return _DoorSummaryCard(
                  door: door,
                  onOpen: () => _openDoor(context, door.id),
                  onDelete: () => _deleteDoor(context, controller, door),
                );
              },
            ),
    );
  }

  String _projectTitle(Survey survey) {
    final reportName = survey.reportName.trim();
    final siteName = survey.siteName.trim();

    if (reportName.isNotEmpty) return '$reportName - Doors';
    if (siteName.isNotEmpty) return '$siteName - Doors';
    return 'Doors';
    }

  void _addDoor(BuildContext context, SurveyController controller) {
    controller.addDoor(widget.surveyId);

    final updatedSurvey = controller.getById(widget.surveyId);
    if (updatedSurvey == null || updatedSurvey.doors.isEmpty) return;

    final createdDoor = updatedSurvey.doors.last;
    context.push('/surveys/${widget.surveyId}/doors/${createdDoor.id}');
  }

  void _openDoor(BuildContext context, String doorId) {
    context.push('/surveys/${widget.surveyId}/doors/$doorId');
  }

  Future<void> _deleteDoor(
    BuildContext context,
    SurveyController controller,
    Door door,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete door record'),
        content: Text(
          'Delete "${door.doorIdTag.trim().isEmpty ? 'Untitled door' : door.doorIdTag.trim()}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      controller.deleteDoor(
        surveyId: widget.surveyId,
        doorId: door.id,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Door deleted')),
      );
    } on StateError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  void _showExportPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PDF export will be added next.'),
      ),
    );
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  final Survey survey;
  final int doorCount;
  final VoidCallback onExport;

  const _ProjectSummaryCard({
    required this.survey,
    required this.doorCount,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final reportName = survey.reportName.trim();
    final siteName = survey.siteName.trim();
    final address = survey.siteAddress.trim().isNotEmpty
        ? survey.siteAddress.trim()
        : _formatAddress(survey);

    final projectName = reportName.isNotEmpty
        ? reportName
        : (siteName.isNotEmpty ? siteName : 'Project');

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
            Text(
              projectName,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  address,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(label: 'Doors', value: '$doorCount'),
                _InfoPill(label: 'Client', value: _safeValue(survey.clientName)),
                _InfoPill(
                  label: 'Completed by',
                  value: _safeValue(survey.reportCompletedBy),
                ),
                _InfoPill(label: 'Project Number', value: _safeValue(survey.reference)),
                _InfoPill(label: 'Type', value: _surveyTypeLabel(survey.type)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Export / Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatAddress(Survey survey) {
    final parts = <String>[
      if (survey.addressLine1.trim().isNotEmpty) survey.addressLine1.trim(),
      if (survey.addressLine2.trim().isNotEmpty) survey.addressLine2.trim(),
      if (survey.cityTown.trim().isNotEmpty) survey.cityTown.trim(),
      if (survey.postCode.trim().isNotEmpty) survey.postCode.trim(),
    ];
    return parts.join(', ');
  }

  static String _safeValue(String value) {
    final v = value.trim();
    return v.isEmpty ? '-' : v;
  }

  static String _surveyTypeLabel(SurveyType type) {
    switch (type) {
      case SurveyType.survey:
        return 'Fire Door Inspection';
      case SurveyType.fireStopping:
        return 'Fire Stopping Inspection';
      case SurveyType.snagging:
        return 'Snagging Inspection';
      case SurveyType.maintenance:
        return 'Remedial Works';
      case SurveyType.installation:
        return 'Installation & Handover';
      case SurveyType.installationSurvey:
        return 'Pre-Installation Survey';
    }
  }
}

class _DoorSummaryCard extends StatelessWidget {
  final Door door;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _DoorSummaryCard({
    required this.door,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = door.doorIdTag.trim().isEmpty
        ? 'Door No: ${door.number}'
        : 'Door No: ${door.doorIdTag.trim()}';

    final defects = _defectCount(door);
    final criticals = _criticalDefectCount(door);
    final compliance = _compliancePercent(door);
    final status = _status(door);
    final statusColor = _statusColor(status);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ─────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      border:
                          Border.all(color: statusColor.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Info pills row ─────────────────────────────────
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _InfoPill(
                    label: 'Floor',
                    value: door.floor.trim().isEmpty
                        ? '-'
                        : door.floor.trim(),
                  ),
                  _InfoPill(
                    label: 'Location',
                    value: door.area.trim().isEmpty
                        ? '-'
                        : door.area.trim(),
                  ),
                  _InfoPill(
                    label: 'Rating',
                    value: _fireRatingLabel(door.fireRating),
                  ),
                  _InfoPill(
                    label: 'Compliance',
                    value: '$compliance%',
                    color: compliance >= 80
                        ? Colors.green
                        : (compliance > 0 ? Colors.orange : Colors.blueGrey),
                  ),
                  _InfoPill(
                    label: 'Defects',
                    value: '$defects',
                    color: defects == 0 ? Colors.green : Colors.red,
                  ),
                  _InfoPill(label: 'Photos', value: '${_photoCount(door)}'),
                  _InfoPill(
                    label: 'Inspection',
                    value: '${door.inspectionDate.day.toString().padLeft(2, '0')}/${door.inspectionDate.month.toString().padLeft(2, '0')}/${door.inspectionDate.year}',
                  ),
                  if (criticals > 0)
                    _InfoPill(
                      label: 'Critical',
                      value: '$criticals',
                      color: const Color(0xFF8B0000),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Action buttons ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Open / Edit'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onDelete,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    child:
                        const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _defectCount(Door d) {
    var count = 0;
    for (final r in d.inspectionResults.values) {
      if (r.outcome == InspectionOutcome.fail ||
          r.outcome == InspectionOutcome.criticalFail) {
        count++;
      }
    }
    return count;
  }

  int _criticalDefectCount(Door d) {
    return d.inspectionResults.values
        .where((r) => r.outcome == InspectionOutcome.criticalFail)
        .length;
  }

  int _photoCount(Door d) {
    var count = d.doorPhotos.length;
    for (final r in d.inspectionResults.values) {
      count += r.photos.length;
    }
    return count;
  }

  int _compliancePercent(Door d) {
    final outcomes = d.inspectionResults.values
        .map((r) => r.outcome)
        .where((o) =>
            o != InspectionOutcome.notAnswered &&
            o != InspectionOutcome.notApplicable)
        .toList();
    if (outcomes.isEmpty) return 0;
    final pass =
        outcomes.where((o) => o == InspectionOutcome.pass).length;
    return ((pass / outcomes.length) * 100).round();
  }

  String _status(Door d) {
    var totalAnswered = 0;
    var totalChecks = 0;

    for (final c in inspectionChecks) {
      totalChecks++;
      final r = d.inspectionResults[c.id.name];
      if (r != null && r.outcome != InspectionOutcome.notAnswered) {
        totalAnswered++;
      }
    }

    if (totalAnswered == 0) return 'Not started';
    if (totalAnswered >= totalChecks) return 'Complete';
    return 'In progress';
  }

  Color _statusColor(String s) {
    if (s == 'Complete') return Colors.green;
    if (s == 'In progress') return Colors.orange;
    return Colors.blueGrey;
  }

  String _fireRatingLabel(FireRating r) {
    switch (r) {
      case FireRating.notAFireDoor:
        return 'Not fire door';
      case FireRating.fd30:
        return 'FD30';
      case FireRating.fd30s:
        return 'FD30S';
      case FireRating.fd60:
        return 'FD60';
      case FireRating.fd60s:
        return 'FD60S';
      case FireRating.fd90:
        return 'FD90';
      case FireRating.fd90s:
        return 'FD90S';
      case FireRating.fd120:
        return 'FD120';
      case FireRating.fd120s:
        return 'FD120S';
      case FireRating.unknown:
        return 'Not recorded';
    }
  }

}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _InfoPill({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c != null ? c.withValues(alpha: 0.10) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: c != null ? c.withValues(alpha: 0.35) : Colors.grey.shade300,
        ),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: c,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyDoorState extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onExport;

  const _EmptyDoorState({
    required this.onAdd,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.meeting_room_outlined, size: 40),
                  const SizedBox(height: 10),
                  const Text(
                    'No doors added yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add your first door record to start inspection and reporting.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onAdd,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Door'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onExport,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Export / Share'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}