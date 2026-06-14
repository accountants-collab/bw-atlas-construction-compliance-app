import 'package:flutter/material.dart';

import '../../surveys/domain/models.dart';
import 'inspection_workspace_screen.dart';

class FireDoorWorkspaceScreen extends StatelessWidget {
  const FireDoorWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const InspectionWorkspaceScreen(workspace: InspectionWorkspace.fireDoor);
  }
}
