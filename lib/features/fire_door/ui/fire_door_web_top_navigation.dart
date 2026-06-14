import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../../auth/auth_state.dart';
import '../../settings/state/settings_controller.dart';
import '../inspection/domain/models.dart';
import '../inspection/state/survey_controller.dart';

class FireDoorWebTopNavigation extends ConsumerWidget implements PreferredSizeWidget {
  final String currentRoute;
  final String title;
  final String workflowLabel;
  final String? surveyId;

  const FireDoorWebTopNavigation({
    super.key,
    required this.currentRoute,
    required this.title,
    required this.workflowLabel,
    this.surveyId,
  });

  @override
  Size get preferredSize => const Size.fromHeight(92);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final surveys = ref.watch(surveyControllerFamilyProvider(InspectionWorkspace.fireDoor)).surveys;
    final activeLogo = getActiveLogo(settings.companyProfile);

    final notices = _buildFireDoorNotices(auth: auth, surveys: surveys);
    final needsAction = notices.where((n) => n.needsAction).length;

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 46,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 8,
      leadingWidth: 190,
      leading: Row(
        children: [
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go('/dashboard'),
            child: SizedBox(
              width: 112,
              height: 30,
              child: activeLogo.hasCompanyLogo
                  ? Image.memory(
                      Uint8List.fromList(activeLogo.companyLogoBytes),
                      fit: BoxFit.contain,
                    )
                  : Image.asset(
                      activeLogo.fallbackAssetPath,
                      fit: BoxFit.contain,
                    ),
            ),
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Open navigation menu',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Fire Door',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D47A1),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      actions: [
        _NotificationBellButton(notices: notices, needsActionCount: needsAction),
        _ProfileMenuButton(auth: auth),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Container(
          height: 46,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFFDFE4EA), width: 1),
              bottom: BorderSide(color: Color(0xFFDFE4EA), width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _FireDoorWorkflowMenu(currentLabel: workflowLabel),
              const Spacer(),
              _ContextActionButton(
                label: '+ Add Project',
                onTap: () {
                  context.go('/workspace/fire-door/inspection/projects');
                },
              ),
              const SizedBox(width: 8),
              _ContextActionButton(
                label: 'Groups',
                onTap: () {
                  context.go('/company/workspace-groups');
                },
              ),
              const SizedBox(width: 8),
              _ContextActionButton(
                label: '+ Add Door',
                onTap: () {
                  if (surveyId == null || surveyId!.isEmpty) {
                    context.go('/workspace/fire-door/inspection/projects');
                    return;
                  }
                  context.go('/workspace/fire-door/inspection/projects/$surveyId/doors');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ContextActionButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _FireDoorWorkflowMenu extends StatelessWidget {
  final String currentLabel;

  const _FireDoorWorkflowMenu({required this.currentLabel});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Fire Door workflow menu',
      onSelected: (route) => context.go(route),
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: '/workspace/fire-door/inspection/projects',
          child: Text('Inspection Projects'),
        ),
        PopupMenuItem<String>(
          value: '/workspace/fire-door/modules/remedials/projects',
          child: Text('Remedial Works'),
        ),
        PopupMenuItem<String>(
          value: '/workspace/fire-door/modules/preinstall/projects',
          child: Text('Pre-Installation'),
        ),
        PopupMenuItem<String>(
          value: '/workspace/fire-door/modules/installation/projects',
          child: Text('Installation & Handover'),
        ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(currentLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class _NotificationBellButton extends StatelessWidget {
  final List<_FireDoorNotice> notices;
  final int needsActionCount;

  const _NotificationBellButton({
    required this.notices,
    required this.needsActionCount,
  });

  @override
  Widget build(BuildContext context) {
    final needsAction = notices.where((n) => n.needsAction).toList();
    final recent = notices.where((n) => !n.needsAction).toList();

    return Stack(
      children: [
        PopupMenuButton<String>(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_rounded),
          itemBuilder: (_) {
            final items = <PopupMenuEntry<String>>[];
            items.add(const PopupMenuItem<String>(enabled: false, child: Text('Needs Action')));
            if (needsAction.isEmpty) {
              items.add(const PopupMenuItem<String>(enabled: false, child: Text('No pending Fire Door actions')));
            } else {
              for (final item in needsAction.take(6)) {
                items.add(PopupMenuItem<String>(
                  enabled: false,
                  child: _NoticeRow(item: item),
                ));
              }
            }

            items.add(const PopupMenuDivider());
            items.add(const PopupMenuItem<String>(enabled: false, child: Text('Recently Completed')));
            if (recent.isEmpty) {
              items.add(const PopupMenuItem<String>(enabled: false, child: Text('No recent completions')));
            } else {
              for (final item in recent.take(4)) {
                items.add(PopupMenuItem<String>(
                  enabled: false,
                  child: _NoticeRow(item: item),
                ));
              }
            }
            return items;
          },
        ),
        if (needsActionCount > 0)
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Color(0xFFC62828), shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

class _NoticeRow extends StatelessWidget {
  final _FireDoorNotice item;

  const _NoticeRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 2),
          Text(item.subtitle, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }
}

class _ProfileMenuButton extends ConsumerWidget {
  final AuthState auth;

  const _ProfileMenuButton({required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = auth.currentUser;
    final fullName = (user?.name ?? '').trim().isEmpty ? auth.email : user!.name.trim();
    final role = _roleLabel(auth.userRole ?? UserRole.worker);
    final initials = _initialsFor(fullName);

    return PopupMenuButton<String>(
      tooltip: 'Profile menu',
      onSelected: (value) async {
        if (value == 'profile') {
          context.go('/account/profile');
          return;
        }
        if (value == 'logout') {
          await ref.read(authControllerProvider.notifier).logout();
          if (context.mounted) {
            context.go('/login');
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(role, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'profile', child: Text('My Profile')),
        const PopupMenuItem<String>(value: 'logout', child: Text('Log out')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFFE3F2FD),
          foregroundColor: const Color(0xFF0D47A1),
          child: Text(initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _FireDoorNotice {
  final String title;
  final String subtitle;
  final bool needsAction;

  const _FireDoorNotice({
    required this.title,
    required this.subtitle,
    required this.needsAction,
  });
}

String _initialsFor(String value) {
  final parts = value
      .split(RegExp(r'\s+'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

String _roleLabel(UserRole role) {
  switch (role) {
    case UserRole.owner:
      return 'Owner';
    case UserRole.admin:
      return 'Admin';
    case UserRole.manager:
      return 'Manager';
    case UserRole.worker:
      return 'Worker';
    case UserRole.superAdmin:
      return 'Super Admin';
  }
}

List<_FireDoorNotice> _buildFireDoorNotices({
  required AuthState auth,
  required List<Survey> surveys,
}) {
  final role = auth.userRole ?? UserRole.worker;
  final notices = <_FireDoorNotice>[];

  for (final survey in surveys.where((s) => s.type == SurveyType.survey)) {
    final project = survey.reportName.trim().isNotEmpty
        ? survey.reportName.trim()
        : (survey.siteName.trim().isNotEmpty ? survey.siteName.trim() : survey.siteAddress.trim());
    final projectLabel = project.isEmpty ? 'Project not named' : project;

    for (final door in survey.doors) {
      if (door.replacementRequired) {
        continue;
      }
      final doorRef = door.doorIdTag.trim().isNotEmpty
          ? door.doorIdTag.trim()
          : 'D-${door.number.toString().padLeft(2, '0')}';

      if (role == UserRole.worker) {
        if (door.remedialStatus == RemedialStatus.pending) {
          notices.add(
            _FireDoorNotice(
              title: 'Fire Door - $doorRef - Newly assigned work',
              subtitle: projectLabel,
              needsAction: true,
            ),
          );
        } else if (door.remedialStatus == RemedialStatus.inProgress) {
          notices.add(
            _FireDoorNotice(
              title: 'Fire Door - $doorRef - Waiting on worker action',
              subtitle: projectLabel,
              needsAction: true,
            ),
          );
        } else if (door.remedialStatus == RemedialStatus.rejectedNeedsRework) {
          notices.add(
            _FireDoorNotice(
              title: 'Fire Door - $doorRef - Rework required',
              subtitle: projectLabel,
              needsAction: true,
            ),
          );
        } else if (door.remedialStatus == RemedialStatus.approved) {
          notices.add(
            _FireDoorNotice(
              title: 'Fire Door - $doorRef - Approved',
              subtitle: projectLabel,
              needsAction: false,
            ),
          );
        }
      } else {
        if (door.remedialStatus == RemedialStatus.forApproval) {
          notices.add(
            _FireDoorNotice(
              title: 'Fire Door - $doorRef - Waiting for approval',
              subtitle: projectLabel,
              needsAction: true,
            ),
          );
        } else if (door.remedialStatus == RemedialStatus.completedByWorker) {
          notices.add(
            _FireDoorNotice(
              title: 'Fire Door - $doorRef - Completed by worker',
              subtitle: projectLabel,
              needsAction: true,
            ),
          );
        } else if (door.remedialStatus == RemedialStatus.approved) {
          notices.add(
            _FireDoorNotice(
              title: 'Fire Door - $doorRef - Approved',
              subtitle: projectLabel,
              needsAction: false,
            ),
          );
        }
      }
    }
  }

  final sortedNotices = List<_FireDoorNotice>.from(notices);
  try {
    if (sortedNotices.length > 1) {
      sortedNotices.sort((a, b) {
        if (a.needsAction == b.needsAction) {
          final aTitle = a.title;
          final bTitle = b.title;
          return aTitle.compareTo(bTitle);
        }
        return a.needsAction ? -1 : 1;
      });
    }
  } catch (e) {
    debugPrint('Sort error (fire door web notices): $e');
  }
  return sortedNotices;
}
