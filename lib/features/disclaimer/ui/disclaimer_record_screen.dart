import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../../../auth/auth_state.dart';
import '../../fire_door/inspection/pdf/web_download_stub.dart'
    if (dart.library.html) '../../fire_door/inspection/pdf/web_download.dart';
import '../data/disclaimer_providers.dart';
import '../domain/disclaimer_models.dart';

class DisclaimerRecordScreen extends ConsumerWidget {
  const DisclaimerRecordScreen({super.key, required this.acceptanceId});

  final String acceptanceId;

  Future<void> _downloadPdf(BuildContext context, DisclaimerAcceptanceRecord record) async {
    if (record.pdfDownloadUrl.trim().isEmpty) return;
    final fileName = 'disclaimer_${record.acceptanceId}.pdf';
    if (kIsWeb) {
      downloadUrlWeb(url: record.pdfDownloadUrl, fileName: fileName);
      return;
    }
    final response = await http.get(Uri.parse(record.pdfDownloadUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to download PDF.');
    }
    final bytes = response.bodyBytes;
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final companyId = auth.companyId;
    if (companyId == null || companyId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Company context is missing.')));
    }

    return FutureBuilder<DisclaimerAcceptanceRecord?>(
      future: ref.read(disclaimerRepositoryProvider).getById(companyId: companyId, acceptanceId: acceptanceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final record = snapshot.data;
        if (record == null) {
          return const Scaffold(body: Center(child: Text('Disclaimer record not found.')));
        }

        final role = auth.actualRole;
        final canViewAll = role == UserRole.owner || role == UserRole.admin || role == UserRole.superAdmin;
        final canView = canViewAll || record.userId == auth.uid;
        if (!canView) {
          return const Scaffold(body: Center(child: Text('You do not have access to this disclaimer record.')));
        }

        final acceptedAt = record.disclaimerAcceptedAt?.toIso8601String().replaceFirst('T', ' ').split('.').first ?? '-';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Disclaimer Acceptance'),
            actions: [
              IconButton(
                onPressed: record.hasPdf
                    ? () async {
                        try {
                          await _downloadPdf(context, record);
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not download PDF: $error')),
                          );
                        }
                      }
                    : null,
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Download PDF',
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(disclaimerTitleForModule(record.moduleType), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 12),
                      Text('Accepted by: ${record.inspectorName}'),
                      Text('User email: ${record.userEmail}'),
                      Text('Role: ${record.userRole}'),
                      Text('Project: ${record.projectName.isEmpty ? '-' : record.projectName}'),
                      Text('Project number: ${record.projectNumber.isEmpty ? '-' : record.projectNumber}'),
                      Text('Report reference: ${record.reportReference.isEmpty ? '-' : record.reportReference}'),
                      Text('Accepted on: $acceptedAt'),
                      Text('Version: ${record.disclaimerVersion}'),
                      Text('Status: ${record.acceptanceStatus}'),
                      const SizedBox(height: 14),
                      const Text('Signature', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Container(
                        height: 92,
                        width: 220,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: record.signatureDownloadUrl.trim().isEmpty
                            ? const Center(child: Text('Signature not available'))
                            : Image.network(record.signatureDownloadUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Text('Could not load signature'))),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(record.acceptedTextSnapshot, style: const TextStyle(height: 1.45)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}