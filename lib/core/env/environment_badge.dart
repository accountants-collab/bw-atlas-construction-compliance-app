import 'package:flutter/material.dart';

import 'app_environment.dart';

class EnvironmentBadge extends StatelessWidget {
  final EdgeInsetsGeometry? margin;

  const EnvironmentBadge({super.key, this.margin});

  @override
  Widget build(BuildContext context) {
    final env = AppEnvironmentRuntime.current;
    if (!env.showEnvironmentBadge) {
      return const SizedBox.shrink();
    }

    final label = env.isStaging
        ? 'STAGING'
        : (env.isDevelopment ? 'DEVELOPMENT' : 'PRODUCTION');

    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF57C00)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFFE65100),
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
