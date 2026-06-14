import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/fire_stopping_models.dart';

class FireStoppingPdfBuilder {
  static Future<Uint8List> buildProjectReport(FireStoppingProject project) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Text('FIRE STOPPING REPORT', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Project: ${project.name.isEmpty ? '-' : project.name}'),
          pw.Text('Reference: ${project.reference.isEmpty ? '-' : project.reference}'),
          pw.Text('Date: ${_fmt(project.date)}'),
          pw.SizedBox(height: 12),
          ...project.items.map((item) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Reference: ${item.reference.isEmpty ? item.id : item.reference}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('Level: ${item.level.isEmpty ? '-' : item.level} | Location: ${item.location.isEmpty ? '-' : item.location}'),
                    pw.Text('Status: ${item.status.name} | Findings: ${item.findings.length}'),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
    return doc.save();
  }

  static String _fmt(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}
