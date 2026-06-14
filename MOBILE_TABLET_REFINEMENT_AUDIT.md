# Mobile and Tablet Refinement Audit

Date: 2026-05-04
Branch: mobile-refinement-pass
Backup commit: c616a14

## Scope and constraints

- Keep existing web behavior working.
- Do not redesign business logic, Firebase data, roles, reports, or workflows.
- Separate layout and navigation concerns from business logic in small steps.
- Android and iOS should share a mobile-first shell where safe.
- Tablet should get a dedicated adaptive layout, not the current desktop-like web shell.

## Current architecture summary

### 1. App and navigation ownership

- `lib/app/app.dart`
  - Owns `MaterialApp.router`.
  - Initializes push notifications after login.
  - Handles notification-driven route navigation and marks notifications as read when opened.

- `lib/app/router.dart`
  - Single source of truth for app routes.
  - Owns auth redirect behavior and most role-based route restrictions.
  - Currently blocks workers from inspection, manager, and preinstall surfaces, but still leaves several UI entry points to company setup/settings available outside router-level hardening.

### 2. Platform-specific layout split today

- Web/mobile split exists and is mostly controlled inline by screen widgets using `kIsWeb`.
- There is no dedicated Android shell and no dedicated iOS shell.
- There is no shared mobile shell with bottom navigation.
- Tablet behavior is local and inconsistent, mostly width checks inside individual screens.

Primary files controlling layout split:

- `lib/features/workspaces/ui/module_web_shell_scaffold.dart`
- `lib/features/workspaces/ui/module_web_top_navigation.dart`
- `lib/features/fire_door/ui/fire_door_web_shell_scaffold.dart`
- `lib/features/home/ui/app_home_web_top_navigation.dart`
- `lib/features/home/home_screen.dart`
- `lib/app/ui/workspace_switch_cards_bar.dart`
- `lib/app/ui/workspace_quick_access_menu.dart`
- `lib/features/workspaces/ui/inspection_workspace_screen.dart`

### 3. Tablet handling today

Tablet responsiveness is not centralized. It is handled case by case with `MediaQuery` and `LayoutBuilder`.

Representative files:

- `lib/features/surveys/ui/survey_list_screen.dart`
- `lib/features/surveys/ui/project_details_screen.dart`
- `lib/features/surveys/ui/door_detail_screen.dart`

### 4. Shared navigation/header/footer logic

- Web header and workflow navigation are shared via:
  - `lib/features/workspaces/ui/module_web_top_navigation.dart`
  - `lib/features/home/ui/app_home_web_top_navigation.dart`

- Mobile header behavior is not centralized. Most screens build their own `AppBar`, often with:
  - `WorkspaceSwitchCardsBar`
  - `AppDrawer`
  - screen-local actions

- There is no shared mobile footer or bottom tab architecture today.

## Audit by requested area

### A. Platform-specific UI structure

Findings:

- The app can be changed for Android/iOS without breaking web because web layout is already isolated through `kIsWeb` and the web shell widgets.
- The main risk is that many feature screens currently branch inline between web and non-web; a broad refactor can easily regress route context, headers, and actions.
- The safest approach is to introduce a mobile/tablet shell layer and migrate entry screens first, while leaving web shell files untouched.

Files most relevant for shell introduction:

- `lib/app/app.dart`
- `lib/app/router.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/workspaces/ui/inspection_workspace_screen.dart`
- `lib/features/modules/ui/module_projects_screen.dart`
- `lib/features/fire_door/ui/fire_door_module_projects_screen.dart`
- `lib/features/fire_stopping/ui/fire_stopping_module_projects_screen.dart`

### B. Mobile bottom navigation

Findings:

- No bottom navigation exists today.
- Current mobile navigation relies on drawer + per-screen app bar + workspace switch bar.
- Home and workspace/module surfaces are the safest first insertion points for a mobile bottom tab shell.

Safe insertion candidates:

- `lib/features/home/home_screen.dart`
- `lib/features/workspaces/ui/inspection_workspace_screen.dart`
- `lib/features/modules/ui/module_projects_screen.dart`
- new shared files under `lib/app/ui/` or `lib/features/workspaces/ui/` for mobile shell and tab model

Recommendation:

- Introduce a mobile shell only for non-web.
- Keep `GoRouter` routes unchanged initially.
- Use shell tabs as route shortcuts, not as a router rewrite in phase 3.

### C. Worker role flow and company setup leak

Findings:

- Worker restrictions exist in `lib/app/router.dart` and `lib/features/modules/ui/module_projects_screen.dart`.
- However, onboarding/company setup gating is still reused in manager-oriented flows through `routeWithCompanyGate` and `resolveRoute` helpers, which is a risk for worker UX.
- `InspectionWorkspaceScreen` still wraps worker destinations in company setup gating.
- `HomeScreen` still uses onboarding gating for workspace option resolution.
- `CompanyOnboardingScreen` is manager/company-detail oriented and should never be a worker detour.

Primary risk files:

- `lib/app/router.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/workspaces/ui/inspection_workspace_screen.dart`
- `lib/features/onboarding/ui/company_onboarding_screen.dart`
- `lib/features/settings/ui/subscription_screen.dart`
- `lib/features/settings/ui/settings_home_screen.dart`
- `lib/features/settings/ui/team_users_screen.dart`
- `lib/features/settings/ui/workspace_groups_screen.dart`

Required direction:

- Workers should never be routed to company onboarding.
- Workers should land directly on assigned remedials/installations/tasks.
- Route and UI entry points both need hardening.

### D. Logout bug

Findings:

- `AuthController.logout()` unregisters push token and calls `AuthService.logout()`.
- `AuthService.logout()` signs out Firebase and deletes only `_authSessionKey`.
- It does not clear `_rememberMeKey` or `_rememberedEmailKey`.
- Router redirect should send logged-out users to `/login`, but some mobile screens call logout without immediately navigating.
- Web menus already do `context.go('/login')` after logout; mobile home does not.

Primary files:

- `lib/auth/auth_state.dart`
- `lib/auth/auth_service.dart`
- `lib/auth/firebase_auth_repository.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/home/ui/app_home_web_top_navigation.dart`
- `lib/features/workspaces/ui/module_web_top_navigation.dart`

Risk:

- Mobile can appear authenticated until router refresh/redirect settles.
- Remember-me state can survive manual logout unintentionally.

### E. Camera-first photo UX

Findings:

- Camera support already exists in several feature screens through `image_picker`.
- Gallery/file upload is also present through `file_picker`.
- Photo actions are implemented screen by screen, not via a shared mobile photo action component.
- No centralized camera permission UX was found.

Primary implementation surfaces:

- `lib/features/fire_door/ui/fire_door_door_detail_full_screen.dart`
- `lib/features/fire_stopping/ui/fire_stopping_door_detail_full_screen.dart`
- `lib/features/remedials/ui/remedial_door_detail_screen.dart`
- `lib/features/installation/ui/installation_item_screen.dart`
- `lib/features/preinstall/ui/preinstallation_survey_builder_screen.dart`
- `lib/features/surveys/ui/door_detail_screen.dart`
- `lib/features/surveys/ui/door_inspection_screen.dart` (legacy)

Risk:

- Because photo entry is duplicated, camera-first changes should be applied through a shared action sheet/widget before sweeping screen-by-screen rewrites.

### F. PDF download on device

Findings:

- Web download is implemented with web-only helpers.
- Mobile currently uses `Printing.layoutPdf` and `Printing.sharePdf` in many places.
- There is no shared Android/iOS file-save helper for PDFs.

Primary implementation surfaces:

- `lib/features/surveys/ui/doors_screen.dart`
- `lib/features/fire_door/ui/fire_door_doors_full_screen.dart`
- `lib/features/fire_stopping/ui/fire_stopping_doors_full_screen.dart`
- `lib/features/fire_door/ui/fire_door_door_detail_full_screen.dart`
- `lib/features/fire_stopping/ui/fire_stopping_door_detail_full_screen.dart`
- `lib/features/preinstall/ui/preinstallation_survey_builder_screen.dart`
- `lib/features/remedials/ui/remedial_review_screen.dart`
- `lib/features/disclaimer/ui/disclaimer_record_screen.dart`
- `lib/features/disclaimer/ui/disclaimer_acceptance_section.dart`
- `lib/features/surveys/pdf/web_download.dart`
- `lib/features/surveys/pdf/web_download_stub.dart`

Risk:

- A direct replacement of current export behavior would break web.
- Safe path is a new mobile-only save helper plus explicit `Download PDF` button in shared export sheets.

### G. Biometric / PIN quick login

Findings:

- No biometric or PIN quick login exists today.
- No `local_auth` or secure storage implementation was found.
- Current persistence is based on Hive auth session and remember-me email.
- The best control surface is profile/preferences, not the raw login screen.

Likely integration points:

- `lib/auth/login_screen.dart`
- `lib/auth/auth_state.dart`
- `lib/auth/auth_service.dart`
- `lib/features/account/ui/my_profile_screen.dart`
- `lib/features/settings/ui/app_preferences_screen.dart`
- `lib/features/settings/state/settings_controller.dart`

Risk:

- Quick login must not substitute Firebase auth.
- It should only unlock a previously restored authenticated context or a securely stored re-auth path.
- This phase needs new dependencies and careful secure-storage design.

### H. Module consistency

Findings:

- Fire Door, Fire Stopping, and Snagging reuse some patterns but still have duplicated UI flows.
- Common user journey elements exist across modules, but components are not consistently shared.
- Web shell reuse already crosses module boundaries, which is good for consistency but must remain web-only.

Primary consistency surfaces:

- project setup/detail screens
- drawing upload/view
- disclaimer UI
- group assignment UI
- photo action UI
- approval/rejection UI
- PDF export action UI

Key files:

- `lib/features/fire_door/ui/fire_door_project_details_full_screen.dart`
- `lib/features/fire_stopping/ui/fire_stopping_project_details_full_screen.dart`
- `lib/features/snagging/ui/snagging_project_details_screen.dart`
- `lib/features/remedials/ui/remedial_door_detail_screen.dart`
- `lib/features/remedials/ui/remedial_review_screen.dart`
- `lib/features/installation/ui/installation_item_screen.dart`
- `lib/features/disclaimer/ui/disclaimer_acceptance_section.dart`

### I. PDF visual consistency

Findings:

- The survey PDF system already has a defined visual language in `survey_pdf.dart`.
- Module-specific PDFs likely diverged over time and need header/footer/component alignment rather than a rebuild.

Primary files:

- `lib/features/surveys/pdf/survey_pdf.dart`
- `lib/features/fire_stopping/inspection/pdf/survey_pdf.dart`
- `lib/features/fire_door/inspection/pdf/survey_pdf.dart`
- `lib/features/snagging/pdf/snagging_pdf_builder.dart`
- `lib/features/remedials/pdf/remedial_pdf.dart`
- `lib/features/installation/pdf/installation_pdf.dart`
- `lib/features/preinstall/pdf/preinstall_pdf.dart`

### J. Notifications and task visibility

Findings:

- Remote notifications are stored under company-scoped Firestore collections.
- Opening a notification marks it as read but does not itself remove the task from local lists.
- Bell summaries combine remote notifications with live state-derived actionable items.
- Task visibility is driven by survey/project state and group access, not by read/unread notification status.

Primary files:

- `lib/features/notifications/data/workflow_notification_repository.dart`
- `lib/features/notifications/state/workflow_event_dispatcher.dart`
- `lib/features/notifications/state/push_notification_service.dart`
- `lib/features/notifications/state/workflow_notifications_provider.dart`
- `lib/features/workspaces/state/header_notifications_provider.dart`
- `lib/app/app.dart`

Risk:

- Notification routes and worker list filters are distributed across modules.
- Phase 7 should include a focused regression pass to confirm notification-open does not hide tasks.

## Main risks

1. UI logic is distributed across many feature screens, so broad edits can regress route context, role gating, or screen titles.
2. Worker gating exists in both router and screen layers; changing only one layer will leave leaks.
3. Logout behavior mixes Firebase state, Hive session state, remember-me flags, and route transitions.
4. Photo capture and PDF export flows are duplicated; they need shared mobile helpers before UX refinement.
5. Quick login introduces security-sensitive storage and should be isolated behind a new service layer.
6. Tablet behavior is currently local; an aggressive shell rewrite would risk web regressions.

## Recommended implementation phases

### Phase 1: Backup and audit only

- Completed:
  - branch `mobile-refinement-pass`
  - backup commit `c616a14`
  - this audit document

Validation:

- run `flutter analyze`

### Phase 2: Logout fix and worker role access fix

Goals:

- Make logout deterministic on Android/iOS and keep web intact.
- Prevent workers from being routed into onboarding, company setup, billing, or team management.

Expected file set:

- `lib/auth/auth_state.dart`
- `lib/auth/auth_service.dart`
- `lib/app/router.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/workspaces/ui/inspection_workspace_screen.dart`
- possible worker-safe helper under `lib/app/` or `lib/auth/`

Validation:

- `flutter analyze`
- auth/logout tests if available
- manual login/logout on Android

### Phase 3: Mobile bottom navigation

Goals:

- Add non-web mobile shell with role-aware bottom tabs.
- Keep web shell untouched.
- Treat tablet separately from phone.

Expected file set:

- new mobile shell files under `lib/app/ui/` or `lib/features/workspaces/ui/`
- `lib/features/home/home_screen.dart`
- `lib/features/workspaces/ui/inspection_workspace_screen.dart`
- `lib/features/modules/ui/module_projects_screen.dart`
- limited route helpers if needed

Validation:

- `flutter analyze`
- role-based smoke check for owner/manager/worker

### Phase 4: Camera-first photo handling

Goals:

- Standardize a mobile-first photo action pattern.
- Default to `Take Photo` on Android/iOS.
- Preserve gallery/file upload as secondary.
- Add clear permission-denied messaging.

Expected file set:

- new shared photo action helper/service
- targeted feature screens for fire door, fire stopping, remedials, installation, preinstall, snagging
- Android and iOS permission config if missing

Validation:

- `flutter analyze`
- device test for camera, denied permissions, gallery fallback

### Phase 5: PDF download on Android/iOS

Goals:

- Add device save flow for PDF files.
- Keep existing web download and share flows.

Expected file set:

- new mobile PDF save helper/service
- export action sheets in affected modules
- platform permission/config only if required by chosen storage path

Validation:

- `flutter analyze`
- device save/share test on Android and iOS

### Phase 6: Biometric and PIN quick login

Goals:

- Add secure quick-login settings and login unlock flow.
- Disable or invalidate quick login on manual logout.

Expected file set:

- auth service/controller
- login screen
- profile/preferences screens
- secure storage and local auth integration files
- dependency updates in `pubspec.yaml`

Validation:

- `flutter analyze`
- unit tests for quick-login state if feasible
- device biometric/PIN tests

### Phase 7: Module consistency cleanup

Goals:

- Reuse safe UI components across Fire Door, Fire Stopping, and Snagging.
- Align common mobile workflows without merging module business logic.

Expected file set:

- shared action widgets
- shared project header/section widgets
- module screens with duplicated mobile interaction patterns

Validation:

- `flutter analyze`
- targeted workflow smoke tests by module

### Phase 8: PDF visual consistency

Goals:

- Align PDF headers, branding blocks, signature sections, colour language, and spacing.
- Preserve module-specific content.

Expected file set:

- module PDF builders
- shared PDF style helpers if extracted safely

Validation:

- `flutter analyze`
- generate sample PDFs from each module and compare visually

## Recommended order of execution

1. Phase 2 first because it removes real user blockers and reduces routing noise before UX work.
2. Phase 3 next because bottom navigation depends on correct worker gating and logout behavior.
3. Phase 4 and Phase 5 after shell stabilization.
4. Phase 6 only after auth/logout behavior is deterministic.
5. Phase 7 and Phase 8 last, because they are cleanup and consistency phases rather than blockers.

## Definition of done for Phase 2

- Worker cannot reach onboarding/company setup/billing/team routes from app UI or router redirects.
- Mobile logout signs out Firebase, clears remembered authenticated session state correctly, and returns to login immediately.
- Web logout remains unchanged.
- `flutter analyze` passes with no new issues introduced by the phase.