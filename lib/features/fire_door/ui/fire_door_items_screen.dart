import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../pdf/fire_door_pdf_builder.dart';
import '../state/fire_door_controller.dart';
import 'fire_door_web_shell_scaffold.dart';

class FireDoorItemsScreen extends ConsumerWidget {
  final String projectId;
  const FireDoorItemsScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(fireDoorControllerProvider.notifier);
    final project = controller.getProject(projectId);
    if (project == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }

    Future<void> exportPdf() async {
      final bytes = await FireDoorPdfBuilder.buildProjectReport(project);
      await Printing.sharePdf(bytes: bytes, filename: 'fire_door_${project.id}.pdf');
    }

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () {
            final item = controller.addItem(projectId);
            context.go('/workspace/fire-door/inspection/projects/$projectId/items/${item.id}');
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Door'),
        ),
        const SizedBox(height: 12),
        if (project.items.isEmpty)
          const Text('No doors yet.')
        else
          ...project.items.map(
            (item) => Card(
              child: ListTile(
                title: Text(item.doorRef.isEmpty ? 'Unnamed door' : item.doorRef),
                subtitle: Text('Result: ${item.result.name} | Issues: ${item.issues.length}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/workspace/fire-door/inspection/projects/$projectId/items/${item.id}'),
              ),
            ),
          ),
      ],
    );

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        currentRoute: '/workspace/fire-door/inspection/projects/$projectId/items',
        title: 'Fire Door Inspection',
        workspaceKey: 'fire-door',
        workflowLabel: 'Inspection Projects',
        drawerRoute: '/workspace/fire-door/inspection/projects',
        surveyId: projectId,
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fire Door Items'),
        actions: [
          IconButton(onPressed: exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
        ],
      ),
      body: content,
    );
  }
}
