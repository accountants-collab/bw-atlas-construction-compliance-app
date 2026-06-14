import 'package:flutter/material.dart';

import 'fire_door_project_details_full_screen.dart';

class FireDoorProjectDetailsScreen extends StatelessWidget {
  final String projectId;

  const FireDoorProjectDetailsScreen({
    super.key,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    return ProjectDetailsScreen(
      surveyId: projectId,
      moduleKey: 'inspection',
      workspaceKey: 'fire-door',
    );
  }
}
