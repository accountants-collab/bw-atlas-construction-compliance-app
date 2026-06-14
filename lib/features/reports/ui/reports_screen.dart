import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/mobile_bottom_navigation_bar.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/state/survey_controller.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  String _workspaceLabel(InspectionWorkspace workspace) {
    switch (workspace) {
      case InspectionWorkspace.fireDoor:
        return 'Fire Door';
      case InspectionWorkspace.fireStopping:
        return 'Fire Stopping';
      case InspectionWorkspace.snagging:
        return 'Snagging';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showMobileBottomNav = shouldShowMobileBottomNavigation(context);
    final allSurveys = ref.watch(surveyControllerProvider).surveys;
    final workspaceParam =
        GoRouterState.of(context).queryParameters['workspace'];
    final workspaceFilter = workspaceParam == null
        ? null
        : parseInspectionWorkspaceKey(workspaceParam);
    final surveys = workspaceFilter == null
        ? allSurveys
        : allSurveys.where((s) => s.workspace == workspaceFilter).toList();
    final reportTitle = workspaceFilter == null
        ? 'Reports'
        : '${_workspaceLabel(workspaceFilter)} Reports';
    final drawerRoute = workspaceFilter == null
        ? '/reports'
        : '/reports?workspace=${inspectionWorkspaceSlug(workspaceFilter)}';

    String routeForSurvey(Survey survey) {
      final workspace = inspectionWorkspaceSlug(survey.workspace);
      switch (survey.type) {
        case SurveyType.survey:
        case SurveyType.fireStopping:
        case SurveyType.snagging:
          return '/workspace/$workspace/inspection/projects/${survey.id}/details';
        case SurveyType.installationSurvey:
          return '/workspace/$workspace/preinstall/${survey.id}/items';
        case SurveyType.installation:
          return '/workspace/$workspace/installation/${survey.id}/items';
        case SurveyType.maintenance:
          return '/workspace/$workspace/remedials/${survey.id}/doors';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(reportTitle),
        bottom: const WorkspaceSwitchCardsBar(),
      ),
      drawer: AppDrawer(currentRoute: drawerRoute),
      bottomNavigationBar:
          showMobileBottomNav ? const MobileBottomNavigationBar() : null,
      body: surveys.isEmpty
          ? const Center(child: Text('No reports yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: surveys.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final s = surveys[i];
                final title =
                    s.reportName.trim().isEmpty ? s.id : s.reportName.trim();
                final type = s.type.name;
                return Card(
                  child: ListTile(
                    title: Text(title),
                    subtitle: Text('Type: $type • Doors: ${s.doors.length}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(routeForSurvey(s)),
                  ),
                );
              },
            ),
    );
  }
}
