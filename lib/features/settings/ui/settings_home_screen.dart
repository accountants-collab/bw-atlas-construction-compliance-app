import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/branding_resolver.dart';
import '../state/settings_controller.dart';

class SettingsHomeScreen extends ConsumerStatefulWidget {
  const SettingsHomeScreen({super.key});

  @override
  ConsumerState<SettingsHomeScreen> createState() => _SettingsHomeScreenState();
}

class _SettingsHomeScreenState extends ConsumerState<SettingsHomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyId = TextEditingController();
  final _name = TextEditingController();
  final _tradingName = TextEditingController();
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _cityTown = TextEditingController();
  final _postCode = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  bool _loaded = false;

  @override
  void dispose() {
    _companyId.dispose();
    _name.dispose();
    _tradingName.dispose();
    _addressLine1.dispose();
    _addressLine2.dispose();
    _cityTown.dispose();
    _postCode.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.watch(settingsControllerProvider.notifier);
    final activeLogo = getActiveLogo(settings.companyProfile);

    if (!_loaded) {
      _loaded = true;
      _companyId.text = settings.companyProfile.companyId;
      _name.text = settings.companyProfile.companyName;
      _tradingName.text = settings.companyProfile.tradingName;
      _addressLine1.text = settings.companyProfile.addressLine1;
      _addressLine2.text = settings.companyProfile.addressLine2;
      _cityTown.text = settings.companyProfile.cityTown;
      _postCode.text = settings.companyProfile.postCode;
      _email.text = settings.companyProfile.email;
      _phone.text = settings.companyProfile.phone;
    }

    Future<void> pickLogo() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
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
        title: const Text('Company Details'),
      ),
      drawer: const AppDrawer(currentRoute: '/company/settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _companyId,
                  decoration: const InputDecoration(
                    labelText: 'Project No',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Company Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _tradingName,
                  decoration: const InputDecoration(
                    labelText: 'Trading Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressLine1,
                  decoration: const InputDecoration(
                    labelText: 'Address line 1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressLine2,
                  decoration: const InputDecoration(
                    labelText: 'Address line 2',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _cityTown,
                  decoration: const InputDecoration(
                    labelText: 'City / Town',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _postCode,
                  decoration: const InputDecoration(
                    labelText: 'Post code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      ctrl.updateCompanyProfile(
                        companyId: _companyId.text,
                        companyName: _name.text,
                        tradingName: _tradingName.text,
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
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Company profile saved.')),
                      );
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Company Profile'),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: pickLogo,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload Company Logo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: settings.companyProfile.logoBytes.isEmpty
                          ? null
                          : () => ctrl.clearCompanyLogo(),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: activeLogo.hasCompanyLogo
                      ? Image.memory(
                          Uint8List.fromList(activeLogo.companyLogoBytes),
                          height: 96,
                        )
                      : Image.asset(
                          activeLogo.fallbackAssetPath,
                          height: 96,
                          fit: BoxFit.contain,
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  activeLogo.hasCompanyLogo
                      ? 'Your custom company logo is currently used across the app and reports.'
                      : 'No custom logo uploaded. The default BW Atlas logo is currently used across the app and reports.',
                  style: TextStyle(
                    fontSize: 12,
                    color: activeLogo.hasCompanyLogo
                        ? Colors.green.shade700
                        : Colors.grey.shade500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
