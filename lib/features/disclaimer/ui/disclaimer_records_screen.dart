import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../../../app/app_drawer.dart';
import '../../../auth/auth_state.dart';
import '../../fire_door/inspection/pdf/web_download_stub.dart'
    if (dart.library.html) '../../fire_door/inspection/pdf/web_download.dart';
import '../data/disclaimer_providers.dart';
import '../domain/disclaimer_models.dart';

class DisclaimerRecordsScreen extends ConsumerStatefulWidget {
  const DisclaimerRecordsScreen({super.key});

  @override
  ConsumerState<DisclaimerRecordsScreen> createState() => _DisclaimerRecordsScreenState();
}

class _DisclaimerRecordsScreenState extends ConsumerState<DisclaimerRecordsScreen> {
  final _searchController = TextEditingController();
  String _moduleFilter = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _download(BuildContext context, DisclaimerAcceptanceRecord record) async {
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
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final role = auth.actualRole;
    final companyId = auth.companyId;
    final canViewAll = role == UserRole.owner || role == UserRole.admin || role == UserRole.superAdmin;
    final canViewOwn = role == UserRole.manager || canViewAll;

    if (!canViewOwn) {
      return const Scaffold(body: Center(child: Text('You do not have access to disclaimer records.')));
    }
    if (companyId == null || companyId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Company context is missing.')));
    }

    final title = canViewAll ? 'All Disclaimer Forms' : 'My Disclaimer Forms';

    return Scaffold(
      drawer: const AppDrawer(currentRoute: '/company/disclaimer-records'),
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<List<DisclaimerAcceptanceRecord>>(
        stream: ref.read(disclaimerRepositoryProvider).watchCompanyRecords(companyId: companyId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final search = _searchController.text.trim().toLowerCase();
          final allRecords = snapshot.data ?? const <DisclaimerAcceptanceRecord>[];
          final visibleRecords = allRecords.where((record) {
            if (!canViewAll && record.userId != auth.uid) return false;
            if (_moduleFilter != 'all' && record.moduleType != _moduleFilter) return false;
            final acceptedAt = record.disclaimerAcceptedAt ?? record.createdAt;
            if (_fromDate != null && acceptedAt.isBefore(DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day))) return false;
            if (_toDate != null) {
              final end = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
              if (acceptedAt.isAfter(end)) return false;
            }
            if (search.isEmpty) return true;
            final haystack = [
              record.projectName,
              record.projectNumber,
              record.reportReference,
              record.userEmail,
              record.inspectorName,
              disclaimerModuleLabel(record.moduleType),
              acceptedAt.toIso8601String(),
            ].join(' ').toLowerCase();
            return haystack.contains(search);
          }).toList();

          try {
            if (visibleRecords.length > 1) {
              visibleRecords.sort((a, b) {
                final aValue = a.disclaimerAcceptedAt ?? a.createdAt;
                final bValue = b.disclaimerAcceptedAt ?? b.createdAt;
                return bValue.compareTo(aValue);
              });
            }
          } catch (e) {
            debugPrint('Sort error (disclaimer records screen): $e');
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search by project, report, user, module, or date',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _searchController.clear()),
                    icon: const Icon(Icons.clear),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _moduleFilter,
                      decoration: const InputDecoration(labelText: 'Module', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All modules')),
                        DropdownMenuItem(value: 'fire-door', child: Text('Fire Door')),
                        DropdownMenuItem(value: 'fire-stopping', child: Text('Fire Stopping')),
                        DropdownMenuItem(value: 'snagging', child: Text('Snagging')),
                      ],
                      onChanged: (value) => setState(() => _moduleFilter = value ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _fromDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => _fromDate = picked);
                      },
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(_fromDate == null ? 'From date' : _fromDate!.toIso8601String().split('T').first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _toDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => _toDate = picked);
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_toDate == null ? 'To date' : _toDate!.toIso8601String().split('T').first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _moduleFilter = 'all';
                    _fromDate = null;
                    _toDate = null;
                    _searchController.clear();
                  }),
                  child: const Text('Clear filters'),
                ),
              ),
              const SizedBox(height: 8),
              if (visibleRecords.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No disclaimer records found for the current filters.'),
                  ),
                )
              else
                for (final record in visibleRecords)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(record.projectName.isEmpty ? 'Unnamed Project' : record.projectName),
                      subtitle: Text(
                        '${disclaimerModuleLabel(record.moduleType)} | ${record.inspectorName} | ${record.disclaimerAcceptedAt?.toIso8601String().replaceFirst('T', ' ').split('.').first ?? '-'}',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => context.go('/company/disclaimer-records/${record.acceptanceId}'),
                            child: const Text('View'),
                          ),
                          TextButton(
                            onPressed: record.hasPdf
                                ? () async {
                                    try {
                                      await _download(context, record);
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Could not download PDF: $error')),
                                      );
                                    }
                                  }
                                : null,
                            child: const Text('Download PDF'),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}