import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../domain/fire_stopping_models.dart';
import '../pdf/fire_stopping_pdf_builder.dart';
import '../state/fire_stopping_module_controller.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';

class FireStoppingItemsScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String? itemId;
  const FireStoppingItemsScreen({super.key, required this.projectId, this.itemId});

  @override
  ConsumerState<FireStoppingItemsScreen> createState() => _FireStoppingItemsScreenState();
}

class _FireStoppingItemsScreenState extends ConsumerState<FireStoppingItemsScreen> {
  @override
  Widget build(BuildContext context) {
    final controller = ref.read(fireStoppingModuleControllerProvider.notifier);
    final project = controller.getProject(widget.projectId);
    if (project == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }

    final selectedItem = widget.itemId == null
        ? null
        : project.items.where((e) => e.id == widget.itemId).cast<FireStoppingItem?>().firstWhere((e) => e != null, orElse: () => null);

    Future<void> exportPdf() async {
      final bytes = await FireStoppingPdfBuilder.buildProjectReport(project);
      await Printing.sharePdf(bytes: bytes, filename: 'fire_stopping_${project.id}.pdf');
    }

    final content = widget.itemId == null
        ? ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: () {
                  final item = controller.addItem(widget.projectId);
                  context.go('/workspace/fire-stopping/inspection/projects/${widget.projectId}/items/${item.id}');
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF'),
              ),
              const SizedBox(height: 12),
              if (project.items.isEmpty)
                const Text('No items yet.')
              else
                ...project.items.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(item.reference.isEmpty ? 'Unnamed item' : item.reference),
                      subtitle: Text('Status: ${item.status.name} | Findings: ${item.findings.length}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/workspace/fire-stopping/inspection/projects/${widget.projectId}/items/${item.id}'),
                    ),
                  ),
                ),
            ],
          )
        : _FireStoppingItemEditor(projectId: widget.projectId, item: selectedItem!);

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: widget.itemId == null
            ? '/workspace/fire-stopping/inspection/projects/${widget.projectId}/items'
            : '/workspace/fire-stopping/inspection/projects/${widget.projectId}/items/${widget.itemId}',
        title: 'Fire Stopping Inspection',
        workflowLabel: 'Inspection Projects',
        drawerRoute: '/workspace/fire-stopping/inspection/projects',
        workspaceKey: 'fire-stopping',
        surveyId: widget.projectId,
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemId == null ? 'Fire Stopping Items' : 'Fire Stopping Item'),
        actions: [
          IconButton(onPressed: exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
        ],
      ),
      body: content,
    );
  }
}

class _FireStoppingItemEditor extends ConsumerStatefulWidget {
  final String projectId;
  final FireStoppingItem item;
  const _FireStoppingItemEditor({required this.projectId, required this.item});

  @override
  ConsumerState<_FireStoppingItemEditor> createState() => _FireStoppingItemEditorState();
}

class _FireStoppingItemEditorState extends ConsumerState<_FireStoppingItemEditor> {
  final _reference = TextEditingController();
  final _level = TextEditingController();
  final _location = TextEditingController();
  FireStoppingStatus _status = FireStoppingStatus.pending;
  bool _loaded = false;

  @override
  void dispose() {
    _reference.dispose();
    _level.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      _loaded = true;
      _reference.text = widget.item.reference;
      _level.text = widget.item.level;
      _location.text = widget.item.location;
      _status = widget.item.status;
    }

    final controller = ref.read(fireStoppingModuleControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextFormField(controller: _reference, decoration: const InputDecoration(labelText: 'Reference', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextFormField(controller: _level, decoration: const InputDecoration(labelText: 'Level', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        DropdownButtonFormField<FireStoppingStatus>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
          items: FireStoppingStatus.values.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _status = v);
          },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            controller.updateItem(
              projectId: widget.projectId,
              itemId: widget.item.id,
              update: (current) => current.copyWith(
                reference: _reference.text.trim(),
                level: _level.text.trim(),
                location: _location.text.trim(),
                status: _status,
              ),
            );
            Navigator.pop(context);
          },
          icon: const Icon(Icons.save),
          label: const Text('Save Item'),
        ),
      ],
    );
  }
}
