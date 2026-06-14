// DEPRECATED: Legacy shared survey export helper.
// Active runtime export flows use module-specific PDF builders.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../surveys/domain/models.dart';
import '../../surveys/state/survey_controller.dart';

enum AppModuleKey { inspection, remedials, preinstall, installation }

AppModuleKey? parseModuleKey(String raw) {
  switch (raw) {
    case 'inspection':
      return AppModuleKey.inspection;
    case 'remedials':
      return AppModuleKey.remedials;
    case 'preinstall':
      return AppModuleKey.preinstall;
    case 'installation':
      return AppModuleKey.installation;
    default:
      return null;
  }
}

SurveyType surveyTypeForModule(AppModuleKey m) {
  switch (m) {
    case AppModuleKey.inspection:
      return SurveyType.survey;
    case AppModuleKey.remedials:
      return SurveyType.maintenance;
    case AppModuleKey.preinstall:
      return SurveyType.installationSurvey;
    case AppModuleKey.installation:
      return SurveyType.installation;
  }
}

String moduleTitle(AppModuleKey m) {
  switch (m) {
    case AppModuleKey.inspection:
      return 'Fire Door Inspection';
    case AppModuleKey.remedials:
      return 'Remedial Works';
    case AppModuleKey.preinstall:
      return 'Pre-Installation Survey';
    case AppModuleKey.installation:
      return 'Installation & Handover';
  }
}

String moduleSubtitle(AppModuleKey m) {
  switch (m) {
    case AppModuleKey.inspection:
      return 'Create and manage inspection projects for buildings and sites.';
    case AppModuleKey.remedials:
      return 'Track remedial works projects and manage defect resolution.';
    case AppModuleKey.preinstall:
      return 'Manage pre-install surveys, sizing checks and site readiness.';
    case AppModuleKey.installation:
      return 'Maintain installation records, completion photos and handover packs.';
  }
}

class ModuleProjectsScreen extends ConsumerWidget {
  final String moduleKey;

  const ModuleProjectsScreen({super.key, required this.moduleKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = parseModuleKey(moduleKey);
    if (key == null) {
      return const Scaffold(body: Center(child: Text('Module not found')));
    }

    final controller = ref.watch(surveyControllerProvider.notifier);
    final state = ref.watch(surveyControllerProvider);

    final type = surveyTypeForModule(key);
    final projects = state.surveys.where((s) => s.type == type).toList();

    void addProject() {
      final created = controller.createSurvey(type);
      // Коректната навигация: първо попълване на детайлите за проекта!
      context.go('/surveys/${created.id}/details');
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(moduleTitle(key)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    moduleSubtitle(key),
                    style: const TextStyle(color: Colors.black54, height: 1.3),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: addProject,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Project'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: projects.isEmpty
                      ? const Center(
                          child: Text(
                            'No projects yet.\nClick "Add Project" to create your first project.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54, height: 1.3),
                          ),
                        )
                      : ListView.builder(
                          itemCount: projects.length,
                          itemBuilder: (context, i) {
                            final p = projects[i];
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: ListTile(
                                title: Text(
                                  p.reportName.trim().isEmpty ? 'Untitled project' : p.reportName,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  p.siteAddress.trim().isEmpty ? 'No address' : p.siteAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                // Навигация към Door List:
                                onTap: () => context.go('/surveys/${p.id}/report'),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}