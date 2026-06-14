import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../auth/auth_state.dart';
import '../../fire_door/inspection/pdf/web_download_stub.dart'
    if (dart.library.html) '../../fire_door/inspection/pdf/web_download.dart';
import '../data/disclaimer_providers.dart';
import '../domain/disclaimer_models.dart';

class DisclaimerAcceptanceSection extends ConsumerWidget {
  const DisclaimerAcceptanceSection({
    super.key,
    required this.companyId,
    required this.reportId,
    required this.moduleType,
    this.onOpenDisclaimerForm,
  });

  final String companyId;
  final String reportId;
  final String moduleType;
  final Future<void> Function()? onOpenDisclaimerForm;

  DateTime _resolveExpiry(DisclaimerAcceptanceRecord record) {
    final acceptedAt = record.disclaimerAcceptedAt ?? record.createdAt;
    return record.expiresAt ?? disclaimerExpiresAtFrom(acceptedAt);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm').format(value);
  }

  String _invalidReason(DisclaimerAcceptanceRecord record) {
    if (record.disclaimerVersion.trim() != kDisclaimerVersion.trim()) {
      return 'A newer disclaimer version is available. Please re-accept before continuing.';
    }
    final expiresAt = _resolveExpiry(record);
    if (DateTime.now().isAfter(expiresAt)) {
      return 'This disclaimer has expired. Please re-accept before continuing.';
    }
    return 'This disclaimer is not valid for the current user or module scope.';
  }

  Future<void> _download(
      BuildContext context, DisclaimerAcceptanceRecord record) async {
    if (record.pdfDownloadUrl.trim().isEmpty) return;
    final fileName = 'disclaimer_${record.acceptanceId}.pdf';
    if (kIsWeb) {
      downloadUrlWeb(url: record.pdfDownloadUrl, fileName: fileName);
      return;
    }
    final response = await http.get(Uri.parse(record.pdfDownloadUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Could not download PDF.');
    }
    final bytes = response.bodyBytes;
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final canViewAll = auth.actualRole == UserRole.owner ||
        auth.actualRole == UserRole.admin ||
        auth.actualRole == UserRole.superAdmin;
    final moduleScope = disclaimerAcceptanceScopeForModule(moduleType);

    return StreamBuilder<List<DisclaimerAcceptanceRecord>>(
      stream: ref
          .read(disclaimerRepositoryProvider)
          .watchCompanyRecords(companyId: companyId),
      builder: (context, snapshot) {
        final allRecords =
            snapshot.data ?? const <DisclaimerAcceptanceRecord>[];
        final scopedRecords = allRecords
            .where(
              (record) =>
                  disclaimerAcceptanceScopeForModule(record.moduleType) ==
                  moduleScope,
            )
            .toList();
        final visible = canViewAll
            ? List<DisclaimerAcceptanceRecord>.from(scopedRecords)
            : scopedRecords
                .where((record) => record.userId == auth.uid)
                .toList();
        try {
          if (visible.length > 1) {
            visible.sort((a, b) {
              final aValue = a.disclaimerAcceptedAt ?? a.createdAt;
              final bValue = b.disclaimerAcceptedAt ?? b.createdAt;
              return bValue.compareTo(aValue);
            });
          }
        } catch (e) {
          debugPrint('Sort error (disclaimer acceptance section): $e');
        }
        final latestRecord = visible.isEmpty ? null : visible.first;
        DisclaimerAcceptanceRecord? currentRecord;
        for (final candidate in visible) {
          if (isDisclaimerAcceptanceCurrent(
            record: candidate,
            moduleType: moduleType,
            userId: auth.uid,
          )) {
            currentRecord = candidate;
            break;
          }
        }
        final displayRecord = currentRecord ?? latestRecord;
        final daysUntilExpiry = disclaimerDaysUntilExpiry(
          record: currentRecord,
          moduleType: moduleType,
          userId: auth.uid,
        );
        final showExpiryReminder = daysUntilExpiry != null &&
            daysUntilExpiry <= kDisclaimerNearExpiryDays &&
            daysUntilExpiry >= 0;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_user_outlined,
                      size: 16, color: Color(0xFF1E3A5F)),
                  SizedBox(width: 6),
                  Text(
                    'Disclaimer Acceptance',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1E3A5F)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (displayRecord == null) ...[
                Text(
                  'No saved disclaimer record is available for this module yet.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                if (onOpenDisclaimerForm != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await onOpenDisclaimerForm!.call();
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Could not open disclaimer form: $error')),
                        );
                      }
                    },
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('Open Disclaimer Form'),
                  ),
                ],
              ] else ...[
                Text(
                  currentRecord != null
                      ? 'Disclaimer accepted'
                      : 'Disclaimer requires renewal',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: currentRecord != null
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Accepted by: ${displayRecord.inspectorName}'),
                Text(
                    'Accepted on: ${_formatDate(displayRecord.disclaimerAcceptedAt ?? displayRecord.createdAt)}'),
                Text(
                    'Valid until: ${_formatDate(_resolveExpiry(displayRecord))}'),
                Text('Version: ${displayRecord.disclaimerVersion}'),
                if (showExpiryReminder) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      border: Border.all(color: const Color(0xFFFFD8A8)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      daysUntilExpiry == 0
                          ? 'Reminder: disclaimer expires today. Renew soon to avoid interruption.'
                          : 'Reminder: disclaimer expires in $daysUntilExpiry day${daysUntilExpiry == 1 ? '' : 's'}.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                if (currentRecord == null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      border: Border.all(color: const Color(0xFFFFCCC7)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _invalidReason(displayRecord),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                if (canViewAll && scopedRecords.length > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                      'Saved records for this module: ${scopedRecords.length}'),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => context.go(
                          '/company/disclaimer-records/${displayRecord.acceptanceId}'),
                      child: const Text('View Disclaimer'),
                    ),
                    FilledButton.tonal(
                      onPressed: displayRecord.hasPdf
                          ? () async {
                              try {
                                await _download(context, displayRecord);
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Could not download disclaimer PDF: $error')),
                                );
                              }
                            }
                          : null,
                      child: const Text('Download Disclaimer PDF'),
                    ),
                    if (onOpenDisclaimerForm != null && currentRecord == null)
                      FilledButton.icon(
                        onPressed: () async {
                          try {
                            await onOpenDisclaimerForm!.call();
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Could not open disclaimer form: $error')),
                            );
                          }
                        },
                        icon: const Icon(Icons.edit_document, size: 16),
                        label: const Text('Renew Disclaimer'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
