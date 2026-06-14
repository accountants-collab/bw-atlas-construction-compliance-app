import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_drawer.dart';
import '../../app/ui/branding_resolver.dart';
import '../../app/ui/mobile_bottom_navigation_bar.dart';
import '../../app/ui/workspace_switch_cards_bar.dart';
import '../../auth/auth_state.dart';
import '../../core/connectivity/connectivity_badge.dart';
import '../../features/modules/ui/module_projects_screen.dart';
import '../../features/settings/state/settings_controller.dart';
import 'ui/app_home_web_top_navigation.dart';

Color _moduleAccent(String workspaceKey) {
  switch (workspaceKey) {
    case 'fire-door':
      return const Color(0xFF1565C0);
    case 'fire-stopping':
      return const Color(0xFF0F766E);
    case 'snagging':
      return const Color(0xFFB45309);
    default:
      return const Color(0xFF1565C0);
  }
}

Color _moduleIconBg(String workspaceKey) {
  switch (workspaceKey) {
    case 'fire-door':
      return const Color(0xFFDEEBFF);
    case 'fire-stopping':
      return const Color(0xFFD1FAF0);
    case 'snagging':
      return const Color(0xFFFEF3C7);
    default:
      return const Color(0xFFDEEBFF);
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  DateTime? _lastBackPress;

  void _handleBackButton() {
    final now = DateTime.now();
    final isDoublePress = _lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2);

    if (isDoublePress) {
      // Double press - exit app
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    _lastBackPress = now;
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit BW Atlas'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/login');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final role = auth.userRole ?? UserRole.worker;
    final showMobileBottomNav = shouldShowMobileBottomNavigation(context);
    final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
    final canAccessFullMenu =
        role == UserRole.manager || role == UserRole.owner || isSuperAdmin;
    final userName = auth.currentUser?.name.trim().isEmpty ?? true
        ? auth.email
        : auth.currentUser!.name;
    final actualRole = auth.actualRole;
    final roleLabel = isSuperAdmin
        ? 'Super Admin'
        : actualRole == UserRole.owner
            ? 'Owner'
            : actualRole == UserRole.admin
                ? 'Admin'
                : (role == UserRole.manager ? 'Manager' : 'Worker');

    final spaces = const <_WorkspaceTileData>[
      _WorkspaceTileData(
        title: 'Fire Door Inspection',
        subtitle:
            'Inspections, remedial works, pre-installation checks, and installation handover.',
        route: '/workspace/fire-door',
        workspaceKey: 'fire-door',
        icon: Icons.fact_check_outlined,
      ),
      _WorkspaceTileData(
        title: 'Fire Stopping Inspection',
        subtitle:
            'Fire stopping inspections plus manager review and approval workflow.',
        route: '/workspace/fire-stopping',
        workspaceKey: 'fire-stopping',
        icon: Icons.shield_moon_outlined,
      ),
      _WorkspaceTileData(
        title: 'Snagging Inspection',
        subtitle:
            'Snagging inspections with remedials, pre-installation, and installation handover steps.',
        route: '/workspace/snagging',
        workspaceKey: 'snagging',
        icon: Icons.assignment_late_outlined,
      ),
    ];

    late final PreferredSizeWidget appBar;
    if (kIsWeb) {
      appBar = const AppHomeWebTopNavigation();
    } else {
      appBar = AppBar(
        title: Text('$userName ($roleLabel)'),
        bottom: const WorkspaceSwitchCardsBar(),
        actions: [
          const ConnectivityBadge(),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackButton();
        }
      },
      child: Scaffold(
        appBar: appBar,
        drawer: const AppDrawer(currentRoute: '/dashboard'),
        bottomNavigationBar:
            showMobileBottomNav ? const MobileBottomNavigationBar() : null,
        body: Column(
          children: [
            const ConnectivityBanner(),
            Expanded(
              child: Stack(
                children: [
                  // Subtle BW Atlas watermark background
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 24, bottom: 24),
                          child: Opacity(
                            opacity: 0.03,
                            child: Image.asset(
                              kDefaultSystemLogoAssetPath,
                              width: 420,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Dashboard content
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final crossAxisCount = w >= 1060 ? 3 : (w >= 620 ? 2 : 1);
                      final isWide = w >= 620;
                      return SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isWide ? 32 : 16,
                          vertical: isWide ? 32 : 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Page header
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Inspection Modules',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF111827),
                                          letterSpacing: -0.5,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Select a module to begin or continue work.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Module cards grid
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                childAspectRatio: crossAxisCount == 1
                                    ? 2.6
                                    : (crossAxisCount == 2 ? 1.5 : 1.35),
                              ),
                              itemCount: spaces.length,
                              itemBuilder: (_, i) => _PremiumModuleCard(
                                data: spaces[i],
                                onTap: () => _openWorkspaceOptions(
                                    context, ref, spaces[i], canAccessFullMenu),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openWorkspaceOptions(BuildContext context, WidgetRef ref,
      _WorkspaceTileData tile, bool canAccessFullMenu) {
    final auth = ref.read(authControllerProvider);
    final role = auth.userRole ?? UserRole.worker;
    final isSuperAdmin = auth.actualRole == UserRole.superAdmin;
    final canCreateProject =
        role == UserRole.manager || role == UserRole.owner || isSuperAdmin;

    String resolveRoute(String route) {
      final settings = ref.read(settingsControllerProvider);
      if (!settings.onboardingCompleted && canCreateProject) {
        return Uri(
          path: '/onboarding/company',
          queryParameters: {
            'mode': 'company',
            'returnTo': route,
          },
        ).toString();
      }

      final workspace = parseWorkspaceKey(tile.workspaceKey);
      if (!canCreateProject || workspace == null) return route;
      return route;
    }

    final options = _workspaceOptions(tile.workspaceKey, canAccessFullMenu);
    final useDialog = MediaQuery.sizeOf(context).width >= 900;

    if (useDialog) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tile.title),
          content: SizedBox(
            width: 460,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: options.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final option = options[i];
                return ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  tileColor: const Color(0xFFF6F7FB),
                  leading: Icon(option.icon, color: const Color(0xFF1565C0)),
                  title: Text(option.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(option.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.go(resolveRoute(option.route));
                  },
                );
              },
            ),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF6F7FB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(tile.title,
                style: Theme.of(sheetCtx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final option in options) ...[
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: ListTile(
                  leading: Icon(option.icon, color: const Color(0xFF1565C0)),
                  title: Text(option.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(option.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    context.go(resolveRoute(option.route));
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  List<_WorkspaceOption> _workspaceOptions(
      String workspaceKey, bool canAccessFullMenu) {
    final base = '/workspace/$workspaceKey';

    if (workspaceKey == 'snagging') {
      return [
        _WorkspaceOption(
          label: 'Snagging Inspection',
          subtitle: 'Open and manage snagging inspection projects',
          route: '$base/inspection/projects',
          icon: Icons.fact_check_outlined,
        ),
        _WorkspaceOption(
          label: 'Snagging Verification',
          subtitle: 'Review completed snagging work and approve or reject',
          route: '$base/verification/projects',
          icon: Icons.verified_outlined,
        ),
      ];
    }

    if (workspaceKey == 'fire-stopping') {
      return [
        _WorkspaceOption(
          label: 'Fire Stopping Inspection',
          subtitle: 'Start or continue fire stopping inspections.',
          route: '$base/inspection/projects',
          icon: Icons.fact_check_outlined,
        ),
        _WorkspaceOption(
          label: 'Manager Review & Approval',
          subtitle: 'Review submissions and approve or reject.',
          route: '$base/modules/remedials/projects',
          icon: Icons.verified_user_outlined,
        ),
      ];
    }

    final options = <_WorkspaceOption>[];

    if (canAccessFullMenu) {
      options.add(
        _WorkspaceOption(
          label: workspaceKey == 'snagging'
              ? 'Snagging Inspection'
              : 'Inspection Projects',
          subtitle: workspaceKey == 'snagging'
              ? 'Open and manage snagging inspection projects.'
              : 'Open and manage inspection projects.',
          route: '$base/inspection/projects',
          icon: Icons.fact_check_outlined,
        ),
      );
    }

    options.add(
      _WorkspaceOption(
        label: 'Remedial Works',
        subtitle: 'Track remedial tasks and approval status.',
        route: '$base/modules/remedials/projects',
        icon: Icons.build_outlined,
      ),
    );

    if (canAccessFullMenu) {
      options.add(
        _WorkspaceOption(
          label: 'Pre-Installation',
          subtitle: 'Prepare opening details before installation.',
          route: '$base/modules/preinstall/projects',
          icon: Icons.rule_folder_outlined,
        ),
      );
    }

    options.add(
      _WorkspaceOption(
        label: 'Installation & Handover',
        subtitle: 'Complete installation evidence and handover.',
        route: '$base/modules/installation/projects',
        icon: Icons.construction_outlined,
      ),
    );

    return options;
  }
}

class _PremiumModuleCard extends StatefulWidget {
  final _WorkspaceTileData data;
  final VoidCallback onTap;

  const _PremiumModuleCard({required this.data, required this.onTap});

  @override
  State<_PremiumModuleCard> createState() => _PremiumModuleCardState();
}

class _PremiumModuleCardState extends State<_PremiumModuleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = _moduleAccent(widget.data.workspaceKey);
    final iconBg = _moduleIconBg(widget.data.workspaceKey);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? accent.withValues(alpha: 0.35)
                  : const Color(0xFFE2E8F0),
              width: _hovered ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? accent.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: _hovered ? 22 : 8,
                offset: Offset(0, _hovered ? 8 : 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon container
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.data.icon, color: accent, size: 26),
                ),
                const SizedBox(height: 16),
                // Title
                Text(
                  widget.data.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                // Subtitle
                Expanded(
                  child: Text(
                    widget.data.subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 12),
                // Footer row
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Open module',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceTileData {
  final String title;
  final String subtitle;
  final String route;
  final String workspaceKey;
  final IconData icon;

  const _WorkspaceTileData({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.workspaceKey,
    required this.icon,
  });
}

class _WorkspaceOption {
  final String label;
  final String subtitle;
  final String route;
  final IconData icon;

  const _WorkspaceOption({
    required this.label,
    required this.subtitle,
    required this.route,
    required this.icon,
  });
}
