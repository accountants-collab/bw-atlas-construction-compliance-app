import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../settings/state/settings_controller.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/state/survey_controller.dart';

class CreateReportScreen extends ConsumerWidget {
  const CreateReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(surveyControllerProvider);
    final controller = ref.read(surveyControllerProvider.notifier);
    final activeWorkspaceKey = ref.watch(settingsControllerProvider).activeWorkspaceKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Report'),
        bottom: const WorkspaceSwitchCardsBar(),
      ),
      drawer: const AppDrawer(currentRoute: '/reports/create'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Select report workflow',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _option(
            context: context,
            title: 'Fire Door Inspection',
            subtitle: 'Create a new inspection report project.',
            onTap: () {
              context.go('/workspace/$activeWorkspaceKey/inspection/projects');
            },
          ),
          _option(
            context: context,
            title: 'Pre-Installation Survey',
            subtitle: 'Create a new pre-installation report project.',
            onTap: () {
              final s = controller.createSurvey(SurveyType.installationSurvey);
              context.go('/workspace/$activeWorkspaceKey/preinstall/${s.id}/items');
            },
          ),
          _option(
            context: context,
            title: 'Installation & Handover',
            subtitle: 'Open installation projects and complete handover.',
            onTap: () => context.go('/workspace/$activeWorkspaceKey/modules/installation/projects'),
          ),
          _option(
            context: context,
            title: 'Remedial Works',
            subtitle: 'Open remedial projects generated from inspection defects.',
            onTap: () => context.go('/workspace/$activeWorkspaceKey/modules/remedials/projects'),
          ),
        ],
      ),
    );
  }

  Widget _option({
    required BuildContext context,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
