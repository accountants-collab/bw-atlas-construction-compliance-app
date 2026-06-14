import 'package:flutter/material.dart';

import '../../../app/app_drawer.dart';
import 'module_web_top_navigation.dart';

class ModuleWebShellScaffold extends StatelessWidget {
  final String drawerRoute;
  final ModuleWebTopNavigationConfig config;
  final Widget body;
  final Color? backgroundColor;

  const ModuleWebShellScaffold({
    super.key,
    required this.drawerRoute,
    required this.config,
    required this.body,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: AppDrawer(currentRoute: drawerRoute),
      appBar: ModuleWebTopNavigation(config: config),
      body: body,
    );
  }
}
