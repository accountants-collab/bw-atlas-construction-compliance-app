import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../disclaimer/domain/disclaimer_models.dart';
import '../domain/snagging_models.dart';

class SnaggingPdfBuilder {
  static final PdfColor _text = PdfColor.fromInt(0xFF1F2937);
  static final PdfColor _secondaryText = PdfColor.fromInt(0xFF667085);
  static final PdfColor _line = PdfColor.fromInt(0xFFD8E0E8);
  static final PdfColor _softLine = PdfColor.fromInt(0xFFE8EDF3);
  static final PdfColor _panelAlt = PdfColor.fromInt(0xFFF8FAFC);
  static final PdfColor _sectionTint = PdfColor.fromInt(0xFFF7F9FC);
  static final PdfColor _pass = PdfColor.fromInt(0xFF15803D);
  static final PdfColor _passBg = PdfColor.fromInt(0xFFF3FAF5);
  static final PdfColor _fail = PdfColor.fromInt(0xFFB91C1C);
  static final PdfColor _failBg = PdfColor.fromInt(0xFFFFF4F4);

  static Future<Uint8List> buildProjectReport(
    SnaggingProject project, {
    DisclaimerAcceptanceRecord? disclaimerRecord,
    String companyName = '',
    String companyAddress = '',
    String companyEmail = '',
    String companyPhone = '',
    String preparedBy = '',
    Uint8List? logoBytes,
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final doc = pw.Document();

    pw.MemoryImage? logoImage;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(logoBytes);
      } catch (_) {
        logoImage = null;
      }
    }

    final issueCount = project.issues.length;
    final issueSections = <pw.Widget>[];
    for (final issue in project.issues) {
      issueSections.addAll(await _buildIssueSection(issue));
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (_) => _buildPageHeader(
          project: project,
          companyName: companyName,
          companyAddress: companyAddress,
          companyEmail: companyEmail,
          companyPhone: companyPhone,
          preparedBy: preparedBy,
          logoImage: logoImage,
          issueCount: issueCount,
          reportHeaderText: reportHeaderText,
        ),
        footer: (ctx) => _buildPageFooter(
          context: ctx,
          companyName: companyName,
          reportFooterText: reportFooterText,
          projectName: project.name,
        ),
        build: (_) => [
          if (disclaimerRecord != null) ...[
            _buildDisclaimerSection(disclaimerRecord),
            pw.SizedBox(height: 12),
          ],
          if (project.issues.isEmpty)
            pw.Text('No snags recorded.',
                style: _style(8, color: _secondaryText))
          else
            ...issueSections,
        ],
      ),
    );

    return doc.save();
  }

  static String buildFilename(SnaggingProject project,
      {String preparedBy = ''}) {
    final date = _fmt(project.date);
    final safe = _slug;
    final projectPart = safe(project.name.isEmpty ? 'Project' : project.name);
    if (preparedBy.isNotEmpty) {
      return 'Snagging_${date}_${projectPart}_${safe(preparedBy)}.pdf';
    }
    return 'Snagging_${date}_$projectPart.pdf';
  }

  static pw.Widget _buildPageHeader({
    required SnaggingProject project,
    required String companyName,
    required String companyAddress,
    required String companyEmail,
    required String companyPhone,
    required String preparedBy,
    required pw.MemoryImage? logoImage,
    required int issueCount,
    required String reportHeaderText,
  }) {
    final address = _siteAddress(project);
    final resolvedCompanyName = companyName.trim().isEmpty
        ? kDefaultSystemCompanyName
        : companyName.trim();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _sectionTint,
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoImage != null)
                pw.SizedBox(
                  width: 108,
                  height: 38,
                  child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                )
              else
                pw.Container(
                  width: 108,
                  height: 38,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    color: _panelAlt,
                    border: pw.Border.all(color: _softLine),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    resolvedCompanyName,
                    style: _style(7.6, bold: true, color: _secondaryText),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('SNAGGING REPORT',
                        textAlign: pw.TextAlign.center,
                        style: _style(13.2, bold: true)),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      project.name.isEmpty ? 'Unnamed Project' : project.name,
                      textAlign: pw.TextAlign.center,
                      style: _style(8.0, color: _secondaryText),
                    ),
                    if (reportHeaderText.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        reportHeaderText.trim(),
                        textAlign: pw.TextAlign.center,
                        style: _style(7.3, color: _secondaryText),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Container(
                width: 160,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: _softLine),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Company',
                        style: _style(7.0, bold: true, color: _secondaryText)),
                    pw.SizedBox(height: 2),
                    pw.Text(resolvedCompanyName,
                        style: _style(6.9, color: _secondaryText),
                        textAlign: pw.TextAlign.right),
                    if (companyAddress.isNotEmpty)
                      pw.Text(companyAddress,
                          style: _style(6.8, color: _secondaryText),
                          textAlign: pw.TextAlign.right),
                    if (companyEmail.isNotEmpty)
                      pw.Text(companyEmail,
                          style: _style(6.8, color: _secondaryText),
                          textAlign: pw.TextAlign.right),
                    if (companyPhone.isNotEmpty)
                      pw.Text(companyPhone,
                          style: _style(6.8, color: _secondaryText),
                          textAlign: pw.TextAlign.right),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          _metaGrid([
            _MetaCell(
                'Project / Site', project.name.isEmpty ? '-' : project.name),
            _MetaCell('Client', project.client.isEmpty ? '-' : project.client),
            if (project.preparedFor.isNotEmpty)
              _MetaCell('Prepared For', project.preparedFor),
            _MetaCell('Site Address', address),
            _MetaCell('Report Date', _fmt(project.date)),
            _MetaCell('Findings', issueCount.toString()),
            if (preparedBy.isNotEmpty) _MetaCell('Prepared By', preparedBy),
          ]),
          pw.SizedBox(height: 6),
          pw.Container(height: 1, color: _line),
        ],
      ),
    );
  }

  static pw.Widget _buildPageFooter({
    required pw.Context context,
    required String companyName,
    required String reportFooterText,
    required String projectName,
  }) {
    final resolvedCompanyName = companyName.trim().isEmpty
        ? kDefaultSystemCompanyName
        : companyName.trim();
    final resolvedFooter = reportFooterText.trim().isEmpty
        ? 'Snagging Report | ${projectName.isEmpty ? 'Unnamed Project' : projectName}'
        : reportFooterText.trim();

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(height: 1, color: _softLine),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Expanded(
                child: pw.Text(resolvedCompanyName,
                    style: _style(7.0, color: _secondaryText))),
            pw.Expanded(
              child: pw.Text(
                resolvedFooter,
                textAlign: pw.TextAlign.center,
                style: _style(7.0, color: _secondaryText),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                textAlign: pw.TextAlign.right,
                style: _style(7.0, color: _secondaryText),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildDisclaimerSection(
      DisclaimerAcceptanceRecord disclaimerRecord) {
    final signatureImage = disclaimerRecord.signatureImageBytes.isNotEmpty
        ? pw.MemoryImage(
            Uint8List.fromList(disclaimerRecord.signatureImageBytes))
        : null;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _panelAlt,
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Disclaimer Acknowledgement', style: _style(9.2, bold: true)),
          pw.SizedBox(height: 4),
          pw.Text(
            'The full snagging disclaimer was reviewed and accepted on a separate saved disclaimer form linked to this report.',
            style: _style(7.8, color: _secondaryText),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'For full legal wording and audit history, see the saved disclaimer records in system compliance files.',
            style: _style(7.6, color: _secondaryText),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Inspector: ${disclaimerRecord.inspectorName}',
              style: _style(7.8)),
          pw.Text(
            'Accepted on: ${_fmtDateTime(disclaimerRecord.disclaimerAcceptedAt ?? disclaimerRecord.createdAt)}',
            style: _style(7.8),
          ),
          pw.Text('Role: Inspector', style: _style(7.8)),
          pw.Text('Version: ${disclaimerRecord.disclaimerVersion}',
              style: _style(7.8)),
          pw.SizedBox(height: 6),
          pw.Text('Signature', style: _style(7.8, bold: true)),
          pw.SizedBox(height: 3),
          if (signatureImage != null)
            pw.Container(
              height: 42,
              width: 120,
              alignment: pw.Alignment.centerLeft,
              child:
                  pw.Image(signatureImage, height: 42, fit: pw.BoxFit.contain),
            )
          else
            pw.Text('Captured on saved disclaimer form.',
                style: _style(7.8, color: _secondaryText)),
        ],
      ),
    );
  }

  static Future<List<pw.Widget>> _buildIssueSection(SnaggingIssue issue) async {
    final drawingPreviewWithPin = await _buildDrawingPreviewWithPin(issue);
    final hasPin = drawingPreviewWithPin != null;
    final priorityColor = _pdfPriorityColor(issue.priority);
    final statusStyle = _statusStyle(issue.status);
    final decodedPhotos = issue.originalPhotoBase64.map(_decodeBase64).toList();

    final widgets = <pw.Widget>[
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: pw.BoxDecoration(
                color: _sectionTint,
                border: pw.Border(bottom: pw.BorderSide(color: _softLine)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Snag #${issue.snagNumber}',
                      style: _style(10.5, bold: true)),
                  pw.Row(
                    children: [
                      _badge(_statusLabel(issue.status), statusStyle.foreground,
                          statusStyle.background),
                      pw.SizedBox(width: 4),
                      _badge(_priorityLabel(issue.priority), PdfColors.white,
                          priorityColor),
                    ],
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (issue.assignedToName.isNotEmpty)
                    _detailRow('Assigned To', issue.assignedToName),
                  if (issue.responsibleParty != ResponsibleParty.unknown)
                    _detailRow(
                      'Responsible Party',
                      issue.responsibleParty == ResponsibleParty.other &&
                              issue.responsiblePartyCustom.trim().isNotEmpty
                          ? issue.responsiblePartyCustom.trim()
                          : responsiblePartyLabel(issue.responsibleParty),
                    ),
                  if (issue.location.isNotEmpty)
                    _detailRow('Location', issue.location),
                  if (issue.reference.isNotEmpty)
                    _detailRow('Reference / PIN', issue.reference),
                  _detailRow(
                      'Programme Impact', _impactLabel(issue.programmeImpact)),
                  _detailRow('Date & Time', _fmtDateTime(issue.dateTime)),
                  if (hasPin) ...[
                    pw.SizedBox(height: 6),
                    pw.Text('Drawing Reference',
                        style: _style(8.2, bold: true)),
                    pw.SizedBox(height: 4),
                    pw.Container(
                      width: double.infinity,
                      height: 190,
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: _softLine)),
                      child: pw.Image(
                        pw.MemoryImage(drawingPreviewWithPin),
                        fit: pw.BoxFit.contain,
                        width: double.infinity,
                        height: 190,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      pw.Text('Photo Evidence', style: _style(8.8, bold: true)),
      pw.SizedBox(height: 5),
      if (decodedPhotos.every((p) => p == null))
        pw.Text('No inspector photos attached.',
            style: _style(7.8, color: _secondaryText))
      else
        ..._buildPhotoRows(issue, decodedPhotos),
      pw.SizedBox(height: 12),
    ];

    return widgets;
  }

  static List<pw.Widget> _buildPhotoRows(
      SnaggingIssue issue, List<Uint8List?> decodedPhotos) {
    final rows = <pw.Widget>[];
    for (var i = 0; i < decodedPhotos.length; i++) {
      final photoBytes = decodedPhotos[i];
      final desc = i < issue.photoDescriptions.length
          ? issue.photoDescriptions[i].trim()
          : '';
      if (photoBytes == null) {
        continue;
      }

      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: _line),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 108,
                  height: 96,
                  color: _panelAlt,
                  child: pw.Image(pw.MemoryImage(photoBytes),
                      fit: pw.BoxFit.cover),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Photo ${i + 1}', style: _style(8.0, bold: true)),
                      pw.SizedBox(height: 3),
                      pw.Text(
                          desc.isEmpty
                              ? 'No issue description provided.'
                              : desc,
                          style: _style(7.8)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return rows;
  }

  static Uint8List? _decodeBase64(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return base64Decode(raw.trim());
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _decodeDrawingPreviewSource(
      SnaggingIssue issue) async {
    if (issue.drawingBytesBase64.trim().isEmpty) return null;
    final source = _decodeBase64(issue.drawingBytesBase64);
    if (source == null) return null;

    if (issue.drawingMimeType == 'application/pdf') {
      try {
        await for (final raster
            in Printing.raster(source, pages: const [0], dpi: 220)) {
          return await raster.toPng();
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    return source;
  }

  static Future<Uint8List?> _buildDrawingPreviewWithPin(
      SnaggingIssue issue) async {
    if (issue.pinX < 0 || issue.pinY < 0) return null;

    final source = await _decodeDrawingPreviewSource(issue);
    if (source == null || source.isEmpty) return null;

    final decoded = img.decodeImage(source);
    if (decoded == null) return null;

    final full = img.copyResize(
      decoded,
      width: decoded.width > 2200 ? 2200 : decoded.width,
    );
    final markerX = (issue.pinX.clamp(0.0, 1.0) * full.width)
        .round()
        .clamp(0, full.width - 1);
    final markerY = (issue.pinY.clamp(0.0, 1.0) * full.height)
        .round()
        .clamp(0, full.height - 1);

    img.fillCircle(full,
        x: markerX, y: markerY, radius: 15, color: img.ColorRgb8(198, 40, 40));
    img.drawCircle(full,
        x: markerX,
        y: markerY,
        radius: 22,
        color: img.ColorRgb8(255, 255, 255));
    img.drawCircle(full,
        x: markerX,
        y: markerY,
        radius: 23,
        color: img.ColorRgb8(255, 255, 255));

    return Uint8List.fromList(img.encodeJpg(full, quality: 92));
  }

  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '$label: ', style: _style(7.8, bold: true)),
            pw.TextSpan(text: value, style: _style(7.8)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _metaGrid(List<_MetaCell> cells) {
    final rows = <pw.TableRow>[];
    for (var i = 0; i < cells.length; i += 2) {
      final left = cells[i];
      final right = i + 1 < cells.length ? cells[i + 1] : null;
      rows.add(
        pw.TableRow(
          children: [
            _metaCell(left),
            _metaCell(right),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _softLine, width: 0.6),
      columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1)},
      children: rows,
    );
  }

  static pw.Widget _metaCell(_MetaCell? cell) {
    if (cell == null) {
      return pw.Container(padding: const pw.EdgeInsets.all(5));
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(cell.label, style: _style(7.0, color: _secondaryText)),
          pw.SizedBox(height: 1),
          pw.Text(cell.value, style: _style(8.2, bold: true)),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd-$mm-${d.year}';
  }

  static String _fmtDateTime(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year} $hh:$min';
  }

  static String _siteAddress(SnaggingProject project) {
    final parts = [
      project.addressLine1,
      project.addressLine2,
      project.postcode,
      project.city
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '-';
    return parts.join(', ');
  }

  static String Function(String) get _slug => (s) =>
      s.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');

  static String _priorityLabel(SnagPriority p) {
    switch (p) {
      case SnagPriority.low:
        return 'Low';
      case SnagPriority.medium:
        return 'Medium';
      case SnagPriority.high:
        return 'High';
    }
  }

  static PdfColor _pdfPriorityColor(SnagPriority p) {
    switch (p) {
      case SnagPriority.low:
        return PdfColor.fromInt(0xFFD97706);
      case SnagPriority.medium:
        return PdfColor.fromInt(0xFFC2410C);
      case SnagPriority.high:
        return PdfColor.fromInt(0xFFB91C1C);
    }
  }

  static String _impactLabel(SnagProgrammeImpact impact) {
    switch (impact) {
      case SnagProgrammeImpact.yes:
        return 'Yes';
      case SnagProgrammeImpact.no:
        return 'No';
      case SnagProgrammeImpact.na:
        return 'N/A';
    }
  }

  static String _statusLabel(SnaggingStatus status) {
    switch (status) {
      case SnaggingStatus.open:
        return 'Open';
      case SnaggingStatus.awaitingVerification:
        return 'Awaiting Verification';
      case SnaggingStatus.approved:
        return 'Approved';
      case SnaggingStatus.returned:
        return 'Rejected / Returned';
    }
  }

  static _StatusBadgeStyle _statusStyle(SnaggingStatus status) {
    switch (status) {
      case SnaggingStatus.approved:
        return _StatusBadgeStyle(_pass, _passBg);
      case SnaggingStatus.returned:
        return _StatusBadgeStyle(_fail, _failBg);
      case SnaggingStatus.open:
      case SnaggingStatus.awaitingVerification:
        return _StatusBadgeStyle(_secondaryText, _panelAlt);
    }
  }

  static pw.Widget _badge(String text, PdfColor fg, PdfColor bg) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(text, style: _style(7.4, bold: true, color: fg)),
    );
  }

  static pw.TextStyle _style(double size,
      {bool bold = false, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? _text,
    );
  }
}

class _MetaCell {
  final String label;
  final String value;
  const _MetaCell(this.label, this.value);
}

class _StatusBadgeStyle {
  final PdfColor foreground;
  final PdfColor background;

  const _StatusBadgeStyle(this.foreground, this.background);
}
