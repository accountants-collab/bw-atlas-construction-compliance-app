import 'package:flutter/material.dart';

import 'fire_stopping_doors_full_screen.dart';

class FireStoppingDoorsScreen extends StatelessWidget {
  final String surveyId;

  const FireStoppingDoorsScreen({
    super.key,
    required this.surveyId,
  });

  @override
  Widget build(BuildContext context) {
    return DoorsScreen(
      surveyId: surveyId,
      moduleKey: 'inspection',
      routePrefix: '/workspace/fire-stopping/inspection/projects',
      workspaceKey: 'fire-stopping',
    );
  }
}
