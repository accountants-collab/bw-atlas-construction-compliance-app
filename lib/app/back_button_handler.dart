import 'package:flutter/material.dart';

/// Helper to detect if current route is a root-level screen that should show exit confirmation.
bool isRootScreen(String location) {
  // Root/main screens where back should show exit confirmation
  final rootRoutes = [
    '/dashboard',
    '/app/preferences',
    '/login',
    '/register',
    '/book-services',
  ];

  // Check if it's a login/auth screen or dashboard-level
  for (final route in rootRoutes) {
    if (location == route || location.startsWith(route)) {
      return true;
    }
  }

  // Also root workspace level (not deep project/item screens)
  if (location == '/' || location.isEmpty) {
    return true;
  }

  return false;
}

/// Handles Android back button press with confirmation on root screens.
/// Call this from PopScope.onPopInvokedWithResult to handle back button behavior.
Future<bool> handleBackButtonPress({
  required BuildContext context,
  required bool didPop,
  required String currentLocation,
}) async {
  if (didPop) {
    return true; // Already popped, allow
  }

  // If not a root screen, allow normal back navigation (let GoRouter handle it)
  if (!isRootScreen(currentLocation)) {
    return true; // Allow pop
  }

  // On root screen, show "press again to exit" pattern
  // Note: Store last press time in a static or provider for this implementation
  // For now, just return false to prevent exit - GoRouter will handle the back
  return false;
}
