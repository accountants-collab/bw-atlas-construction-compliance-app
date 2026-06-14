import 'package:flutter/material.dart';

import 'fire_stopping_project_details_full_screen.dart';

class FireStoppingProjectDetailsScreen extends StatelessWidget {
  final String projectId;

  const FireStoppingProjectDetailsScreen({
    super.key,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    return ProjectDetailsScreen(
      surveyId: projectId,
      moduleKey: 'inspection',
      workspaceKey: 'fire-stopping',
    );
  }
}
