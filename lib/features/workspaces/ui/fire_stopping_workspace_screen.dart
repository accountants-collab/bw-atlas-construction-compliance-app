import 'package:flutter/material.dart';

import '../../surveys/domain/models.dart';
import 'inspection_workspace_screen.dart';

class FireStoppingWorkspaceScreen extends StatelessWidget {
  const FireStoppingWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const InspectionWorkspaceScreen(workspace: InspectionWorkspace.fireStopping);
  }
}
