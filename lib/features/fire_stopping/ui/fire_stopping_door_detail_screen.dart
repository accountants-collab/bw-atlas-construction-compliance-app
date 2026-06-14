import 'package:flutter/material.dart';

import 'fire_stopping_door_detail_full_screen.dart';

class FireStoppingDoorDetailScreen extends StatelessWidget {
  final String surveyId;
  final String doorId;

  const FireStoppingDoorDetailScreen({
    super.key,
    required this.surveyId,
    required this.doorId,
  });

  @override
  Widget build(BuildContext context) {
    return DoorDetailScreen(
      surveyId: surveyId,
      mode: DoorDetailMode.edit,
      existingDoorId: doorId,
      moduleKey: 'inspection',
      routePrefix: '/workspace/fire-stopping/inspection/projects',
      workspaceKey: 'fire-stopping',
    );
  }
}
