import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_state.dart';
import '../../features/settings/state/settings_controller.dart';

bool shouldShowMobileBottomNavigation(BuildContext context) {
  if (kIsWeb) return false;
  if (MediaQuery.sizeOf(context).width >= 900) return false;
  final path = GoRouterState.of(context).matchedLocation;
  return shouldShowMobileBottomNavigationForPath(path);
}

bool shouldShowMobileBottomNavigationForPath(String path) {
  final normalized = path.trim();

  if (normalized.isEmpty) return true;
  if (normalized == '/' || normalized == '/dashboard') return true;

  // Root-level workspace/module/list routes where nav should stay visible.
  if (RegExp(r'^/workspace/[^/]+$').hasMatch(normalized)) return true;
  if (RegExp(r'^/workspace/[^/]+/inspection/projects$').hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^/workspace/[^/]+/verification/projects$')
      .hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^/workspace/[^/]+/modules/[^/]+/projects$')
      .hasMatch(normalized)) {
    return true;
  }

  // Worker task list roots.
  if (RegExp(r'^/workspace/[^/]+/remedials/[^/]+/doors$')
      .hasMatch(normalized)) {
    return false;
  }
  if (RegExp(r'^/workspace/[^/]+/modules/remedials/projects$')
      .hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^/workspace/[^/]+/modules/installation/projects$')
      .hasMatch(normalized)) {
    return true;
  }

  // Top-level utility screens.
  if (normalized.startsWith('/reports')) return true;
  if (normalized.startsWith('/app/preferences')) return true;
  if (normalized.startsWith('/company/')) return true;
  if (normalized.startsWith('/info/')) return true;
  if (normalized.startsWith('/account/')) return true;

  // Default: hide on detail/edit/camera/drawing/pdf/signature/full-screen flows.
  return false;
}

class MobileBottomNavigationBar extends ConsumerWidget {
  const MobileBottomNavigationBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final isWorker = (auth.userRole ?? UserRole.worker) == UserRole.worker;
    final workspaceKey = settings.activeWorkspaceKey;
    final path = GoRouterState.of(context).matchedLocation;

    final tabs =
        isWorker ? _workerTabs(workspaceKey) : _managerTabs(workspaceKey);
    final selectedIndex = _resolveIndex(path: path, tabs: tabs);

    return NavigationBar(
      selectedIndex: selectedIndex,
      height: 68,
      destinations: [
        for (final tab in tabs)
          NavigationDestination(
            icon: Icon(tab.icon),
            selectedIcon: Icon(tab.selectedIcon),
            label: tab.label,
          ),
      ],
      onDestinationSelected: (index) {
        final target = tabs[index].route;
        if (target == path) return;
        context.go(target);
      },
    );
  }

  int _resolveIndex({required String path, required List<_NavTab> tabs}) {
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].matches(path)) return i;
    }
    return 0;
  }

  List<_NavTab> _managerTabs(String workspaceKey) {
    return [
      _NavTab(
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        route: '/dashboard',
        matches: (path) => path == '/dashboard' || path == '/',
      ),
      _NavTab(
        label: 'Projects',
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder,
        route: '/workspace/$workspaceKey/inspection/projects',
        matches: (path) => path.contains('/inspection/projects'),
      ),
      _NavTab(
        label: 'Tasks',
        icon: Icons.task_alt_outlined,
        selectedIcon: Icons.task_alt,
        route: '/workspace/$workspaceKey/modules/remedials/projects',
        matches: (path) =>
            path.contains('/modules/remedials') || path.contains('/remedials/'),
      ),
      _NavTab(
        label: 'Reports',
        icon: Icons.assessment_outlined,
        selectedIcon: Icons.assessment,
        route: '/reports?workspace=$workspaceKey',
        matches: (path) => path.startsWith('/reports'),
      ),
      _NavTab(
        label: 'More',
        icon: Icons.menu,
        selectedIcon: Icons.menu_open,
        route: '/app/preferences',
        matches: (path) =>
            path.startsWith('/app/preferences') ||
            path.startsWith('/company/') ||
            path.startsWith('/info/') ||
            path.startsWith('/account/'),
      ),
    ];
  }

  List<_NavTab> _workerTabs(String workspaceKey) {
    return [
      _NavTab(
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        route: '/dashboard',
        matches: (path) => path == '/dashboard' || path == '/',
      ),
      _NavTab(
        label: 'Tasks',
        icon: Icons.assignment_outlined,
        selectedIcon: Icons.assignment,
        route: '/workspace/$workspaceKey/modules/remedials/projects',
        matches: (path) =>
            path.contains('/modules/remedials') || path.contains('/remedials/'),
      ),
      _NavTab(
        label: 'Completed',
        icon: Icons.verified_outlined,
        selectedIcon: Icons.verified,
        route: '/workspace/$workspaceKey/modules/installation/projects',
        matches: (path) =>
            path.contains('/modules/installation') ||
            path.contains('/installation/'),
      ),
      _NavTab(
        label: 'More',
        icon: Icons.menu,
        selectedIcon: Icons.menu_open,
        route: '/app/preferences',
        matches: (path) =>
            path.startsWith('/app/preferences') ||
            path.startsWith('/company/disclaimer-records') ||
            path.startsWith('/info/') ||
            path.startsWith('/account/'),
      ),
    ];
  }
}

class _NavTab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
  final bool Function(String path) matches;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
    required this.matches,
  });
}
