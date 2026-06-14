import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui/branding_resolver.dart';

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Disclaimer')),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset(kDefaultSystemLogoAssetPath, height: 90),
              ),
              const SizedBox(height: 20),
              const Text(
                'Please read and accept this disclaimer before proceeding.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'This app is provided "as is" without warranties of any kind.\n'
                'You are responsible for verifying outputs and ensuring compliance with applicable standards.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () =>
                      context.go('/workspace/fire-door/inspection/projects'),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
