import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connectivity_provider.dart';

/// A compact chip shown in AppBar actions to indicate network status.
/// Shows nothing when online (clean UI), a badge when offline or checking.
class ConnectivityBadge extends ConsumerWidget {
  const ConnectivityBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityProvider);

    switch (status) {
      case ConnectivityStatus.online:
        // Silent when connected — no noise needed.
        return const SizedBox.shrink();
      case ConnectivityStatus.checking:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white70,
                ),
              ),
              SizedBox(width: 5),
              Text(
                'Connecting…',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        );
      case ConnectivityStatus.offline:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFC62828),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, size: 13, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// A full-width banner for screens that want a more prominent offline notice.
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityProvider);
    if (status != ConnectivityStatus.offline) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: const Color(0xFFC62828),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, size: 14, color: Colors.white),
          SizedBox(width: 8),
          Text(
            'You are offline. Changes will sync when the connection returns.',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
