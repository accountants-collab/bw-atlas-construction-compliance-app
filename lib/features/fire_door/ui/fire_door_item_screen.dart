import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/fire_door_models.dart';
import '../state/fire_door_controller.dart';
import 'fire_door_web_shell_scaffold.dart';

class FireDoorItemScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String itemId;
  const FireDoorItemScreen({super.key, required this.projectId, required this.itemId});

  @override
  ConsumerState<FireDoorItemScreen> createState() => _FireDoorItemScreenState();
}

class _FireDoorItemScreenState extends ConsumerState<FireDoorItemScreen> {
  final _doorRef = TextEditingController();
  final _level = TextEditingController();
  final _location = TextEditingController();
  bool _loaded = false;
  FireDoorResult _result = FireDoorResult.notInspected;

  @override
  void dispose() {
    _doorRef.dispose();
    _level.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(fireDoorControllerProvider.notifier);
    final project = controller.getProject(widget.projectId);
    if (project == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }
    FireDoorItem? item;
    for (final e in project.items) {
      if (e.id == widget.itemId) {
        item = e;
        break;
      }
    }
    if (item == null) {
      return const Scaffold(body: Center(child: Text('Item not found')));
    }

    if (!_loaded) {
      _loaded = true;
      _doorRef.text = item.doorRef;
      _level.text = item.level;
      _location.text = item.location;
      _result = item.result;
    }

    final content = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(controller: _doorRef, decoration: const InputDecoration(labelText: 'Door Reference', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextFormField(controller: _level, decoration: const InputDecoration(labelText: 'Level', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<FireDoorResult>(
            initialValue: _result,
            decoration: const InputDecoration(labelText: 'Result', border: OutlineInputBorder()),
            items: FireDoorResult.values
                .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _result = v);
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              controller.updateItem(
                projectId: widget.projectId,
                itemId: widget.itemId,
                update: (current) => current.copyWith(
                  doorRef: _doorRef.text.trim(),
                  level: _level.text.trim(),
                  location: _location.text.trim(),
                  result: _result,
                ),
              );
              Navigator.pop(context);
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Door'),
          ),
        ],
      );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: '/workspace/fire-door/inspection/projects/${widget.projectId}/items/${widget.itemId}',
        title: 'Fire Door Inspection',
        workspaceKey: 'fire-door',
        workflowLabel: 'Inspection Projects',
        drawerRoute: '/workspace/fire-door/inspection/projects',
        surveyId: widget.projectId,
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fire Door Item')),
      body: content,
    );
  }
}
