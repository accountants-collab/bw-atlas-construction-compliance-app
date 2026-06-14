import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/app_visual_system.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../domain/snagging_models.dart';
import '../state/snagging_module_controller.dart';

class SnaggingVerificationScreen extends ConsumerWidget {
  const SnaggingVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(snaggingModuleControllerProvider);
    final controller = ref.read(snaggingModuleControllerProvider.notifier);

    final items = <({SnaggingProject project, SnaggingIssue issue})>[];
    for (final project in state.projects) {
      for (final issue in project.issues) {
        if (issue.status == SnaggingStatus.awaitingVerification &&
            issue.completionPhotoBase64.isNotEmpty) {
          items.add((project: project, issue: issue));
        }
      }
    }

    final content = ListView(
      padding: const EdgeInsets.all(AppSpace.m),
      children: [
        const Text(
          'Completed snags with uploaded photos appear here for manager review.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpace.s),
        if (items.isEmpty)
          const AppEmptyState(
            icon: Icons.verified_outlined,
            title: 'No items awaiting verification',
            message:
                'When workers complete snags and upload completion photos, they will show here.',
          )
        else
          ...items.map(
            (entry) => Card(
              child: ExpansionTile(
                leading: _PriorityDot(priority: entry.issue.priority),
                title: Text(
                  'Snag #${entry.issue.snagNumber} \u2014 '
                  '${entry.project.name.isEmpty ? 'Project' : entry.project.name}',
                ),
                subtitle: Text(
                  entry.issue.assignedToName.isEmpty
                      ? 'Unassigned - Status: For Approval'
                      : '${entry.issue.assignedToName} - Status: For Approval',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (entry.issue.location.isNotEmpty)
                    _kv('Location', entry.issue.location),
                  Row(
                    children: [
                      const Text('Priority: ',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      _priorityChip(entry.issue.priority),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _kv('Programme Impact',
                      _impactLabel(entry.issue.programmeImpact)),
                  if (entry.issue.description.isNotEmpty)
                    _kv('Description', entry.issue.description),
                  if (entry.issue.reference.isNotEmpty)
                    _kv('Reference / PIN', entry.issue.reference),
                  _kv('Date & Time', _formatDateTime(entry.issue.dateTime)),
                  if (entry.issue.workerNotes.isNotEmpty)
                    _kv('Worker Notes', entry.issue.workerNotes),
                  const SizedBox(height: 8),
                  _photoBlock(
                      'Inspector Photos', entry.issue.originalPhotoBase64),
                  const SizedBox(height: 8),
                  _photoBlock(
                      'Completion Photos', entry.issue.completionPhotoBase64),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            controller.updateIssue(
                              projectId: entry.project.id,
                              issueId: entry.issue.id,
                              update: (i) =>
                                  i.copyWith(status: SnaggingStatus.approved),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Snag #${entry.issue.snagNumber} approved.')),
                            );
                          },
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.shade700),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Approve'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            controller.updateIssue(
                              projectId: entry.project.id,
                              issueId: entry.issue.id,
                              update: (i) =>
                                  i.copyWith(status: SnaggingStatus.returned),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Snag #${entry.issue.snagNumber} rejected and returned for rework.')),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700),
                          icon: const Icon(Icons.undo_outlined),
                          label: const Text('Reject / Return'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: '/workspace/snagging/verification/projects',
        title: 'Snagging Verification',
        workflowLabel: 'Snagging Verification',
        drawerRoute: '/workspace/snagging/verification/projects',
        workspaceKey: 'snagging',
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Snagging Verification'),
        bottom: const WorkspaceSwitchCardsBar(currentWorkspaceKey: 'snagging'),
      ),
      body: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Priority helpers
// ---------------------------------------------------------------------------

Color _priorityColor(SnagPriority p) {
  switch (p) {
    case SnagPriority.low:
      return const Color(0xFFFBC02D);
    case SnagPriority.medium:
      return const Color(0xFFF57C00);
    case SnagPriority.high:
      return const Color(0xFFD32F2F);
  }
}

String _priorityText(SnagPriority p) {
  switch (p) {
    case SnagPriority.low:
      return 'Low';
    case SnagPriority.medium:
      return 'Medium';
    case SnagPriority.high:
      return 'High';
  }
}

Widget _priorityChip(SnagPriority p) {
  final color = _priorityColor(p);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      _priorityText(p),
      style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
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
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Widget _kv(String label, String value) {
  final safe = value.trim().isEmpty ? '-' : value.trim();
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 13),
        children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: safe),
        ],
      ),
    ),
  );
}

Widget _photoBlock(String label, List<String> base64List) {
  final bytes = base64List.map(_decodeImage).whereType<Uint8List>().toList();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      const SizedBox(height: 6),
      if (bytes.isEmpty)
        const Text('-', style: TextStyle(color: Colors.black54))
      else
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: bytes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes[index],
                  width: 88, height: 88, fit: BoxFit.cover),
            ),
          ),
        ),
    ],
  );
}

String _impactLabel(SnagProgrammeImpact value) {
  switch (value) {
    case SnagProgrammeImpact.yes:
      return 'Yes';
    case SnagProgrammeImpact.no:
      return 'No';
    case SnagProgrammeImpact.na:
      return 'N/A';
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
