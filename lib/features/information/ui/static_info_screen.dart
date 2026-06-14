import 'package:flutter/material.dart';

import '../../../app/app_drawer.dart';

class StaticInfoScreen extends StatelessWidget {
  final String routeKey;

  const StaticInfoScreen({
    super.key,
    required this.routeKey,
  });

  @override
  Widget build(BuildContext context) {
    final data = _content(routeKey);
    return Scaffold(
      appBar: AppBar(title: Text(data.title)),
      drawer: AppDrawer(currentRoute: '/info/$routeKey'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          data.body,
          style: const TextStyle(height: 1.5, fontSize: 16),
        ),
      ),
    );
  }

  _InfoData _content(String key) {
    switch (key) {
      case 'about':
        return const _InfoData(
          title: 'About',
          body:
              'This app helps fire door inspectors and teams manage surveys, compliance checks, reports, and records efficiently.',
        );
      case 'how-it-works':
        return const _InfoData(
          title: 'How It Works',
          body:
              '1. Create a report.\n'
              '2. Add door inspections with pass/fail checks.\n'
              '3. Upload photos and notes.\n'
              '4. Export or share report.',
        );
      case 'terms':
        return const _InfoData(
          title: 'Terms & Conditions',
          body:
              'Use of this app is subject to your company compliance and safety standards. You are responsible for data accuracy and lawful use.',
        );
      case 'privacy':
        return const _InfoData(
          title: 'Privacy Policy',
          body:
              'We collect only operational data needed for inspections and reports. We do not sell your data. Contact us for deletion/export requests.',
        );
      case 'contact':
        return const _InfoData(
          title: 'Contact Us',
          body: 'Email support: support@bwfiredoors.com',
        );
      default:
        return const _InfoData(title: 'Information', body: 'No content available.');
    }
  }
}

class _InfoData {
  final String title;
  final String body;

  const _InfoData({required this.title, required this.body});
}
