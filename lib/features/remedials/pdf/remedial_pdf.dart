import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/pdf/web_download_stub.dart' if (dart.library.html) '../../surveys/pdf/web_download.dart';
import 'remedial_certificate_settings.dart';

class RemedialPdfBuilder {
  static const _logoAssetPath = kDefaultSystemLogoAssetPath;

  static final PdfColor _text = PdfColor.fromInt(0xFF1F2937);
  static final PdfColor _secondaryText = PdfColor.fromInt(0xFF667085);
  static final PdfColor _headerBg = PdfColor.fromInt(0xFFF7F9FC);
  static final PdfColor _border = PdfColor.fromInt(0xFFD8E0E8);
  static final PdfColor _softLine = PdfColor.fromInt(0xFFE8EDF3);

  static Future<Uint8List> buildCombinedApprovedProjectPdf(
    Survey survey, {
    String companyName = '',
    List<int> companyLogoBytes = const [],
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final approvedDoors = _approvedDoors(survey);
    if (approvedDoors.isEmpty) {
      throw StateError('Official maintenance certificate is available only after manager approval.');
    }
    _validateDoorMaintenanceIntervals(approvedDoors);

    final settings = _effectiveSettings(companyName);
    final logo = await _loadAssetImage(_logoAssetPath, companyLogoBytes: companyLogoBytes);
    final doc = await _buildCertificateDocument(
      survey: survey,
      approvedDoors: approvedDoors,
      logo: logo,
      settings: settings,
      reportHeaderText: reportHeaderText,
      reportFooterText: reportFooterText,
    );
    return doc.save();
  }

  static Future<Uint8List> buildSingleApprovedDoorPdf(
    Survey survey,
    Door door, {
    String companyName = '',
    List<int> companyLogoBytes = const [],
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final approvedDoors = _approvedDoors(survey);
    final isApproved = approvedDoors.any((d) => d.id == door.id);
    if (!isApproved) {
      throw StateError('Official maintenance certificate is available only after manager approval.');
    }
    _validateDoorMaintenanceIntervals([door]);

    final settings = _effectiveSettings(companyName);
    final logo = await _loadAssetImage(_logoAssetPath, companyLogoBytes: companyLogoBytes);
    final doc = await _buildCertificateDocument(
      survey: survey,
      approvedDoors: [door],
      logo: logo,
      settings: settings,
      reportHeaderText: reportHeaderText,
      reportFooterText: reportFooterText,
    );
    return doc.save();
  }

  static Future<Uint8List> buildSeparateApprovedDoorsZip(
    Survey survey, {
    String companyName = '',
    List<int> companyLogoBytes = const [],
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final approvedDoors = _approvedDoors(survey);
    if (approvedDoors.isEmpty) {
      throw StateError('Official maintenance certificate is available only after manager approval.');
    }
    _validateDoorMaintenanceIntervals(approvedDoors);

    final settings = _effectiveSettings(companyName);
    final logo = await _loadAssetImage(_logoAssetPath, companyLogoBytes: companyLogoBytes);
    final archive = Archive();

    for (final door in approvedDoors) {
      final doc = await _buildCertificateDocument(
        survey: survey,
        approvedDoors: [door],
        logo: logo,
        settings: settings,
        reportHeaderText: reportHeaderText,
        reportFooterText: reportFooterText,
      );
      final bytes = await doc.save();
      final name = '${_safeFileName(settings.companyDisplayName)}_RMA058_Maintenance_${_safeDoorRef(door)}.pdf';
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static Future<void> shareOrDownload({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      downloadBytesWeb(bytes: bytes, fileName: fileName, mimeType: mimeType);
    } catch (_) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  static Future<pw.Document> _buildCertificateDocument({
    required Survey survey,
    required List<Door> approvedDoors,
    required pw.ImageProvider? logo,
    required RemedialCertificateSettings settings,
    required String reportHeaderText,
    required String reportFooterText,
  }) async {
    final signatureImage = await _resolveSignatureImage(approvedDoors);

    final doc = pw.Document();
    final scope = _CertificateScope.fromSurvey(survey: survey, doors: approvedDoors, settings: settings);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 24),
        footer: (context) => _pageFooter(
          context: context,
          companyName: settings.companyDisplayName,
          reportFooterText: reportFooterText,
        ),
        build: (context) => [
          _pageHeader(
            logo: logo,
            companyName: settings.companyDisplayName,
            title: 'Fire Door Maintenance Certificate',
            reportHeaderText: reportHeaderText,
          ),
          pw.SizedBox(height: 10),
          _headerDeclarationBlock(scope: scope, signatureImage: signatureImage),
          pw.SizedBox(height: 12),
          _sectionTitle('Maintenance Record Table'),
          pw.SizedBox(height: 6),
          _maintenanceRecordTable(scope),
          pw.SizedBox(height: 8),
          pw.Text(
            'Only manager approved remedial actions are marked as completed in this certificate.',
            style: _style(9),
          ),
          pw.NewPage(),
          _pageHeader(
            logo: logo,
            companyName: settings.companyDisplayName,
            title: 'Photograph Notes / Certificate Notes',
            reportHeaderText: reportHeaderText,
          ),
          pw.SizedBox(height: 12),
          _photoNotesBlock(scope: scope, logo: logo),
          pw.NewPage(),
          _pageHeader(
            logo: logo,
            companyName: settings.companyDisplayName,
            title: 'Photo Evidence Register',
            reportHeaderText: reportHeaderText,
          ),
          pw.SizedBox(height: 10),
          ..._photoEvidenceSections(scope),
        ],
      ),
    );

    return doc;
  }

  static List<Door> _approvedDoors(Survey survey) {
    return survey.doors.where((door) {
      if (door.remedialStatus != RemedialStatus.approved) return false;
      final approved = door.remedialItems.where((i) => i.status == RemedialStatus.approved).toList();
      return approved.isNotEmpty;
    }).toList();
  }

  static void _validateDoorMaintenanceIntervals(List<Door> doors) {
    final invalid = doors.where((d) => d.maintenanceIntervalMonths <= 0).toList();
    if (invalid.isEmpty) return;
    final first = invalid.first;
    final doorLabel = first.doorIdTag.trim().isEmpty ? 'Door ${first.number}' : first.doorIdTag.trim();
    throw StateError('Maintenance interval is required for approved doors. Missing/invalid on $doorLabel.');
  }

  static pw.Widget _pageHeader({
    required pw.ImageProvider? logo,
    required String companyName,
    required String title,
    required String reportHeaderText,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _headerBg,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 120,
            height: 42,
            alignment: pw.Alignment.centerLeft,
            child: logo == null
                ? pw.Text(companyName, style: _style(11.5, bold: true))
                : pw.Image(logo, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  title,
                  textAlign: pw.TextAlign.center,
                  style: _style(13.2, bold: true),
                ),
                if (reportHeaderText.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    reportHeaderText.trim(),
                    textAlign: pw.TextAlign.center,
                    style: _style(8.0, color: _secondaryText),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Container(
            width: 155,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: _softLine),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Company', style: _style(7.2, bold: true, color: _secondaryText)),
                pw.SizedBox(height: 2),
                pw.Text(
                  companyName,
                  textAlign: pw.TextAlign.right,
                  style: _style(7.2, color: _secondaryText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pageFooter({
    required pw.Context context,
    required String companyName,
    required String reportFooterText,
  }) {
    final customFooter = reportFooterText.trim();
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(height: 1, color: _softLine),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                companyName,
                style: _style(7.0, color: _secondaryText),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                customFooter.isEmpty
                    ? 'RMA 058 - Record of Maintenance Activities'
                    : customFooter,
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

  static pw.Widget _headerDeclarationBlock({
    required _CertificateScope scope,
    required pw.ImageProvider? signatureImage,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Table(
            border: pw.TableBorder.all(color: _border),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.8),
              1: pw.FlexColumnWidth(2.2),
              2: pw.FlexColumnWidth(1.8),
              3: pw.FlexColumnWidth(2.2),
            },
            children: [
              _row4(
                'Register Reference Number',
                scope.rmaRegisterReference,
                'Internal Maintenance Project Reference',
                scope.internalMaintenanceJobReference,
              ),
              _row4('Company Name', scope.companyName, 'Approved Maintainer Name', scope.approvedMaintainerName),
              _row4('Approved Maintainer Number', scope.approvedMaintainerNumber, 'Site Address', scope.siteAddress),
            ],
          ),
          pw.SizedBox(height: 10),
          _sectionTitle('Declaration'),
          pw.SizedBox(height: 4),
          pw.Text(scope.declarationText, style: _style(9)),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Signature', style: _style(9, bold: true)),
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 4),
                      height: 42,
                      alignment: pw.Alignment.centerLeft,
                      decoration: pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: _border)),
                      ),
                      child: signatureImage == null
                          ? pw.Text('Signature not provided', style: _style(8))
                          : pw.Image(signatureImage, fit: pw.BoxFit.contain),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text('Approved Maintainer', style: _style(8.2, color: _secondaryText)),
                    pw.Text(scope.approvedMaintainerName, style: _style(8.2, bold: true)),
                  ],
                ),
              ),
              pw.SizedBox(width: 18),
              pw.Container(
                width: 160,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Signature Date', style: _style(9, bold: true)),
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 4),
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      decoration: pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: _border)),
                      ),
                      child: pw.Text(_fmt(scope.approvalDate), style: _style(9)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.TableRow _row4(String l1, String v1, String l2, String v2) {
    return pw.TableRow(
      children: [
        _cellLabel(l1),
        _cellValue(v1),
        _cellLabel(l2),
        _cellValue(v2),
      ],
    );
  }

  static pw.Widget _maintenanceRecordTable(_CertificateScope scope) {
    // Super-header: two solid colour blocks. Flex widths match the sums of each
    // column group (survey 9.0, maintenance 7.0) so the divider aligns with the
    // border between col 6 and col 7 in the main table. No bottom border so the
    // main table's top border acts as the single dividing line.
    final superHeader = pw.Table(
      border: pw.TableBorder(
        left: pw.BorderSide(color: _border),
        top: pw.BorderSide(color: _border),
        right: pw.BorderSide(color: _border),
        verticalInside: pw.BorderSide(color: _border),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(9.0),
        1: pw.FlexColumnWidth(7.0),
      },
      children: [
        pw.TableRow(children: [
          pw.Container(
            color: _headerBg,
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: pw.Text(
              'Survey and Inspection',
              style: _style(8.5, bold: true),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Container(
            color: _headerBg,
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: pw.Text(
              'Maintenance (ARTs) completed',
              style: _style(8.5, bold: true),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ]),
      ],
    );

    final mainTable = pw.Table(
      border: pw.TableBorder.all(color: _border),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.0),
        3: pw.FlexColumnWidth(2.0),
        4: pw.FlexColumnWidth(1.2),
        5: pw.FlexColumnWidth(1.0),
        6: pw.FlexColumnWidth(1.1),
        7: pw.FlexColumnWidth(1.1),
        8: pw.FlexColumnWidth(0.9),
        9: pw.FlexColumnWidth(1.2),
        10: pw.FlexColumnWidth(1.1),
        11: pw.FlexColumnWidth(1.2),
        12: pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(children: [
          pw.Container(color: _headerBg, child: _th('Unique door ref.')),
          pw.Container(color: _headerBg, child: _th('Location of doorset')),
          pw.Container(color: _headerBg, child: _th('Client declared fire resistance period')),
          pw.Container(color: _headerBg, child: _th('Description of issues and/or damage')),
          pw.Container(color: _headerBg, child: _th('Door condition survey completed by')),
          pw.Container(color: _headerBg, child: _th('Grading level assigned')),
          pw.Container(color: _headerBg, child: _th('ARTs required')),
          pw.Container(color: _headerBg, child: _th('ARTs complete (ART No. and Rev No.)')),
          pw.Container(color: _headerBg, child: _th('Maintenance label fitted (Y/N)')),
          pw.Container(color: _headerBg, child: _th('Maintenance completed date')),
          pw.Container(color: _headerBg, child: _th('Maintained by')),
          pw.Container(color: _headerBg, child: _th('Next maintenance due date')),
          pw.Container(color: _headerBg, child: _th('Comments')),
        ]),
        ...scope.rows.map(
          (row) => pw.TableRow(
            children: [
              _td(row.doorRef),
              _td(row.location),
              _td(row.fireResistance),
              _td(row.issueDescription),
              _td(row.surveyCompletedBy),
              _td(row.gradingLevel),
              _td(row.artsRequired),
              _td(row.artsComplete),
              _td(row.maintenanceLabelFitted),
              _td(row.maintenanceCompletedDate),
              _td(row.maintainedBy),
              _td(row.nextMaintenanceDueDate),
              _td(row.comments),
            ],
          ),
        ),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [superHeader, mainTable],
    );
  }

  static pw.Widget _photoNotesBlock({required _CertificateScope scope, required pw.ImageProvider? logo}) {
    final note =
        'Photographs included in this maintenance certificate are traceable to their original inspection and repair records in the system. Thumbnail images and references are acceptable where they remain clearly linked to the original source files.';

    return pw.Stack(
      children: [
        if (logo != null)
          pw.Positioned(
            right: 20,
            top: 20,
            child: pw.Opacity(
              opacity: 0.08,
              child: pw.SizedBox(width: 220, height: 160, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            ),
          ),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _border),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sectionTitle('Certificate Notes'),
              pw.SizedBox(height: 6),
              pw.Text(note, style: _style(10)),
              pw.SizedBox(height: 10),
              pw.Text(
                'Project: ${scope.projectName}   |   Project Ref: ${scope.internalMaintenanceJobReference}',
                style: _style(9),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Maintainer: ${scope.approvedMaintainerName}', style: _style(9)),
              pw.SizedBox(height: 2),
              pw.Text('Approved Maintainer Number: ${scope.approvedMaintainerNumber}', style: _style(9)),
              pw.SizedBox(height: 4),
              pw.Text('Company: ${scope.companyName}', style: _style(9)),
            ],
          ),
        ),
      ],
    );
  }

  static List<pw.Widget> _photoEvidenceSections(_CertificateScope scope) {
    final widgets = <pw.Widget>[];
    for (final row in scope.rows) {
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _border),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Door: ${row.doorRef}', style: _style(11, bold: true)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: _border),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.0),
                  1: pw.FlexColumnWidth(1.9),
                  2: pw.FlexColumnWidth(1.9),
                  3: pw.FlexColumnWidth(1.9),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: _headerBg),
                    children: [
                      _th('Unique door ref.'),
                      _th('Photographs prior to maintenance'),
                      _th('Post/during maintenance photographs'),
                      _th('Final manager approval evidence'),
                    ],
                  ),
                  ..._photoEvidenceRows(row),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  static List<pw.TableRow> _photoEvidenceRows(_MaintenanceRow row) {
    final rows = <pw.TableRow>[];
    final prior = _chunk(row.beforePhotos, 2);
    final post = _chunk(row.afterPhotos, 2);
    final approval = _chunk(row.approvalPhotos, 2);
    final maxRows = [prior.length, post.length, approval.length].fold<int>(1, (a, b) => b > a ? b : a);

    for (var i = 0; i < maxRows; i++) {
      rows.add(
        pw.TableRow(
          children: [
            _td(i == 0 ? row.doorRef : ''),
            _photoCell(i < prior.length ? prior[i] : const []),
            _photoCell(i < post.length ? post[i] : const []),
            _photoCell(i < approval.length ? approval[i] : const []),
          ],
        ),
      );
    }
    return rows;
  }

  static pw.Widget _photoCell(List<Uint8List> photos) {
    if (photos.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text('-', style: _style(8)),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final bytes in photos)
            pw.Container(
              width: 72,
              height: 58,
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _border)),
              child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
            ),
        ],
      ),
    );
  }

  static List<List<Uint8List>> _chunk(List<Uint8List> source, int size) {
    if (source.isEmpty) return const [];
    final out = <List<Uint8List>>[];
    for (var i = 0; i < source.length; i += size) {
      out.add(source.sublist(i, i + size > source.length ? source.length : i + size));
    }
    return out;
  }

  static pw.Widget _sectionTitle(String text) => pw.Text(text, style: _style(11, bold: true));

  static pw.Widget _cellLabel(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(text, style: _style(8.5, bold: true)),
      );

  static pw.Widget _cellValue(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(_safe(text), style: _style(8.5)),
      );

  static pw.Widget _th(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(text, style: _style(7.7, bold: true)),
      );

  static pw.Widget _td(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(_safe(text), style: _style(7.5)),
      );

  static String _safe(String value) {
    final v = value.trim();
    return v.isEmpty ? '-' : v;
  }

  static String _safeDoorRef(Door door) {
    final ref = door.doorIdTag.trim();
    if (ref.isNotEmpty) return ref;
    return 'Door ${door.number.toString().padLeft(3, '0')}';
  }

  static String _fmt(DateTime? date) {
    if (date == null) return '-';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year}';
  }

  static Future<pw.ImageProvider?> _resolveSignatureImage(List<Door> doors) async {
    DateTime? latestDate;
    Approval? latestApproval;
    for (final door in doors) {
      for (final item in door.remedialItems) {
        final approval = item.approval;
        if (approval == null) {
          continue;
        }
        final hasBytes = approval.signatureImageBytes.isNotEmpty;
        final hasAsset = approval.signatureAssetPath.trim().isNotEmpty;
        if (!hasBytes && !hasAsset) {
          continue;
        }

        if (latestDate == null || approval.approvedDate.isAfter(latestDate)) {
          latestDate = approval.approvedDate;
          latestApproval = approval;
        }
      }
    }

    if (latestApproval == null) {
      return null;
    }

    if (latestApproval.signatureImageBytes.isNotEmpty) {
      return pw.MemoryImage(Uint8List.fromList(latestApproval.signatureImageBytes));
    }

    final assetPath = latestApproval.signatureAssetPath.trim();
    if (assetPath.isNotEmpty) {
      return _loadAssetImage(assetPath);
    }

    return null;
  }

  static RemedialCertificateSettings _effectiveSettings(String companyName) {
    return RemedialCertificateSettings(
      companyDisplayName: companyName.trim().isEmpty
          ? kDefaultSystemCompanyName
          : companyName.trim(),
      approvedMaintainerName: defaultRemedialCertificateSettings.approvedMaintainerName,
      approvedMaintainerNumber: defaultRemedialCertificateSettings.approvedMaintainerNumber,
      rmaRegisterReference: defaultRemedialCertificateSettings.rmaRegisterReference,
      defaultSignatureImage: defaultRemedialCertificateSettings.defaultSignatureImage,
      declarationText: defaultRemedialCertificateSettings.declarationText,
    );
  }

  static pw.TextStyle _style(double size, {bool bold = false, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? _text,
    );
  }

  static Future<pw.ImageProvider?> _loadAssetImage(
    String path, {
    List<int> companyLogoBytes = const [],
  }) async {
    if (companyLogoBytes.isNotEmpty) {
      return pw.MemoryImage(Uint8List.fromList(companyLogoBytes));
    }
    try {
      final data = await rootBundle.load(path);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static String _safeFileName(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'Company' : cleaned;
  }
}

class _CertificateScope {
  final String rmaRegisterReference;
  final String internalMaintenanceJobReference;
  final String companyName;
  final String approvedMaintainerName;
  final String approvedMaintainerNumber;
  final String siteAddress;
  final String declarationText;
  final DateTime approvalDate;
  final String projectName;
  final List<_MaintenanceRow> rows;

  const _CertificateScope({
    required this.rmaRegisterReference,
    required this.internalMaintenanceJobReference,
    required this.companyName,
    required this.approvedMaintainerName,
    required this.approvedMaintainerNumber,
    required this.siteAddress,
    required this.declarationText,
    required this.approvalDate,
    required this.projectName,
    required this.rows,
  });

  factory _CertificateScope.fromSurvey({
    required Survey survey,
    required List<Door> doors,
    required RemedialCertificateSettings settings,
  }) {
    final rows = doors.map((door) => _MaintenanceRow.fromDoor(door, settings)).toList();
    final latestApproval = rows
        .where((r) => r.approvalDate != null)
        .map((r) => r.approvalDate!)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    final siteAddress = [
      survey.addressLine1,
      survey.addressLine2,
      survey.cityTown,
      survey.postCode,
      survey.siteAddress,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().join(', ');

    final internalRefOverride = rows
        .map((r) => r.certificateJobReferenceOverride.trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');

    final maintainerNameOverride = rows
        .map((r) => r.approvedMaintainerName.trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');

    final maintainerNumberOverride = rows
        .map((r) => r.approvedMaintainerNumber.trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');

    final projectRegisterReference = survey.registerReference.trim();
    final generatedSuffix = survey.reference.trim().isEmpty
      ? (survey.id.length <= 8 ? survey.id.toUpperCase() : survey.id.substring(0, 8).toUpperCase())
      : survey.reference.trim();
    final generatedRegisterReference =
      'REG-${survey.createdAt.year}${survey.createdAt.month.toString().padLeft(2, '0')}${survey.createdAt.day.toString().padLeft(2, '0')}-$generatedSuffix';

    return _CertificateScope(
      rmaRegisterReference: projectRegisterReference.isEmpty ? generatedRegisterReference : projectRegisterReference,
      internalMaintenanceJobReference: internalRefOverride.isEmpty
          ? (survey.reference.trim().isEmpty ? survey.id : survey.reference.trim())
          : internalRefOverride,
      companyName: settings.companyDisplayName,
      approvedMaintainerName: maintainerNameOverride.isEmpty ? settings.approvedMaintainerName : maintainerNameOverride,
      approvedMaintainerNumber: maintainerNumberOverride.isEmpty ? settings.approvedMaintainerNumber : maintainerNumberOverride,
      siteAddress: siteAddress.isEmpty ? '-' : siteAddress,
      declarationText: settings.declarationText,
      approvalDate: latestApproval ?? DateTime.now(),
      projectName: survey.reportName.trim().isEmpty ? survey.siteName : survey.reportName,
      rows: rows,
    );
  }
}

class _MaintenanceRow {
  final String doorRef;
  final String location;
  final String fireResistance;
  final String issueDescription;
  final String surveyCompletedBy;
  final String gradingLevel;
  final String artsRequired;
  final String artsComplete;
  final String maintenanceLabelFitted;
  final String maintenanceCompletedDate;
  final String maintainedBy;
  final String nextMaintenanceDueDate;
  final String comments;
  final DateTime? approvalDate;
  final String approvedMaintainerName;
  final String approvedMaintainerNumber;
  final String certificateJobReferenceOverride;
  final List<Uint8List> beforePhotos;
  final List<Uint8List> afterPhotos;
  final List<Uint8List> approvalPhotos;
  final List<Uint8List> rejectionPhotos;

  const _MaintenanceRow({
    required this.doorRef,
    required this.location,
    required this.fireResistance,
    required this.issueDescription,
    required this.surveyCompletedBy,
    required this.gradingLevel,
    required this.artsRequired,
    required this.artsComplete,
    required this.maintenanceLabelFitted,
    required this.maintenanceCompletedDate,
    required this.maintainedBy,
    required this.nextMaintenanceDueDate,
    required this.comments,
    required this.approvalDate,
    required this.approvedMaintainerName,
    required this.approvedMaintainerNumber,
    required this.certificateJobReferenceOverride,
    required this.beforePhotos,
    required this.afterPhotos,
    required this.approvalPhotos,
    required this.rejectionPhotos,
  });

  factory _MaintenanceRow.fromDoor(Door door, RemedialCertificateSettings settings) {
    final approvedItems = door.remedialItems.where((i) => i.status == RemedialStatus.approved).toList();

    final artsRequiredSet = <String>{};
    final issueDescriptions = <String>[];
    final before = <Uint8List>[];
    final after = <Uint8List>[];
    final approvalPhotos = <Uint8List>[];
    final rejection = <Uint8List>[];

    for (final item in approvedItems) {
      issueDescriptions.add(_normalizeIssueTitle(item.title));
      if (item.actionMappings.isNotEmpty) {
        for (final mapping in item.actionMappings) {
          final actual = (mapping['actualArtCode'] ?? '').trim();
          final match = RegExp(r'ART(\d{2})', caseSensitive: false).firstMatch(actual);
          if (match != null) {
            artsRequiredSet.add('ART ${match.group(1)} Rev 1');
          }
        }
      } else {
        final issue = door.issues.where((e) => e.id == item.issueId).cast<Issue?>().firstWhere((e) => e != null, orElse: () => null);
        if (issue != null && issue.artCode > 0) {
          artsRequiredSet.add('ART ${issue.artCode} Rev 1');
        }
      }

      for (final p in item.originalInspectionPhotos) {
        before.add(Uint8List.fromList(p.bytes));
      }
      for (final p in item.afterRepairPhotos) {
        after.add(Uint8List.fromList(p.bytes));
      }
      for (final p in item.managerApprovalPhotos) {
        approvalPhotos.add(Uint8List.fromList(p.bytes));
      }
      for (final p in item.managerRejectionPhotos) {
        rejection.add(Uint8List.fromList(p.bytes));
      }
    }

    final completedDate = approvedItems
        .where((i) => i.completedDate != null)
        .map((i) => i.completedDate!)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    final latestApproval = approvedItems
        .where((i) => i.approvedAt != null)
        .map((i) => i.approvedAt!)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    final approval = approvedItems.map((e) => e.approval).firstWhere((e) => e != null, orElse: () => null);

    final maintainedBy = approvedItems
        .map((i) => i.completedBy.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .join(', ');

    final surveyCompletedBy = approvedItems
        .map((i) => i.submittedBy.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .join(', ');

    final intervalMonths = door.maintenanceIntervalMonths > 0 ? door.maintenanceIntervalMonths : 12;
    final maintenanceBaseDate = completedDate ?? latestApproval ?? DateTime.now();
    final nextDue = _addMonths(maintenanceBaseDate, intervalMonths);
    final intervalText = 'Maintenance Interval: $intervalMonths month${intervalMonths == 1 ? '' : 's'}';
    final managerComment = approval?.finalManagerComments.trim().isNotEmpty == true
      ? approval!.finalManagerComments.trim()
      : (approval?.comment.trim().isNotEmpty == true ? approval!.comment.trim() : '');
    final fullComment = managerComment.isEmpty ? intervalText : '$intervalText | $managerComment';

    return _MaintenanceRow(
      doorRef: door.doorIdTag.trim().isEmpty ? 'Door ${door.number}' : door.doorIdTag.trim(),
      location: [door.floor.trim(), door.area.trim()].where((v) => v.isNotEmpty).join(' / '),
      fireResistance: door.fireRating.name.toUpperCase(),
      issueDescription: issueDescriptions.isEmpty ? '-' : issueDescriptions.join('; '),
      surveyCompletedBy: surveyCompletedBy.isEmpty ? '-' : surveyCompletedBy,
      gradingLevel: door.gradingLevel.name,
      artsRequired: artsRequiredSet.isEmpty ? '-' : artsRequiredSet.join(', '),
      artsComplete: artsRequiredSet.isEmpty ? '-' : artsRequiredSet.join(', '),
      maintenanceLabelFitted: (approval?.maintenanceLabelFitted ?? true) ? 'Y' : 'N',
      maintenanceCompletedDate: RemedialPdfBuilder._fmt(completedDate),
      maintainedBy: maintainedBy.isEmpty ? '-' : maintainedBy,
      nextMaintenanceDueDate: RemedialPdfBuilder._fmt(nextDue),
        comments: fullComment,
      approvalDate: latestApproval,
      approvedMaintainerName: approval?.approvedMaintainerName.trim().isNotEmpty == true
          ? approval!.approvedMaintainerName.trim()
          : settings.approvedMaintainerName,
      approvedMaintainerNumber: approval?.approvedMaintainerNumber.trim().isNotEmpty == true
          ? approval!.approvedMaintainerNumber.trim()
          : settings.approvedMaintainerNumber,
      certificateJobReferenceOverride: approval?.certificateJobReferenceOverride ?? '',
      beforePhotos: before,
      afterPhotos: after,
      approvalPhotos: approvalPhotos,
      rejectionPhotos: rejection,
    );
  }

  static DateTime _addMonths(DateTime date, int months) {
    final safeMonths = months <= 0 ? 12 : months;
    final monthIndex = date.month - 1 + safeMonths;
    final year = date.year + (monthIndex ~/ 12);
    final month = (monthIndex % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day <= lastDay ? date.day : lastDay;
    return DateTime(year, month, day);
  }

  static String _normalizeIssueTitle(String raw) {
    final noPrefix = raw.trim().replaceFirst(RegExp(r'^CHECK:'), '');
    final withSpaces = noPrefix.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    final words = withSpaces
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ')
        .trim();
    return words.isEmpty ? 'Inspection Issue' : words;
  }
}
