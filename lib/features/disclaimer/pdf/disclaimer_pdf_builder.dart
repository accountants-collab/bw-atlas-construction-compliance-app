import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/disclaimer_models.dart';

class DisclaimerPdfBuilder {
  /// Build PDF with signature from record (for new records during creation where signatureImageBytes is available)
  static Future<Uint8List> build({
    required DisclaimerAcceptanceRecord record,
    required String companyName,
    required String companyAddress,
    required String companyEmail,
    required String companyPhone,
    List<int> logoBytes = const [],
  }) async {
    return _buildPdf(
      record: record,
      companyName: companyName,
      companyAddress: companyAddress,
      companyEmail: companyEmail,
      companyPhone: companyPhone,
      logoBytes: logoBytes,
      signatureBytes: record.signatureImageBytes,
    );
  }

  /// Build PDF with signature loaded from URL (for existing records)
  static Future<Uint8List> buildWithRemoteSignature({
    required DisclaimerAcceptanceRecord record,
    required String companyName,
    required String companyAddress,
    required String companyEmail,
    required String companyPhone,
    List<int> logoBytes = const [],
  }) async {
    List<int> signatureBytes = const [];

    if (record.signatureDownloadUrl.trim().isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(record.signatureDownloadUrl));
        if (response.statusCode == 200) {
          signatureBytes = response.bodyBytes;
        }
      } catch (e) {
        // If signature download fails, just build without it
      }
    }

    return _buildPdf(
      record: record,
      companyName: companyName,
      companyAddress: companyAddress,
      companyEmail: companyEmail,
      companyPhone: companyPhone,
      logoBytes: logoBytes,
      signatureBytes: signatureBytes,
    );
  }

  static Future<Uint8List> _buildPdf({
    required DisclaimerAcceptanceRecord record,
    required String companyName,
    required String companyAddress,
    required String companyEmail,
    required String companyPhone,
    required List<int> logoBytes,
    required List<int> signatureBytes,
  }) async {
    final doc = pw.Document();
    final logo = logoBytes.isEmpty ? null : pw.MemoryImage(Uint8List.fromList(logoBytes));
    final signature = signatureBytes.isEmpty
        ? null
        : pw.MemoryImage(Uint8List.fromList(signatureBytes));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (logo != null) pw.Image(logo, width: 92, height: 52, fit: pw.BoxFit.contain),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(companyName.trim().isEmpty ? 'Company' : companyName.trim(),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    if (companyAddress.trim().isNotEmpty) pw.Text(companyAddress.trim(), style: const pw.TextStyle(fontSize: 9)),
                    if (companyEmail.trim().isNotEmpty) pw.Text(companyEmail.trim(), style: const pw.TextStyle(fontSize: 9)),
                    if (companyPhone.trim().isNotEmpty) pw.Text(companyPhone.trim(), style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: PdfColor.fromHex('#20364F'),
            child: pw.Text(
              'DISCLAIMER ACCEPTANCE RECORD',
              style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
          ),
          pw.SizedBox(height: 14),
          _metaTable(record),
          pw.SizedBox(height: 14),
          pw.Text(
            disclaimerTitleForModule(record.moduleType),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
          ),
          pw.SizedBox(height: 8),
          pw.Text(record.acceptedTextSnapshot.trim(), style: const pw.TextStyle(fontSize: 9, lineSpacing: 3)),
          pw.SizedBox(height: 16),
          pw.Text('Signature', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 6),
          pw.Container(
            height: 72,
            width: 180,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: signature == null
                ? pw.Center(child: pw.Text('Signature not available', style: const pw.TextStyle(fontSize: 9)))
                : pw.Image(signature, fit: pw.BoxFit.contain),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _metaTable(DisclaimerAcceptanceRecord record) {
    String acceptedAt = record.disclaimerAcceptedAt?.toIso8601String().replaceFirst('T', ' ').split('.').first ?? '-';
    final rows = <List<String>>[
      ['Module', disclaimerModuleLabel(record.moduleType)],
      ['Project', record.projectName.trim().isEmpty ? '-' : record.projectName.trim()],
      ['Project Number', record.projectNumber.trim().isEmpty ? '-' : record.projectNumber.trim()],
      ['Report Reference', record.reportReference.trim().isEmpty ? '-' : record.reportReference.trim()],
      ['Inspector / Manager', record.inspectorName.trim().isEmpty ? '-' : record.inspectorName.trim()],
      ['User Email', record.userEmail.trim().isEmpty ? '-' : record.userEmail.trim()],
      ['Role', record.userRole.trim().isEmpty ? '-' : record.userRole.trim()],
      ['Accepted On', acceptedAt],
      ['Disclaimer Version', record.disclaimerVersion],
      ['Status', record.acceptanceStatus],
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2.4),
      },
      children: [
        for (final row in rows)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(row[0], style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(row[1], style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
          ),
      ],
    );
  }
}