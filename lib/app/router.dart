import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/accept_invite_screen.dart';
import '../auth/auth_state.dart';
import '../auth/forgot_password_screen.dart';
import '../auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/information/ui/about_app_screen.dart';
import '../features/information/ui/contact_support_screen.dart';
import '../features/information/ui/how_it_works_screen.dart';
import '../features/information/ui/privacy_policy_screen.dart';
import '../features/information/ui/terms_conditions_screen.dart';
import '../features/commercial/ui/bw_service_booking_screen.dart';
import '../features/commercial/ui/customer_registration_screen.dart';
import '../features/account/ui/my_profile_screen.dart';
import '../features/disclaimer/ui/disclaimer_record_screen.dart';
import '../features/disclaimer/ui/disclaimer_records_screen.dart';
import '../features/fire_door/ui/fire_door_door_detail_screen.dart';
import '../features/fire_door/ui/fire_door_doors_screen.dart';
import '../features/fire_door/ui/fire_door_project_details_screen.dart';
import '../features/fire_door/ui/fire_door_projects_screen.dart';
import '../features/fire_door/ui/fire_door_workspace_screen.dart';
import '../features/fire_stopping/ui/fire_stopping_door_detail_screen.dart';
import '../features/fire_stopping/ui/fire_stopping_doors_screen.dart';
import '../features/fire_stopping/ui/fire_stopping_project_details_screen.dart';
import '../features/fire_stopping/ui/fire_stopping_projects_screen.dart';
import '../features/fire_stopping/ui/fire_stopping_workspace_screen.dart';
import '../features/installation/ui/installation_item_list_screen.dart';
import '../features/installation/ui/installation_item_screen.dart';
import '../features/manager/invites/manager_invites_screen.dart';
import '../features/modules/ui/module_projects_screen.dart';
import '../features/onboarding/ui/company_onboarding_screen.dart';
import '../features/preinstall/ui/preinstallation_survey_builder_list_screen.dart';
import '../features/preinstall/ui/preinstallation_survey_builder_screen.dart';
import '../features/reports/ui/create_report_screen.dart';
import '../features/reports/ui/reports_screen.dart';
import '../features/remedials/ui/remedial_door_detail_screen.dart';
import '../features/remedials/ui/remedial_door_list_screen.dart';
import '../features/remedials/ui/remedial_project_list_screen.dart';
import '../features/remedials/ui/remedial_review_screen.dart';
import '../features/platform/ui/super_admin_panel_screen.dart';
import '../features/settings/ui/app_preferences_screen.dart';
import '../features/settings/ui/quick_login_settings_screen.dart';
import '../features/settings/ui/branding_screen.dart';
import '../features/settings/ui/settings_home_screen.dart';
import '../features/settings/ui/subscription_screen.dart';
import '../features/settings/ui/team_users_screen.dart';
import '../features/settings/ui/workspace_groups_screen.dart';
import '../features/settings/state/settings_controller.dart';
import '../features/snagging/ui/snagging_issues_screen.dart';
import '../features/snagging/ui/snagging_project_details_screen.dart';
import '../features/snagging/ui/snagging_projects_screen.dart';
import '../features/snagging/ui/snagging_verification_screen.dart';
import '../features/snagging/ui/snagging_workspace_screen.dart';
import '../features/surveys/ui/project_details_screen.dart';
import 'router_refresh.dart';

String _extractInviteToken(GoRouterState state) {
  final fromQuery = (state.queryParameters['token'] ?? '').trim();
  if (fromQuery.isNotEmpty) return fromQuery;

  return '';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.matchedLocation;
      final inviteToken = _extractInviteToken(state);

      if (auth.isLoading) {
        return null;
      }

      final isLoggedIn = auth.isLoggedIn;
      final isLoginPath = path == '/login';
      final isRegisterPath = path == '/register';
      final isForgotPath = path == '/forgot-password';
      final isPublicCommercialPath = path == '/register' || path == '/book-services';
      final isInvitePath = path == '/invite' || path.startsWith('/invite/');

      if (!isLoggedIn) {
        if (inviteToken.isNotEmpty && !isInvitePath) {
          final encoded = Uri.encodeComponent(inviteToken);
          return '/invite/$encoded';
        }
        if (isLoginPath || isPublicCommercialPath || isInvitePath || isForgotPath) return null;
        return '/login';
      }

      if (isLoginPath || isRegisterPath || isForgotPath) {
        return '/dashboard';
      }

      if (path.startsWith('/platform/admin') && auth.actualRole != UserRole.superAdmin) {
        return '/dashboard';
      }

      final role = auth.userRole ?? UserRole.worker;
      final activeWorkspaceKey = ref.read(settingsControllerProvider).activeWorkspaceKey;

      if (role == UserRole.worker) {
        if (path.startsWith('/book-services')) {
          return '/dashboard';
        }

        if (path.startsWith('/onboarding/company') ||
            path.startsWith('/company/settings') ||
            path.startsWith('/company/team-users') ||
            path.startsWith('/company/workspace-groups') ||
            path.startsWith('/company/subscription') ||
            path.startsWith('/company/branding')) {
          return '/workspace/$activeWorkspaceKey/modules/remedials/projects';
        }

        final installationAllowed =
            path.startsWith('/modules/installation') ||
            path.startsWith('/installation') ||
          (path.startsWith('/workspace/') &&
            (path.contains('/modules/installation') || path.contains('/installation/')));
        final remedialsAllowed =
            path.startsWith('/modules/remedials') ||
            path.startsWith('/remedials') ||
          (path.startsWith('/workspace/') &&
            (path.contains('/modules/remedials') || path.contains('/remedials/')));
        final blockedWorkspaceForWorker = path.startsWith('/workspace/') && !installationAllowed && !remedialsAllowed;
        final blockedForWorker = path.startsWith('/manager') ||
            path.startsWith('/modules/inspection') ||
            path.startsWith('/inspections') ||
            blockedWorkspaceForWorker ||
            path.startsWith('/modules/preinstall') ||
            path.startsWith('/preinstall');
        if (!installationAllowed && !remedialsAllowed && blockedForWorker) {
          return '/workspace/$activeWorkspaceKey/modules/remedials/projects';
        }
        if (path.contains('/review')) {
          final surveyId = state.pathParameters['surveyId'];
          final doorId = state.pathParameters['doorId'];
          final itemId = state.pathParameters['itemId'];
          if (surveyId != null &&
              doorId != null &&
              (path.startsWith('/remedials/') || path.contains('/remedials/'))) {
            return '/remedials/$surveyId/doors/$doorId';
          }
          if (surveyId != null &&
              itemId != null &&
              (path.startsWith('/installation/') || path.contains('/installation/'))) {
            return '/installation/$surveyId/items/$itemId';
          }
          return '/workspace/$activeWorkspaceKey/modules/remedials/projects';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (c, s) => const ForgotPasswordScreen()),
      GoRoute(path: '/register', builder: (c, s) => const CustomerRegistrationScreen()),
      GoRoute(path: '/book-services', builder: (c, s) => const BwServiceBookingScreen()),
      GoRoute(
        path: '/invite',
        builder: (c, s) {
          final token = (s.queryParameters['token'] ?? '').trim();
          return AcceptInviteScreen(token: token);
        },
      ),
      GoRoute(
        path: '/invite/:token',
        builder: (c, s) => AcceptInviteScreen(token: s.pathParameters['token']!),
      ),
      GoRoute(path: '/', redirect: (_, __) => '/dashboard'),
      GoRoute(path: '/dashboard', builder: (c, s) => const HomeScreen()),
      GoRoute(path: '/platform/admin', builder: (c, s) => const SuperAdminPanelScreen()),
      GoRoute(path: '/reports', builder: (c, s) => const ReportsScreen()),
      GoRoute(path: '/reports/create', builder: (c, s) => const CreateReportScreen()),
      GoRoute(path: '/account/profile', builder: (c, s) => const MyProfileScreen()),
      GoRoute(path: '/company/settings', builder: (c, s) => const SettingsHomeScreen()),
      GoRoute(path: '/app/preferences', builder: (c, s) => const AppPreferencesScreen()),
      GoRoute(path: '/app/quick-login', builder: (c, s) => const QuickLoginSettingsScreen()),
      GoRoute(path: '/company/team-users', builder: (c, s) => const TeamUsersScreen()),
      GoRoute(path: '/company/workspace-groups', builder: (c, s) => const WorkspaceGroupsScreen()),
      GoRoute(path: '/company/subscription', builder: (c, s) => const SubscriptionScreen()),
      GoRoute(path: '/company/branding', builder: (c, s) => const BrandingScreen()),
      GoRoute(path: '/onboarding/company', builder: (c, s) => const CompanyOnboardingScreen()),
      GoRoute(path: '/info/about-app', builder: (c, s) => const AboutAppScreen()),
      GoRoute(path: '/info/how-it-works', builder: (c, s) => const HowItWorksScreen()),
      GoRoute(path: '/info/terms-conditions', builder: (c, s) => const TermsConditionsScreen()),
      GoRoute(path: '/info/privacy-policy', builder: (c, s) => const PrivacyPolicyScreen()),
      GoRoute(path: '/info/contact-support', builder: (c, s) => const ContactSupportScreen()),
      GoRoute(
        path: '/manager/invites',
        builder: (c, s) => const ManagerInvitesScreen(),
      ),
      GoRoute(
        path: '/company/disclaimer-records',
        builder: (c, s) => const DisclaimerRecordsScreen(),
      ),
      GoRoute(
        path: '/company/disclaimer-records/:acceptanceId',
        builder: (c, s) => DisclaimerRecordScreen(
          acceptanceId: s.pathParameters['acceptanceId']!,
        ),
      ),

      // Workspace landing pages (the 3 top-level buttons)
      GoRoute(path: '/workspace/fire-door', builder: (c, s) => const FireDoorWorkspaceScreen()),
      GoRoute(path: '/workspace/fire-stopping', builder: (c, s) => const FireStoppingWorkspaceScreen()),
      GoRoute(path: '/workspace/snagging', builder: (c, s) => const SnaggingWorkspaceScreen()),

      // Legacy links -> keep compatibility but forward to the active workspace.
      GoRoute(path: '/modules/:module/projects', redirect: (c, s) {
        final module = s.pathParameters['module']!;
        final activeWorkspaceKey = ref.read(settingsControllerProvider).activeWorkspaceKey;
        if (module == 'inspection') {
          return '/workspace/$activeWorkspaceKey/inspection/projects';
        }
        return '/workspace/$activeWorkspaceKey/modules/$module/projects';
      }),
      GoRoute(path: '/inspections/fire-door', redirect: (_, __) => '/workspace/fire-door/inspection/projects'),
      GoRoute(path: '/inspections/fire-stopping', redirect: (_, __) => '/workspace/fire-stopping/inspection/projects'),
      GoRoute(path: '/inspections/snagging', redirect: (_, __) => '/workspace/snagging/inspection/projects'),
      GoRoute(path: '/inspections/fire-door/projects', redirect: (_, __) => '/workspace/fire-door/inspection/projects'),
      GoRoute(path: '/inspections/fire-stopping/projects', redirect: (_, __) => '/workspace/fire-stopping/inspection/projects'),
      GoRoute(path: '/inspections/snagging/projects', redirect: (_, __) => '/workspace/snagging/inspection/projects'),
      GoRoute(
        path: '/inspections/:module/projects/:surveyId/details',
        redirect: (c, s) {
          final module = s.pathParameters['module']!;
          final surveyId = s.pathParameters['surveyId']!;
          return '/workspace/$module/inspection/projects/$surveyId/details';
        },
      ),

      // Workspace inspection routes (restored survey flow)
      GoRoute(
        path: '/workspace/fire-door/inspection/projects',
        builder: (c, s) => const FireDoorProjectsScreen(),
      ),
      GoRoute(
        path: '/workspace/fire-door/inspection/projects/:projectId/details',
        builder: (c, s) => FireDoorProjectDetailsScreen(projectId: s.pathParameters['projectId']!),
      ),
      GoRoute(
        path: '/workspace/fire-door/inspection/projects/:surveyId/doors',
        builder: (c, s) => FireDoorDoorsScreen(surveyId: s.pathParameters['surveyId']!),
      ),
      GoRoute(
        path: '/workspace/fire-door/inspection/projects/:surveyId/doors/:doorId',
        builder: (c, s) => FireDoorDoorDetailScreen(
          surveyId: s.pathParameters['surveyId']!,
          doorId: s.pathParameters['doorId']!,
        ),
      ),

      GoRoute(
        path: '/workspace/fire-stopping/inspection/projects',
        builder: (c, s) => const FireStoppingProjectsScreen(),
      ),
      GoRoute(
        path: '/workspace/fire-stopping/inspection/projects/:projectId/details',
        builder: (c, s) => FireStoppingProjectDetailsScreen(projectId: s.pathParameters['projectId']!),
      ),
      GoRoute(
        path: '/workspace/fire-stopping/inspection/projects/:surveyId/doors',
        builder: (c, s) => FireStoppingDoorsScreen(surveyId: s.pathParameters['surveyId']!),
      ),
      GoRoute(
        path: '/workspace/fire-stopping/inspection/projects/:surveyId/doors/:doorId',
        builder: (c, s) => FireStoppingDoorDetailScreen(
          surveyId: s.pathParameters['surveyId']!,
          doorId: s.pathParameters['doorId']!,
        ),
      ),

      GoRoute(
        path: '/workspace/snagging/inspection/projects',
        builder: (c, s) => const SnaggingProjectsScreen(),
      ),
      GoRoute(
        path: '/workspace/snagging/inspection/projects/:projectId/details',
        builder: (c, s) => SnaggingProjectDetailsScreen(projectId: s.pathParameters['projectId']!),
      ),
      GoRoute(
        path: '/workspace/snagging/inspection/projects/:projectId/items',
        builder: (c, s) => SnaggingIssuesScreen(projectId: s.pathParameters['projectId']!),
      ),
      GoRoute(
        path: '/workspace/snagging/inspection/projects/:projectId/items/:itemId',
        builder: (c, s) => SnaggingIssuesScreen(
          projectId: s.pathParameters['projectId']!,
          issueId: s.pathParameters['itemId']!,
        ),
      ),
      GoRoute(
        path: '/workspace/snagging/verification/projects',
        builder: (c, s) => const SnaggingVerificationScreen(),
      ),
      GoRoute(
        path: '/workspace/snagging/inspection/projects/:surveyId/doors',
        redirect: (c, s) => '/workspace/snagging/inspection/projects/${s.pathParameters['surveyId']!}/items',
      ),
      GoRoute(
        path: '/workspace/snagging/inspection/projects/:surveyId/doors/:doorId',
        redirect: (c, s) => '/workspace/snagging/inspection/projects/${s.pathParameters['surveyId']!}/items/${s.pathParameters['doorId']!}',
      ),

      GoRoute(
        path: '/workspace/:workspace/modules/:module/projects',
        redirect: (c, s) {
          final workspace = s.pathParameters['workspace']!;
          final module = s.pathParameters['module']!;
          if (workspace == 'snagging') {
            if (module == 'inspection') return '/workspace/snagging/inspection/projects';
            if (module == 'verification') return '/workspace/snagging/verification/projects';
            return '/workspace/snagging';
          }
          if (module == 'inspection') {
            return '/workspace/$workspace/inspection/projects';
          }
          return null;
        },
        builder: (c, s) => ModuleProjectsScreen(
          moduleKey: s.pathParameters['module']!,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/workspace/:workspace/modules/:module/projects/:surveyId/details',
        redirect: (c, s) {
          final workspace = s.pathParameters['workspace']!;
          final module = s.pathParameters['module']!;
          final surveyId = s.pathParameters['surveyId']!;
          if (module == 'inspection') {
            return '/workspace/$workspace/inspection/projects/$surveyId/details';
          }
          return null;
        },
        builder: (c, s) => ProjectDetailsScreen(
          surveyId: s.pathParameters['surveyId']!,
          moduleKey: s.pathParameters['module']!,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/workspace/:workspace/inspection/projects/:surveyId/doors',
        redirect: (c, s) {
          final workspace = s.pathParameters['workspace']!;
          final surveyId = s.pathParameters['surveyId']!;
          if (workspace == 'snagging') {
            return '/workspace/snagging/inspection/projects/$surveyId/items';
          }
          return null;
        },
        builder: (c, s) {
          final workspace = s.pathParameters['workspace']!;
          final surveyId = s.pathParameters['surveyId']!;
          if (workspace == 'fire-door') {
            return FireDoorDoorsScreen(surveyId: surveyId);
          }
          if (workspace == 'fire-stopping') {
            return FireStoppingDoorsScreen(surveyId: surveyId);
          }
          return const SnaggingIssuesScreen(projectId: '');
        },
      ),
      GoRoute(
        path: '/workspace/:workspace/inspection/projects/:surveyId/doors/:doorId',
        redirect: (c, s) {
          final workspace = s.pathParameters['workspace']!;
          final surveyId = s.pathParameters['surveyId']!;
          final doorId = s.pathParameters['doorId']!;
          if (workspace == 'snagging') {
            return '/workspace/snagging/inspection/projects/$surveyId/items/$doorId';
          }
          return null;
        },
        builder: (c, s) {
          final workspace = s.pathParameters['workspace']!;
          final surveyId = s.pathParameters['surveyId']!;
          final doorId = s.pathParameters['doorId']!;
          if (workspace == 'fire-door') {
            return FireDoorDoorDetailScreen(surveyId: surveyId, doorId: doorId);
          }
          if (workspace == 'fire-stopping') {
            return FireStoppingDoorDetailScreen(surveyId: surveyId, doorId: doorId);
          }
          return const SnaggingIssuesScreen(projectId: '');
        },
      ),
      GoRoute(
        path: '/workspace/:workspace/remedials/:surveyId/doors',
        builder: (c, s) => RemedialDoorListScreen(
          surveyId: s.pathParameters['surveyId']!,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/workspace/:workspace/remedials/:surveyId/doors/:doorId',
        builder: (c, s) => RemedialDoorDetailScreen(
          surveyId: s.pathParameters['surveyId']!,
          doorId: s.pathParameters['doorId']!,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/workspace/:workspace/remedials/:surveyId/doors/:doorId/review',
        builder: (c, s) => RemedialReviewScreen(
          surveyId: s.pathParameters['surveyId']!,
          doorId: s.pathParameters['doorId']!,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/workspace/:workspace/preinstall/:surveyId/items',
        builder: (c, s) => PreInstallationSurveyBuilderListScreen(
          surveyId: s.pathParameters['surveyId']!,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/workspace/:workspace/preinstall/:surveyId/items/:itemId',
        builder: (c, s) => PreInstallationSurveyBuilderScreen(
          surveyId: s.pathParameters['surveyId']!,
          itemId: s.pathParameters['itemId']!,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/workspace/:workspace/installation/:surveyId/items',
        builder: (c, s) => InstallationItemListScreen(
          surveyId: s.pathParameters['surveyId']!,
          module: InstallationFlowModule.installation,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/workspace/:workspace/installation/:surveyId/items/:itemId',
        builder: (c, s) => InstallationItemScreen(
          surveyId: s.pathParameters['surveyId']!,
          itemId: s.pathParameters['itemId']!,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/workspace/:workspace/installation/:surveyId/items/:itemId/review',
        builder: (c, s) => InstallationItemScreen(
          surveyId: s.pathParameters['surveyId']!,
          itemId: s.pathParameters['itemId']!,
          managerReview: true,
          workspaceKey: s.pathParameters['workspace']!,
        ),
      ),
      GoRoute(
        path: '/remedials/projects',
        builder: (c, s) => const RemedialProjectListScreen(),
      ),
      GoRoute(
        path: '/remedials/:surveyId/doors',
        builder: (c, s) => RemedialDoorListScreen(surveyId: s.pathParameters['surveyId']!),
      ),
      GoRoute(
        path: '/remedials/:surveyId/doors/:doorId',
        builder: (c, s) => RemedialDoorDetailScreen(
          surveyId: s.pathParameters['surveyId']!,
          doorId: s.pathParameters['doorId']!,
        ),
      ),
      GoRoute(
        path: '/remedials/:surveyId/doors/:doorId/review',
        builder: (c, s) => RemedialReviewScreen(
          surveyId: s.pathParameters['surveyId']!,
          doorId: s.pathParameters['doorId']!,
        ),
      ),
      GoRoute(
        path: '/modules/:module/projects/:surveyId/details',
        redirect: (c, s) {
          final module = s.pathParameters['module']!;
          final surveyId = s.pathParameters['surveyId']!;
          final activeWorkspaceKey = ref.read(settingsControllerProvider).activeWorkspaceKey;
          return '/workspace/$activeWorkspaceKey/modules/$module/projects/$surveyId/details';
        },
      ),
      GoRoute(
        path: '/preinstall/:surveyId/items',
        builder: (c, s) => PreInstallationSurveyBuilderListScreen(surveyId: s.pathParameters['surveyId']!),
      ),
      GoRoute(
        path: '/preinstall/:surveyId/items/:itemId',
        builder: (c, s) => PreInstallationSurveyBuilderScreen(
          surveyId: s.pathParameters['surveyId']!,
          itemId: s.pathParameters['itemId']!,
        ),
      ),
      GoRoute(
        path: '/installation/:surveyId/items',
        builder: (c, s) => InstallationItemListScreen(
          surveyId: s.pathParameters['surveyId']!,
          module: InstallationFlowModule.installation,
        ),
      ),
      GoRoute(
        path: '/installation/:surveyId/items/:itemId',
        builder: (c, s) => InstallationItemScreen(
          surveyId: s.pathParameters['surveyId']!,
          itemId: s.pathParameters['itemId']!,
        ),
      ),
      GoRoute(
        path: '/installation/:surveyId/items/:itemId/review',
        builder: (c, s) => InstallationItemScreen(
          surveyId: s.pathParameters['surveyId']!,
          itemId: s.pathParameters['itemId']!,
          managerReview: true,
        ),
      ),

      GoRoute(path: '/surveys', redirect: (_, __) => '/workspace/fire-door/inspection/projects'),
    ],
  );
});