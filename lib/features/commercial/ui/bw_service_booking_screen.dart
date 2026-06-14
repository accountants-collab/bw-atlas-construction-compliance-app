import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../settings/state/settings_controller.dart';

class BwServiceBookingScreen extends ConsumerStatefulWidget {
  const BwServiceBookingScreen({super.key});

  @override
  ConsumerState<BwServiceBookingScreen> createState() =>
      _BwServiceBookingScreenState();
}

class _BwServiceBookingScreenState
    extends ConsumerState<BwServiceBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyName = TextEditingController();
  final _contactName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _cityTown = TextEditingController();
  final _postCode = TextEditingController();
  final _notes = TextEditingController();
  final _customService = TextEditingController();
  final List<PlatformFile> _attachments = [];

  String _service = 'Book Survey';

  static const _serviceOptions = <String>[
    'Book Survey',
    'Book Installation',
    'Book Remedial / Maintenance',
    'General Enquiry',
    'Other (custom)',
  ];

  @override
  void dispose() {
    _companyName.dispose();
    _contactName.dispose();
    _email.dispose();
    _phone.dispose();
    _addressLine1.dispose();
    _addressLine2.dispose();
    _cityTown.dispose();
    _postCode.dispose();
    _notes.dispose();
    _customService.dispose();
    super.dispose();
  }

  Future<void> _submitEnquiry() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    const destinationEmail = 'info@bestwaycarpenty.com';

    final selectedService = _service == 'Other (custom)'
        ? (_customService.text.trim().isEmpty
            ? 'Other (custom)'
            : _customService.text.trim())
        : _service;

    final addressSummary = [
      _addressLine1.text.trim(),
      _addressLine2.text.trim(),
      _cityTown.text.trim(),
      _postCode.text.trim(),
    ].where((p) => p.isNotEmpty).join(', ');

    final subjectRaw = 'Service Enquiry: $selectedService';
    final bodyRaw = '''
Company Name: ${_companyName.text.trim()}
Contact Name: ${_contactName.text.trim()}
Email: ${_email.text.trim()}
Phone: ${_phone.text.trim()}
  Address line 1: ${_addressLine1.text.trim()}
  Address line 2: ${_addressLine2.text.trim()}
  City / Town: ${_cityTown.text.trim()}
  Post code: ${_postCode.text.trim()}
  Project / Site Address: $addressSummary
  Service Requested: $selectedService
Notes: ${_notes.text.trim()}
''';

    if (_attachments.isNotEmpty) {
      final files = _attachments
          .where((f) => f.bytes != null)
          .map((f) => XFile.fromData(
                f.bytes!,
                name: f.name,
                mimeType:
                    f.extension == null ? null : 'application/${f.extension}',
              ))
          .toList();

      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Attached files are unavailable. Please add files again.')),
        );
        return;
      }

      await Share.shareXFiles(
        files,
        subject: subjectRaw,
        text: 'Send to: $destinationEmail\n\n$bodyRaw',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Files prepared. Please select your email app and send to $destinationEmail.')),
      );
      return;
    }

    final subject = Uri.encodeComponent(subjectRaw);
    final body = Uri.encodeComponent(bodyRaw);

    final uri =
        Uri.parse('mailto:$destinationEmail?subject=$subject&body=$body');
    final launched = await launchUrl(uri);

    if (!mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Could not open email app. Please email $destinationEmail directly.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Enquiry prepared for $destinationEmail')),
    );
  }

  Future<void> _addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final existing = _attachments.map((f) => '${f.name}:${f.size}').toSet();
    final newFiles = result.files
        .where((f) => f.bytes != null)
        .where((f) => !existing.contains('${f.name}:${f.size}'))
        .toList();

    if (newFiles.isEmpty) return;
    setState(() => _attachments.addAll(newFiles));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    if (_companyName.text.isEmpty &&
        settings.companyProfile.companyName.trim().isNotEmpty) {
      _companyName.text = settings.companyProfile.companyName.trim();
    }
    if (_email.text.isEmpty &&
        settings.companyProfile.email.trim().isNotEmpty) {
      _email.text = settings.companyProfile.email.trim();
    }
    if (_phone.text.isEmpty &&
        settings.companyProfile.phone.trim().isNotEmpty) {
      _phone.text = settings.companyProfile.phone.trim();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Book BW Atlas Services')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B3D2E), Color(0xFF147A5A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x330B3D2E),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need certified specialists to do the work for you?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Book BW Atlas directly for fire door surveys, installation, remedial works, and maintenance support.',
                      style: TextStyle(color: Colors.white, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _service,
                          decoration: const InputDecoration(
                            labelText: 'Service Requested',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.handyman_outlined),
                          ),
                          items: _serviceOptions
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _service = v ?? _service),
                        ),
                        if (_service == 'Other (custom)') ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _customService,
                            decoration: const InputDecoration(
                              labelText: 'Custom service *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.edit_outlined),
                            ),
                            validator: (v) {
                              if (_service != 'Other (custom)') return null;
                              return (v ?? '').trim().isEmpty
                                  ? 'Please enter custom service.'
                                  : null;
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _companyName,
                          decoration: const InputDecoration(
                            labelText: 'Company Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Company name is required.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _contactName,
                          decoration: const InputDecoration(
                            labelText: 'Contact Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Contact name is required.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Email is required.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Phone is required.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressLine1,
                          decoration: const InputDecoration(
                            labelText: 'Address line 1',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Address line 1 is required.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressLine2,
                          decoration: const InputDecoration(
                            labelText: 'Address line 2',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.pin_drop_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _cityTown,
                          decoration: const InputDecoration(
                            labelText: 'City / Town',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_city_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'City / Town is required.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _postCode,
                          decoration: const InputDecoration(
                            labelText: 'Post code',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.markunread_mailbox_outlined),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Post code is required.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notes,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                            prefixIcon: Icon(Icons.sticky_note_2_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Attachments (optional)',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _addFiles,
                                icon: const Icon(Icons.attach_file_outlined),
                                label: const Text('Add File'),
                              ),
                            ),
                          ],
                        ),
                        if (_attachments.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (int i = 0; i < _attachments.length; i++)
                                InputChip(
                                  label: Text(_attachments[i].name),
                                  onDeleted: () =>
                                      setState(() => _attachments.removeAt(i)),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _submitEnquiry,
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('Request a Quote'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
