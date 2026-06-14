import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../settings/state/settings_controller.dart';

class SurveyListScreen extends ConsumerWidget {
  const SurveyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isTablet = MediaQuery.of(context).size.width >= 700;
    final maxWidth = isTablet ? 760.0 : double.infinity;
    final settings = ref.watch(settingsControllerProvider);
    final companyName = getActiveCompanyName(settings.companyProfile);
    final activeWorkspace = settings.activeWorkspaceKey;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const SizedBox.shrink(),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 6),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F6FEB).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF1F6FEB)
                                .withValues(alpha: 0.18)),
                      ),
                      child: const Icon(Icons.shield_outlined,
                          color: Color(0xFF1F6FEB), size: 36),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      companyName,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Select a module to manage projects and reports',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Modules(
                      isTablet: isTablet,
                      onTapInspection: () =>
                          context.go('/inspections/fire-door/projects'),
                      onTapFireStopping: () =>
                          context.go('/inspections/fire-stopping/projects'),
                      onTapSnagging: () =>
                          context.go('/inspections/snagging/projects'),
                      onTapRemedials: () => context.go(
                          '/workspace/$activeWorkspace/modules/remedials/projects'),
                      onTapPreInstall: () => context.go(
                          '/workspace/$activeWorkspace/modules/preinstall/projects'),
                      onTapInstallHandover: () => context.go(
                          '/workspace/$activeWorkspace/modules/installation/projects'),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Modules extends StatelessWidget {
  final bool isTablet;

  final VoidCallback onTapInspection;
  final VoidCallback onTapFireStopping;
  final VoidCallback onTapSnagging;
  final VoidCallback onTapRemedials;
  final VoidCallback onTapPreInstall;
  final VoidCallback onTapInstallHandover;

  const _Modules({
    required this.isTablet,
    required this.onTapInspection,
    required this.onTapFireStopping,
    required this.onTapSnagging,
    required this.onTapRemedials,
    required this.onTapPreInstall,
    required this.onTapInstallHandover,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _ModuleCard(
        title: 'Fire Door Inspection',
        subtitle: 'Compliance surveys and door assessments',
        icon: Icons.fact_check_outlined,
        onTap: onTapInspection,
      ),
      _ModuleCard(
        title: 'Fire Stopping Inspection',
        subtitle: 'Inspection and defect reporting for fire stopping works',
        icon: Icons.shield_moon_outlined,
        onTap: onTapFireStopping,
      ),
      _ModuleCard(
        title: 'Snagging Inspection',
        subtitle: 'General snagging and quality defect reporting',
        icon: Icons.assignment_late_outlined,
        onTap: onTapSnagging,
      ),
      _ModuleCard(
        title: 'Remedial Works',
        subtitle: 'Repairs, adjustments and defect tracking',
        icon: Icons.build_outlined,
        onTap: onTapRemedials,
      ),
      _ModuleCard(
        title: 'Pre-Installation Survey',
        subtitle: 'Pre-install checks, sizing and site readiness',
        icon: Icons.rule_folder_outlined,
        onTap: onTapPreInstall,
      ),
      _ModuleCard(
        title: 'Installation & Handover',
        subtitle: 'Installed door records, photos and completion',
        icon: Icons.construction_outlined,
        onTap: onTapInstallHandover,
      ),
    ];

    if (!isTablet) {
      return Column(
        children: [
          for (final w in children) ...[
            w,
            const SizedBox(height: 12),
          ],
        ],
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: children,
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white,
      elevation: 1.2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F6FEB).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF1F6FEB).withValues(alpha: 0.18)),
                ),
                child: Icon(icon, color: const Color(0xFF1F6FEB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.black54, height: 1.2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}
