import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/mobile_bottom_navigation_bar.dart';

// ─── Lightweight local prefs model ──────────────────────────────────────────

const _prefsBoxName = 'app_user_prefs_v1';

class _AppPrefs {
  // Appearance
  final int themeMode; // 0=system, 1=light, 2=dark

  // Login
  final bool keepSignedIn;
  final bool biometricEnabled;

  // Media
  final bool savePhotosToGallery;

  // Offline & Sync
  final bool autoSyncOnReconnect;
  final bool showPendingCount;

  // Notifications
  final bool notificationsEnabled;

  const _AppPrefs({
    this.themeMode = 0,
    this.keepSignedIn = true,
    this.biometricEnabled = false,
    this.savePhotosToGallery = false,
    this.autoSyncOnReconnect = true,
    this.showPendingCount = true,
    this.notificationsEnabled = true,
  });

  _AppPrefs copyWith({
    int? themeMode,
    bool? keepSignedIn,
    bool? biometricEnabled,
    bool? savePhotosToGallery,
    bool? autoSyncOnReconnect,
    bool? showPendingCount,
    bool? notificationsEnabled,
  }) {
    return _AppPrefs(
      themeMode: themeMode ?? this.themeMode,
      keepSignedIn: keepSignedIn ?? this.keepSignedIn,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      savePhotosToGallery: savePhotosToGallery ?? this.savePhotosToGallery,
      autoSyncOnReconnect: autoSyncOnReconnect ?? this.autoSyncOnReconnect,
      showPendingCount: showPendingCount ?? this.showPendingCount,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'themeMode': themeMode,
        'keepSignedIn': keepSignedIn,
        'biometricEnabled': biometricEnabled,
        'savePhotosToGallery': savePhotosToGallery,
        'autoSyncOnReconnect': autoSyncOnReconnect,
        'showPendingCount': showPendingCount,
        'notificationsEnabled': notificationsEnabled,
      };

  factory _AppPrefs.fromMap(Map<dynamic, dynamic> m) => _AppPrefs(
        themeMode: (m['themeMode'] as int?) ?? 0,
        keepSignedIn: (m['keepSignedIn'] as bool?) ?? true,
        biometricEnabled: (m['biometricEnabled'] as bool?) ?? false,
        savePhotosToGallery: (m['savePhotosToGallery'] as bool?) ?? false,
        autoSyncOnReconnect: (m['autoSyncOnReconnect'] as bool?) ?? true,
        showPendingCount: (m['showPendingCount'] as bool?) ?? true,
        notificationsEnabled: (m['notificationsEnabled'] as bool?) ?? true,
      );
}

// ─── Riverpod provider ──────────────────────────────────────────────────────

class _AppPrefsNotifier extends StateNotifier<_AppPrefs> {
  _AppPrefsNotifier() : super(const _AppPrefs()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_prefsBoxName);
      final raw = box.get('prefs');
      if (raw is Map) {
        state = _AppPrefs.fromMap(raw);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final box = await Hive.openBox(_prefsBoxName);
      await box.put('prefs', state.toMap());
    } catch (_) {}
  }

  void update(_AppPrefs updated) {
    state = updated;
    _save();
  }
}

final _appPrefsProvider = StateNotifierProvider<_AppPrefsNotifier, _AppPrefs>(
    (_) => _AppPrefsNotifier());

// ─── Screen ─────────────────────────────────────────────────────────────────

class AppPreferencesScreen extends ConsumerWidget {
  const AppPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showMobileBottomNav = shouldShowMobileBottomNavigation(context);
    final prefs = ref.watch(_appPrefsProvider);
    final ctrl = ref.read(_appPrefsProvider.notifier);

    void set(_AppPrefs updated) => ctrl.update(updated);

    const headerStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 12,
      color: Color(0xFF607D9B),
      letterSpacing: 0.8,
    );

    Widget sectionHeader(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(label.toUpperCase(), style: headerStyle),
        );

    Widget switchTile({
      required IconData icon,
      required String title,
      String? subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return SwitchListTile(
        secondary: Icon(icon, color: const Color(0xFF4A6080)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: const TextStyle(color: Colors.black54, fontSize: 12))
            : null,
        value: value,
        onChanged: onChanged,
        dense: true,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Settings'),
      ),
      drawer: const AppDrawer(currentRoute: '/app/preferences'),
      bottomNavigationBar:
          showMobileBottomNav ? const MobileBottomNavigationBar() : null,
      body: ListView(
        children: [
          // ── Appearance ────────────────────────────────────────────────
          sectionHeader('Appearance'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                RadioListTile<int>(
                  secondary: const Icon(Icons.brightness_auto_outlined,
                      color: Color(0xFF4A6080)),
                  title: const Text('System default',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  value: 0,
                  groupValue: prefs.themeMode,
                  onChanged: (v) => set(prefs.copyWith(themeMode: v)),
                  dense: true,
                ),
                RadioListTile<int>(
                  secondary: const Icon(Icons.light_mode_outlined,
                      color: Color(0xFF4A6080)),
                  title: const Text('Light',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  value: 1,
                  groupValue: prefs.themeMode,
                  onChanged: (v) => set(prefs.copyWith(themeMode: v)),
                  dense: true,
                ),
                RadioListTile<int>(
                  secondary: const Icon(Icons.dark_mode_outlined,
                      color: Color(0xFF4A6080)),
                  title: const Text('Dark',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  value: 2,
                  groupValue: prefs.themeMode,
                  onChanged: (v) => set(prefs.copyWith(themeMode: v)),
                  dense: true,
                ),
              ],
            ),
          ),

          // ── Login Preferences ─────────────────────────────────────────
          sectionHeader('Login Preferences'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                switchTile(
                  icon: Icons.stay_current_portrait_outlined,
                  title: 'Keep me signed in',
                  subtitle: 'Stay logged in between app sessions.',
                  value: prefs.keepSignedIn,
                  onChanged: (v) => set(prefs.copyWith(keepSignedIn: v)),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading:
                      const Icon(Icons.lock_outline, color: Color(0xFF4A6080)),
                  title: const Text(
                    'Quick Login & Security',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Enable biometric login, set/change 4-digit PIN, or disable quick login.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/app/quick-login'),
                ),
              ],
            ),
          ),

          // ── Media Handling ────────────────────────────────────────────
          sectionHeader('Media Handling'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                switchTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Save photos to device gallery',
                  subtitle:
                      'Photos taken in the app will also be saved to your gallery.',
                  value: prefs.savePhotosToGallery,
                  onChanged: (v) => set(prefs.copyWith(savePhotosToGallery: v)),
                ),
              ],
            ),
          ),

          // ── Offline & Sync ────────────────────────────────────────────
          sectionHeader('Offline & Sync'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                switchTile(
                  icon: Icons.sync_outlined,
                  title: 'Auto-sync when connection returns',
                  subtitle:
                      'Automatically upload pending data when back online.',
                  value: prefs.autoSyncOnReconnect,
                  onChanged: (v) => set(prefs.copyWith(autoSyncOnReconnect: v)),
                ),
                const Divider(height: 1, indent: 56),
                switchTile(
                  icon: Icons.upload_outlined,
                  title: 'Show pending uploads count',
                  subtitle:
                      'Display a badge when there are items waiting to upload.',
                  value: prefs.showPendingCount,
                  onChanged: (v) => set(prefs.copyWith(showPendingCount: v)),
                ),
              ],
            ),
          ),

          // ── Notifications ─────────────────────────────────────────────
          sectionHeader('Notifications'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: switchTile(
              icon: Icons.notifications_outlined,
              title: 'Enable notifications',
              subtitle:
                  'Receive app notifications for assignments and updates.',
              value: prefs.notificationsEnabled,
              onChanged: (v) => set(prefs.copyWith(notificationsEnabled: v)),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
