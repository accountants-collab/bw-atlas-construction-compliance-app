import 'dart:typed_data';
import 'dart:async';

// DEPRECATED: Legacy shared survey inspection flow.
// Active runtime flow uses workspace module routes under /workspace/*/inspection/*.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/selection_controls.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../domain/inspection_definitions.dart';
import '../domain/models.dart';
import '../state/survey_controller.dart';
import 'project_drawing_viewer.dart';

class DoorInspectionScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final String doorId;
  final String workspaceKey;
  final String routePrefix;

  const DoorInspectionScreen({
    super.key,
    required this.surveyId,
    required this.doorId,
    this.workspaceKey = 'fire-door',
    this.routePrefix = '/surveys',
  });

  @override
  ConsumerState<DoorInspectionScreen> createState() => _DoorInspectionScreenState();
}

class _DoorInspectionScreenState extends ConsumerState<DoorInspectionScreen> {
  final _picker = ImagePicker();
  final Map<String, Timer> _inputDebounceTimers = <String, Timer>{};

  static const Duration _textUpdateDebounce = Duration(milliseconds: 300);

  void _debounceInput({
    required String key,
    required VoidCallback action,
    Duration delay = _textUpdateDebounce,
  }) {
    _inputDebounceTimers[key]?.cancel();
    _inputDebounceTimers[key] = Timer(delay, action);
  }

  @override
  void dispose() {
    for (final timer in _inputDebounceTimers.values) {
      timer.cancel();
    }
    _inputDebounceTimers.clear();
    super.dispose();
  }

  Future<List<PhotoAttachment>> _pickPhotos() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (res == null) return [];

    final photos = <PhotoAttachment>[];
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;

      photos.add(
        PhotoAttachment(
          fileName: f.name,
          mimeType: 'image/*',
          bytes: bytes,
        ),
      );
    }
    return photos;
  }

  Future<void> _showDrawing(BuildContext ctx, Survey survey) async {
    await ProjectDrawingAccess.showDrawingPicker(
      context: ctx,
      survey: survey,
    );
  }

  Future<PhotoAttachment?> _takePhoto() async {
    final shot = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (shot == null) return null;
    final bytes = await shot.readAsBytes();
    return PhotoAttachment(
      fileName: shot.name.isEmpty ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg' : shot.name,
      mimeType: 'image/jpeg',
      bytes: bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final surveyId = widget.surveyId;
    final doorId = widget.doorId;
    final workspace = parseInspectionWorkspaceKey(widget.workspaceKey) ?? InspectionWorkspace.fireDoor;
    ref.watch(surveyControllerFamilyProvider(workspace));
    final controller = ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final survey = controller.getById(surveyId);
    final door = survey?.doors.where((d) => d.id == doorId).toList().firstOrNull;

    if (survey == null || door == null) {
      return const Scaffold(body: Center(child: Text('Door not found')));
    }

    final bySection = checksBySection();

    InspectionCheckResult resultFor(InspectionCheckId id) {
      final existing = door.inspectionResults[id.name];
      if (existing != null) return existing;

      final def = checkDef(id);
      return InspectionCheckResult(
        outcome: InspectionOutcome.notAnswered,
        recommendedAction: def.recommendedAction,
        comment: '',
        photos: const [],
      );
    }

    // -------- Summary --------
    final allChecks = inspectionChecks;
    final completedCount = allChecks.where((c) => resultFor(c.id).outcome != InspectionOutcome.notAnswered).length;
    final totalChecks = allChecks.length;

    final applicableOutcomes = allChecks
        .map((c) => resultFor(c.id).outcome)
        .where((o) => o != InspectionOutcome.notAnswered && o != InspectionOutcome.notApplicable)
        .toList();

    final passCount = applicableOutcomes.where((o) => o == InspectionOutcome.pass).length;
    final compliancePercent = applicableOutcomes.isEmpty ? 0 : ((passCount / applicableOutcomes.length) * 100).round();

    final defectCount = allChecks
        .map((c) => resultFor(c.id).outcome)
        .where((o) => o == InspectionOutcome.fail || o == InspectionOutcome.criticalFail)
        .length;

    final criticalFailCount = allChecks.map((c) => resultFor(c.id).outcome).where((o) => o == InspectionOutcome.criticalFail).length;

    bool allAnswered = completedCount == totalChecks;

    bool missingRequiredPhotos() {
      for (final c in allChecks) {
        final r = resultFor(c.id);
        if (r.outcome == InspectionOutcome.fail || r.outcome == InspectionOutcome.criticalFail) {
          if (r.photos.isEmpty) return true;
        }
      }
      return false;
    }

    Future<void> showBlockingDialog(String title, String body) async {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    }

    Color outcomeColor(InspectionOutcome o) {
      switch (o) {
        case InspectionOutcome.pass:
          return Colors.green;
        case InspectionOutcome.advisory:
          return Colors.amber;
        case InspectionOutcome.fail:
          return Colors.red;
        case InspectionOutcome.criticalFail:
          return const Color(0xFF8B0000);
        case InspectionOutcome.notApplicable:
          return Colors.grey;
        case InspectionOutcome.notAnswered:
          return Colors.black45;
      }
    }

    Widget outcomeChip({
      required InspectionCheckId checkId,
      required InspectionOutcome value,
      required InspectionOutcome selected,
    }) {
      final isSelected = selected == value;
      final color = outcomeColor(value);

      return AppChoicePill(
        label: inspectionOutcomeLabel(value),
        selected: isSelected,
        selectedColor: color,
        onPressed: () {
          controller.setInspectionOutcome(
            surveyId: surveyId,
            doorId: doorId,
            checkId: checkId,
            outcome: value,
          );
        },
      );
    }

    String artPreview(InspectionCheckId id, InspectionOutcome o) {
      final art = autoArtCodeForOutcome(checkId: id, outcome: o);
      if (art == null) return '-';
      return 'ART${art.toString().padLeft(2, '0')}';
    }

    Widget checkRow(InspectionCheckDefinition def) {
      final r = resultFor(def.id);
      final o = r.outcome;

      final showDetails = o != InspectionOutcome.notAnswered && o != InspectionOutcome.pass;
      final needsPhoto = o == InspectionOutcome.fail || o == InspectionOutcome.criticalFail;
      final showArt = o == InspectionOutcome.fail || o == InspectionOutcome.criticalFail;

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(def.title, style: const TextStyle(fontWeight: FontWeight.w800))),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    decoration: BoxDecoration(
                      color: outcomeColor(o).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: outcomeColor(o).withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      o == InspectionOutcome.notAnswered ? 'Not started' : inspectionOutcomeLabel(o),
                      style: TextStyle(fontWeight: FontWeight.w800, color: outcomeColor(o), fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(def.helperText, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final allowed in def.allowedOutcomes)
                    outcomeChip(checkId: def.id, value: allowed, selected: o),
                ],
              ),

              if (showArt) ...[
                const SizedBox(height: 12),
                Text(
                  'Auto ART: ${artPreview(def.id, o)}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: outcomeColor(o)),
                ),
              ],

              if (showDetails) ...[
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: r.comment,
                  onChanged: (v) => _debounceInput(
                    key: 'comment_${def.id.name}',
                    action: () => controller.setInspectionComment(
                      surveyId: surveyId,
                      doorId: doorId,
                      checkId: def.id,
                      comment: v,
                    ),
                  ),
                  onFieldSubmitted: (v) => controller.setInspectionComment(
                    surveyId: surveyId,
                    doorId: doorId,
                    checkId: def.id,
                    comment: v,
                  ),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Inspector comment / notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: r.recommendedAction,
                  onChanged: (v) => _debounceInput(
                    key: 'recommended_${def.id.name}',
                    action: () => controller.setInspectionRecommendedAction(
                      surveyId: surveyId,
                      doorId: doorId,
                      checkId: def.id,
                      recommendedAction: v,
                    ),
                  ),
                  onFieldSubmitted: (v) => controller.setInspectionRecommendedAction(
                    surveyId: surveyId,
                    doorId: doorId,
                    checkId: def.id,
                    recommendedAction: v,
                  ),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Recommended action',
                    border: OutlineInputBorder(),
                  ),
                ),

                if (def.id == InspectionCheckId.doorGapsIncorrect &&
                    (o == InspectionOutcome.fail || o == InspectionOutcome.criticalFail)) ...[
                  const SizedBox(height: 10),
                  const Text('Gap measurements (mm)', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _GapGrid(
                    top: r.gapTopMm,
                    bottom: r.gapBottomMm,
                    left: r.gapLeftMm,
                    right: r.gapRightMm,
                    onChanged: (top, bottom, left, right) {
                      _debounceInput(
                        key: 'gaps_${def.id.name}',
                        action: () => controller.setInspectionGaps(
                          surveyId: surveyId,
                          doorId: doorId,
                          checkId: def.id,
                          topMm: top,
                          bottomMm: bottom,
                          leftMm: left,
                          rightMm: right,
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 10),
                // Required-photo warning
                if (needsPhoto && r.photos.isEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF5350)),
                    ),
                    child: const Text(
                      'At least 1 photo required for Fail / Critical Fail.',
                      style: TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w800),
                    ),
                  ),
                // Existing photo thumbnails with per-photo delete
                if (r.photos.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int pi = 0; pi < r.photos.length; pi++)
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  Uint8List.fromList(r.photos[pi].bytes),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () {
                                    final updated = [...r.photos];
                                    updated.removeAt(pi);
                                    controller.setInspectionPhotos(
                                      surveyId: surveyId,
                                      doorId: doorId,
                                      checkId: def.id,
                                      photos: updated,
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    padding: const EdgeInsets.all(3),
                                    child: const Icon(Icons.close, color: Colors.white, size: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                // Photo action buttons: Take Photo (camera) + Upload Photo
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final photo = await _takePhoto();
                          if (photo == null) return;
                          controller.addInspectionPhotos(
                            surveyId: surveyId,
                            doorId: doorId,
                            checkId: def.id,
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
                        onPressed: () async {
                          final picked = await _pickPhotos();
                          if (picked.isEmpty) return;
                          controller.addInspectionPhotos(
                            surveyId: surveyId,
                            doorId: doorId,
                            checkId: def.id,
                            photos: picked,
                          );
                        },
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload Photo'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget sectionCard(InspectionSection section, List<InspectionCheckDefinition> checks) {
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
              Text(inspectionSectionTitle(section), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(inspectionSectionHelper(section), style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              for (final c in checks) ...[
                checkRow(c),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: widget.workspaceKey),
        title: Text(
          door.doorIdTag.trim().isEmpty
              ? 'Door No: ${door.number} – Inspection'
              : 'Door No: ${door.doorIdTag.trim()} – Inspection',
        ),
        actions: [
          IconButton(
            tooltip: 'View Project Drawing',
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              // ignore: use_build_context_synchronously
              _showDrawing(context, survey);
            },
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/modules/inspection/projects'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                  const Text('Inspection summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MetricChip(label: 'Completed', value: '$completedCount/$totalChecks', color: Colors.blueGrey),
                      _MetricChip(
                        label: 'Compliance',
                        value: '$compliancePercent%',
                        color: completedCount == 0
                            ? Colors.blueGrey
                            : (compliancePercent >= 80 ? Colors.green : Colors.orange),
                      ),
                      _MetricChip(
                        label: 'Defects',
                        value: defectCount.toString(),
                        color: completedCount == 0
                            ? Colors.blueGrey
                            : (defectCount == 0 ? Colors.green : Colors.red),
                      ),
                      _MetricChip(
                        label: 'Critical',
                        value: criticalFailCount.toString(),
                        color: completedCount == 0
                            ? Colors.blueGrey
                            : (criticalFailCount == 0 ? Colors.green : const Color(0xFF8B0000)),
                      ),
                    ],
                  ),
                  if (!allAnswered || missingRequiredPhotos()) ...[
                    const SizedBox(height: 10),
                    Text(
                      !allAnswered
                          ? 'Complete all checks before leaving.'
                          : 'Add required photos for all Fail/Critical Fail items before leaving.',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          for (final entry in bySection.entries) ...[
            sectionCard(entry.key, entry.value),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (!allAnswered) {
                      await showBlockingDialog(
                        'Incomplete inspection',
                        'Please answer all inspection checks before leaving this screen.',
                      );
                      return;
                    }
                    if (missingRequiredPhotos()) {
                      await showBlockingDialog(
                        'Photos required',
                        'At least 1 photo is required for every Fail/Critical Fail item.',
                      );
                      return;
                    }
                    context.go('${widget.routePrefix}/$surveyId/doors/$doorId');
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: Text(
                    door.doorIdTag.trim().isEmpty
                        ? 'Back to Door Details'
                        : 'Back to Door No: ${door.doorIdTag.trim()}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontWeight: FontWeight.w900, color: color),
      ),
    );
  }
}

class _GapGrid extends StatelessWidget {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  final void Function(double? top, double? bottom, double? left, double? right) onChanged;

  const _GapGrid({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
    required this.onChanged,
  });

  double? _parse(String v) {
    final t = v.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        );

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: top?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: dec('Top (mm)'),
                onChanged: (v) => onChanged(_parse(v), bottom, left, right),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: bottom?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: dec('Bottom (mm)'),
                onChanged: (v) => onChanged(top, _parse(v), left, right),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: left?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: dec('Left (mm)'),
                onChanged: (v) => onChanged(top, bottom, _parse(v), right),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: right?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: dec('Right (mm)'),
                onChanged: (v) => onChanged(top, bottom, left, _parse(v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}