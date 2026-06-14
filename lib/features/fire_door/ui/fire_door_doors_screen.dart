import 'package:flutter/material.dart';

import 'fire_door_doors_full_screen.dart';

class FireDoorDoorsScreen extends StatelessWidget {
  final String surveyId;

  const FireDoorDoorsScreen({
    super.key,
    required this.surveyId,
  });

  @override
  Widget build(BuildContext context) {
    return DoorsScreen(
      surveyId: surveyId,
      moduleKey: 'inspection',
      routePrefix: '/workspace/fire-door/inspection/projects',
      workspaceKey: 'fire-door',
    );
  }
}
