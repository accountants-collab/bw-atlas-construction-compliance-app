import 'package:flutter/material.dart';

import '../../surveys/domain/models.dart';
import 'inspection_workspace_screen.dart';

class SnaggingWorkspaceScreen extends StatelessWidget {
  const SnaggingWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const InspectionWorkspaceScreen(workspace: InspectionWorkspace.snagging);
  }
}
