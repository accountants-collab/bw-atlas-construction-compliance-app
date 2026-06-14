import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../reports/domain/report_file_naming.dart';
import '../state/settings_controller.dart';

class BrandingScreen extends ConsumerStatefulWidget {
  const BrandingScreen({super.key});

  @override
  ConsumerState<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends ConsumerState<BrandingScreen> {
  final _header = TextEditingController();
  final _footer = TextEditingController();
  final _naming = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    _naming.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.watch(settingsControllerProvider.notifier);

    if (!_loaded) {
      _loaded = true;
      _header.text = settings.reportBranding.reportHeader;
      _footer.text = settings.reportBranding.reportFooter;
      _naming.text = settings.reportBranding.pdfFileNameFormat;
    }

    Future<void> pickReportLogo() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      ctrl.setReportLogo(bytes.toList());
    }

    final preview = previewReportFileNameFormat(
      settings: settings,
      reportType: 'Inspection',
      reportName: 'Project_001',
      extension: 'pdf',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Branding'),
        bottom: const WorkspaceSwitchCardsBar(),
      ),
      drawer: const AppDrawer(currentRoute: '/company/branding'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: settings.reportBranding.useCompanyBrandingOnPdf,
            onChanged: (v) {
              ctrl.updateReportBranding(
                reportHeader: _header.text,
                reportFooter: _footer.text,
                pdfFileNameFormat: _naming.text,
                useCompanyBrandingOnPdf: v,
              );
            },
            title: const Text('Use Company Branding on PDFs'),
            subtitle: const Text('When disabled, default report branding will be used.'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _header,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Report Header Text',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              ctrl.updateReportBranding(
                reportHeader: v,
                reportFooter: _footer.text,
                pdfFileNameFormat: _naming.text,
                useCompanyBrandingOnPdf: settings.reportBranding.useCompanyBrandingOnPdf,
              );
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _footer,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Report Footer Text',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              ctrl.updateReportBranding(
                reportHeader: _header.text,
                reportFooter: v,
                pdfFileNameFormat: _naming.text,
                useCompanyBrandingOnPdf: settings.reportBranding.useCompanyBrandingOnPdf,
              );
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _naming,
            decoration: const InputDecoration(
              labelText: 'Dynamic file naming format ({company} {type} {report} {date})',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              ctrl.updateReportBranding(
                reportHeader: _header.text,
                reportFooter: _footer.text,
                pdfFileNameFormat: v,
                useCompanyBrandingOnPdf: settings.reportBranding.useCompanyBrandingOnPdf,
              );
            },
          ),
          const SizedBox(height: 8),
          Text('Preview: $preview', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pickReportLogo,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Upload Report Logo'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: settings.reportBranding.reportLogoBytes.isEmpty ? null : ctrl.clearReportLogo,
                child: const Text('Remove'),
              ),
            ],
          ),
          if (settings.reportBranding.reportLogoBytes.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(Uint8List.fromList(settings.reportBranding.reportLogoBytes), height: 90),
            ),
          ],
        ],
      ),
    );
  }
}
