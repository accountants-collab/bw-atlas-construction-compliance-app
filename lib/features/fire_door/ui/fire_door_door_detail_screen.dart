import 'package:flutter/material.dart';

import 'fire_door_door_detail_full_screen.dart';

class FireDoorDoorDetailScreen extends StatelessWidget {
  final String surveyId;
  final String doorId;

  const FireDoorDoorDetailScreen({
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
      routePrefix: '/workspace/fire-door/inspection/projects',
      workspaceKey: 'fire-door',
    );
  }
}
