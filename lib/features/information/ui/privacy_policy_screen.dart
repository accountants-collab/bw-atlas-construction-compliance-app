import 'package:flutter/material.dart';

import '../../../app/app_drawer.dart';
import '../content/info_content.dart';
import 'widgets/info_page_scaffold.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const InfoPageScaffold(
      drawer: AppDrawer(currentRoute: '/info/privacy-policy'),
      content: privacyPolicyContent,
    );
  }
}
