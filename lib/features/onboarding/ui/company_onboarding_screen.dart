import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_controller.dart';

class CompanyOnboardingScreen extends ConsumerStatefulWidget {
  const CompanyOnboardingScreen({super.key});

  @override
  ConsumerState<CompanyOnboardingScreen> createState() =>
      _CompanyOnboardingScreenState();
}

class _CompanyOnboardingScreenState
    extends ConsumerState<CompanyOnboardingScreen> {
  final _name = TextEditingController();
  final _trading = TextEditingController();
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _cityTown = TextEditingController();
  final _postCode = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  String? _seededWorkspaceKey;

  String _returnTo(BuildContext context) {
    final raw =
        GoRouterState.of(context).queryParameters['returnTo']?.trim() ?? '';
    return raw.isEmpty ? '/dashboard' : raw;
  }

  bool _looksLikePdf(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  @override
  void dispose() {
    _name.dispose();
    _trading.dispose();
    _addressLine1.dispose();
    _addressLine2.dispose();
    _cityTown.dispose();
    _postCode.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  List<String> _validateCompanyFields() {
    final missing = <String>[];
    if (_addressLine1.text.trim().isEmpty) missing.add('Address line 1');
    if (_cityTown.text.trim().isEmpty) missing.add('City / Town');
    if (_postCode.text.trim().isEmpty) missing.add('Post code');
    if (_email.text.trim().isEmpty) {
      missing.add('Company Email (Step 1)');
    } else if (!_isValidEmail(_email.text)) {
      missing.add('Valid Company Email (Step 1)');
    }
    if (_phone.text.trim().isEmpty) missing.add('Phone');
    return missing;
  }

  bool _isValidEmail(String email) {
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(email.trim());
  }

  void _seedCompanyFieldsIfNeeded(AppSettings settings) {
    final workspaceKey = settings.activeWorkspaceKey;
    if (_seededWorkspaceKey == workspaceKey) return;
    _seededWorkspaceKey = workspaceKey;

    final profile =
        hasCompletedCompanySetup(settings, workspaceKey: workspaceKey)
            ? settings.companyProfile
            : CompanyProfile(companyId: settings.companyProfile.companyId);
    _name.text = profile.companyName;
    _trading.text = profile.tradingName;
    _addressLine1.text = profile.addressLine1;
    _addressLine2.text = profile.addressLine2;
    _cityTown.text = profile.cityTown;
    _postCode.text = profile.postCode;
    _email.text = profile.email;
    _phone.text = profile.phone;
  }

  Future<void> _saveCompanyDraft({
    required SettingsController ctrl,
    required AppSettings settings,
  }) async {
    final missing = _validateCompanyFields();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please complete: ${missing.join(', ')}')),
      );
      return;
    }

    final existingCompanyId =
        settings.companyProfile.companyId.trim().isNotEmpty
            ? settings.companyProfile.companyId.trim()
            : settings.activeCompanyId.trim();

    ctrl.updateCompanyProfile(
      companyId: existingCompanyId,
      companyName: _name.text,
      tradingName: _trading.text,
      address: [
        _addressLine1.text,
        _addressLine2.text,
        _cityTown.text,
        _postCode.text,
      ].where((p) => p.trim().isNotEmpty).join(', '),
      addressLine1: _addressLine1.text,
      addressLine2: _addressLine2.text,
      cityTown: _cityTown.text,
      postCode: _postCode.text,
      email: _email.text,
      phone: _phone.text,
    );
    await ctrl.flushSharedSettingsNow();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Company profile saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.watch(settingsControllerProvider.notifier);
    final activeLogo = getActiveLogo(settings.companyProfile);

    final returnTo = _returnTo(context);
    final mode = (GoRouterState.of(context).queryParameters['mode'] ?? '')
        .trim()
        .toLowerCase();
    final workspaceFromReturn = returnTo.contains('/workspace/fire-stopping')
        ? 'fire-stopping'
        : (returnTo.contains('/workspace/snagging') ? 'snagging' : 'fire-door');
    final isFireStoppingJobDetails =
        workspaceFromReturn == 'fire-stopping' && mode != 'company';
    if (settings.activeWorkspaceKey != workspaceFromReturn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(settingsControllerProvider.notifier)
            .setActiveWorkspace(workspaceFromReturn);
      });
    }

    _seedCompanyFieldsIfNeeded(settings);

    Future<void> pickLogo() async {
      final result = await FilePicker.platform.pickFiles(
        type: isFireStoppingJobDetails ? FileType.custom : FileType.image,
        allowedExtensions: isFireStoppingJobDetails
            ? ['pdf', 'png', 'jpg', 'jpeg', 'webp']
            : null,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      ctrl.setCompanyLogo(bytes.toList());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isFireStoppingJobDetails
            ? 'Project Details'
            : 'Set Up Company Details'),
        bottom:
            WorkspaceSwitchCardsBar(currentWorkspaceKey: workspaceFromReturn),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.go(returnTo),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: 'Home',
            onPressed: () => context.go('/dashboard'),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionCard(
            title: isFireStoppingJobDetails
                ? 'Project Details'
                : 'Company Details',
            subtitle: isFireStoppingJobDetails
                ? 'Site and client information used for Fire Stopping inspection flow.'
                : 'Business and contact information used in reports.',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;
                final halfWidth = isWide
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;

                Widget wrapField(Widget child) {
                  return SizedBox(width: halfWidth, child: child);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        wrapField(
                          TextField(
                            controller: _name,
                            decoration: InputDecoration(
                              labelText: isFireStoppingJobDetails
                                  ? 'Client'
                                  : 'Company Name',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        wrapField(
                          TextField(
                            controller: _trading,
                            decoration: InputDecoration(
                              labelText: isFireStoppingJobDetails
                                  ? 'Block / Building'
                                  : 'Trading Name',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        wrapField(
                          TextField(
                            controller: _addressLine1,
                            decoration: InputDecoration(
                              labelText: isFireStoppingJobDetails
                                  ? 'Site Address'
                                  : 'Address line 1',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        wrapField(
                          TextField(
                            controller: _addressLine2,
                            decoration: InputDecoration(
                              labelText: isFireStoppingJobDetails
                                  ? 'Site Address (line 2)'
                                  : 'Address line 2',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        wrapField(
                          TextField(
                            controller: _cityTown,
                            decoration: InputDecoration(
                              labelText: isFireStoppingJobDetails
                                  ? 'Floor / Level'
                                  : 'City / Town',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        wrapField(
                          TextField(
                            controller: _postCode,
                            decoration: InputDecoration(
                              labelText: isFireStoppingJobDetails
                                  ? 'Post code (optional)'
                                  : 'Post code',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        wrapField(
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: isFireStoppingJobDetails
                                  ? 'Client Email'
                                  : 'Email',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        wrapField(
                          TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: isFireStoppingJobDetails
                                  ? 'Client Phone'
                                  : 'Phone',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _saveCompanyDraft(
                          ctrl: ctrl,
                          settings: settings,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(isFireStoppingJobDetails
                            ? 'Save Project Details'
                            : 'Save Company Details'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          _buildSectionCard(
            title: isFireStoppingJobDetails ? 'Drawing Upload' : 'Logo Upload',
            subtitle: isFireStoppingJobDetails
                ? 'Upload a drawing file used for Fire Stopping project setup.'
                : 'Upload your company logo used in app and reports.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 72,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Center(
                        child: activeLogo.hasCompanyLogo
                            ? (() {
                                final bytes = Uint8List.fromList(
                                    activeLogo.companyLogoBytes);
                                if (isFireStoppingJobDetails &&
                                    _looksLikePdf(bytes)) {
                                  return const Icon(
                                      Icons.picture_as_pdf_outlined,
                                      color: Colors.red,
                                      size: 28);
                                }
                                return Image.memory(
                                  bytes,
                                  height: 50,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.insert_drive_file_outlined,
                                    size: 28,
                                    color: Colors.black54,
                                  ),
                                );
                              })()
                            : Image.asset(activeLogo.fallbackAssetPath,
                                height: 50, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: pickLogo,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: Text(isFireStoppingJobDetails
                                ? 'Upload Drawing'
                                : 'Upload Company Logo'),
                          ),
                          const SizedBox(height: 6),
                          if (!isFireStoppingJobDetails)
                            Text(
                              activeLogo.hasCompanyLogo
                                  ? 'Your custom company logo is currently used across the app and reports.'
                                  : 'No custom logo uploaded. The default BW Atlas logo is currently used across the app and reports.',
                              style: TextStyle(
                                fontSize: 11,
                                color: activeLogo.hasCompanyLogo
                                    ? Colors.green.shade700
                                    : Colors.grey.shade500,
                                height: 1.4,
                              ),
                            ),
                          if (activeLogo.hasCompanyLogo &&
                              isFireStoppingJobDetails)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'PDF drawing uploaded',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Finish button
          FilledButton.icon(
            onPressed: () => _finishOnboarding(
              ctrl: ctrl,
              settings: settings,
              isFireStoppingJobDetails: isFireStoppingJobDetails,
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(isFireStoppingJobDetails
                ? 'Save Project Details'
                : 'Finish Onboarding'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  void _finishOnboarding({
    required SettingsController ctrl,
    required AppSettings settings,
    required bool isFireStoppingJobDetails,
  }) async {
    final missing = _validateCompanyFields();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please complete: ${missing.join(', ')}'),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final existingCompanyId =
        settings.companyProfile.companyId.trim().isNotEmpty
            ? settings.companyProfile.companyId.trim()
            : settings.activeCompanyId.trim();

    // Update company profile
    ctrl.updateCompanyProfile(
      companyId: existingCompanyId,
      companyName: _name.text,
      tradingName: _trading.text,
      address: [
        _addressLine1.text,
        _addressLine2.text,
        _cityTown.text,
        _postCode.text,
      ].where((p) => p.trim().isNotEmpty).join(', '),
      addressLine1: _addressLine1.text,
      addressLine2: _addressLine2.text,
      cityTown: _cityTown.text,
      postCode: _postCode.text,
      email: _email.text,
      phone: _phone.text,
    );

    // Mark onboarding as complete
    ctrl.completeOnboarding();
    await ctrl.flushSharedSettingsNow();
    if (!mounted) return;

    if (isFireStoppingJobDetails) {
      final goTo = await _showNextStepDialog(context);
      if (!mounted) return;
      if (goTo == _NextStep.review) {
        context.go('/workspace/fire-stopping/modules/remedials/projects');
      } else {
        context.go('/workspace/fire-stopping/inspection/projects');
      }
    } else {
      // Return to the workspace/module the user came from.
      context.go(_returnTo(context));
    }

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Company profile saved and onboarding complete.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<_NextStep> _showNextStepDialog(BuildContext context) async {
    final result = await showDialog<_NextStep>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Where would you like to go next?'),
          content:
              const Text('Choose the next area to continue your workflow.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_NextStep.inspection),
              child: const Text('Go to Fire Stopping Inspection'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_NextStep.review),
              child: const Text('Go to Manager Review & Approval'),
            ),
          ],
        );
      },
    );
    return result ?? _NextStep.inspection;
  }
}

enum _NextStep { inspection, review }
