import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../core/env/app_environment.dart';
import '../features/notifications/state/notification_navigation_controller.dart';
import '../features/notifications/state/push_notification_service.dart';
import 'router.dart';

class FDApp extends ConsumerWidget {
  const FDApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final env = AppEnvironmentRuntime.current;
    final auth = ref.watch(authControllerProvider);

    if (auth.isLoggedIn) {
      unawaited(ref.read(pushNotificationServiceProvider).initializeForCurrentUser());
    }

    ref.listen<NotificationNavigationRequest?>(notificationNavigationControllerProvider, (previous, next) {
      if (next == null) return;
      if (next.notificationId.isNotEmpty) {
        unawaited(
          ref.read(workflowNotificationRepositoryProvider).markRead(
                companyId: next.companyId,
                notificationId: next.notificationId,
              ),
        );
      }
      router.go(next.route);
      ref.read(notificationNavigationControllerProvider.notifier).clear();
    });

    return MaterialApp.router(
      debugShowCheckedModeBanner: env.verboseLogging,
      title: env.appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: IconThemeData(color: Colors.white),
          actionsIconTheme: IconThemeData(color: Colors.white),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFFF5F9FF),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shadowColor: const Color(0x1A000000),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFDDE5F0)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          isDense: false,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          border: OutlineInputBorder(),
        ),
        listTileTheme: const ListTileThemeData(
          minVerticalPadding: 10,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            backgroundColor: Color(0xFF1565C0),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: Color(0xFF1565C0),
            side: BorderSide(color: Color(0xFF1565C0)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: Color(0xFF1565C0),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}