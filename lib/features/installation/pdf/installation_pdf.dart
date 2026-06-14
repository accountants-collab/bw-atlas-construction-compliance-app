import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/pdf/web_download_stub.dart' if (dart.library.html) '../../surveys/pdf/web_download.dart';

class InstallationPdfBuilder {
  static const _logoAssetPath = kDefaultSystemLogoAssetPath;

  static final PdfColor _text = PdfColor.fromInt(0xFF1F2937);
  static final PdfColor _secondaryText = PdfColor.fromInt(0xFF667085);
  static final PdfColor _sectionBg = PdfColor.fromInt(0xFFF7F9FC);
  static final PdfColor _border = PdfColor.fromInt(0xFFD8E0E8);
  static final PdfColor _ok = PdfColor.fromInt(0xFF15803D);
  static final PdfColor _okBg = PdfColor.fromInt(0xFFF3FAF5);
  static final PdfColor _softLine = PdfColor.fromInt(0xFFE8EDF3);

  static Future<Uint8List> buildCombinedApprovedProjectPdf(
    Survey survey, {
    List<int> companyLogoBytes = const [],
    String companyName = kDefaultSystemCompanyName,
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final approvedItems = _approvedItems(survey);
    if (approvedItems.isEmpty) {
      throw StateError('Installation/Handover PDF is only available after manager approval.');
    }

    final doc = pw.Document();
    final logo = await _loadLogo(companyLogoBytes);
    for (final item in approvedItems) {
      doc.addPage(
        _itemPage(
          survey: survey,
          item: item,
          logo: logo,
          companyName: companyName,
          reportHeaderText: reportHeaderText,
          reportFooterText: reportFooterText,
        ),
      );
    }
    return doc.save();
  }

  static Future<Uint8List> buildSeparateApprovedItemsZip(
    Survey survey, {
    List<int> companyLogoBytes = const [],
    String companyName = kDefaultSystemCompanyName,
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final approvedItems = _approvedItems(survey);
    if (approvedItems.isEmpty) {
      throw StateError('Installation/Handover PDF is only available after manager approval.');
    }

    final archive = Archive();
    final logo = await _loadLogo(companyLogoBytes);
    for (final item in approvedItems) {
      final doc = pw.Document();
      doc.addPage(
        _itemPage(
          survey: survey,
          item: item,
          logo: logo,
          companyName: companyName,
          reportHeaderText: reportHeaderText,
          reportFooterText: reportFooterText,
        ),
      );
      final bytes = await doc.save();
      final fileName = '${_safeFileName(companyName)}_Installation_${_fileSafeItemRef(item)}.pdf';
      archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static Future<Uint8List> buildSingleApprovedItemPdf(
    Survey survey,
    PreInstallItem item, {
    List<int> companyLogoBytes = const [],
    String companyName = kDefaultSystemCompanyName,
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final approvedItems = _approvedItems(survey);
    final isApproved = approvedItems.any((i) => i.id == item.id);
    if (!isApproved) {
      throw StateError('Installation/Handover PDF is only available after manager approval.');
    }

    final doc = pw.Document();
    final logo = await _loadLogo(companyLogoBytes);
    doc.addPage(
      _itemPage(
        survey: survey,
        item: item,
        logo: logo,
        companyName: companyName,
        reportHeaderText: reportHeaderText,
        reportFooterText: reportFooterText,
      ),
    );
    return doc.save();
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

  static List<PreInstallItem> _approvedItems(Survey survey) {
    return survey.preInstallItems.where((i) => i.status == InstallationStatus.approved).toList();
  }

  static pw.Page _itemPage({
    required Survey survey,
    required PreInstallItem item,
    required pw.ImageProvider? logo,
    required String companyName,
    required String reportHeaderText,
    required String reportFooterText,
  }) {
    final linkedDoor = _findLinkedDoor(survey: survey, item: item);
    final isReplacementTask = item.fullReplacementTask || (linkedDoor?.replacementRequired ?? false);
    final completedTasks = item.installationTasks
        .where((t) => t.status == InstallationTaskStatus.completed || t.status == InstallationTaskStatus.notApplicable)
        .length;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(logo: logo, companyName: companyName, reportHeaderText: reportHeaderText),
          pw.SizedBox(height: 12),
          _section(
            title: 'Project and Handover Details',
            child: _details([
              ['Project', _safeSurveyName(survey)],
              ['Project Reference', _safe(survey.reference)],
              ['Opening Ref', _safe(item.doorRef)],
              ['Location', _safe(item.location)],
              ['Fire Rating', _safe(item.fireRating)],
              if (isReplacementTask) ['Replacement Required', 'Yes - Full Doorset Replacement'],
              if (isReplacementTask)
                [
                  'Original Inspection Result',
                  linkedDoor == null ? '-' : linkedDoor.result.name.toUpperCase(),
                ],
              if (isReplacementTask)
                [
                  'Replacement Opening Width (mm)',
                  linkedDoor?.replacementDoor1Width.trim().isNotEmpty == true
                      ? linkedDoor!.replacementDoor1Width.trim()
                      : _safe(item.openingWidth),
                ],
              if (isReplacementTask)
                [
                  'Replacement Opening Height (mm)',
                  linkedDoor?.replacementDoor1Height.trim().isNotEmpty == true
                      ? linkedDoor!.replacementDoor1Height.trim()
                      : _safe(item.openingHeight),
                ],
              if (isReplacementTask && linkedDoor != null && linkedDoor.configuration != DoorConfiguration.singleLeaf)
                [
                  'Leaf 1 Approx Width (mm)',
                  linkedDoor.replacementDoor2Width.trim().isEmpty ? '-' : linkedDoor.replacementDoor2Width.trim(),
                ],
              if (isReplacementTask && linkedDoor != null && linkedDoor.configuration != DoorConfiguration.singleLeaf)
                [
                  'Leaf 2 Approx Width (mm)',
                  linkedDoor.replacementDoor2Height.trim().isEmpty ? '-' : linkedDoor.replacementDoor2Height.trim(),
                ],
              if (linkedDoor != null)
                ['Maintenance Interval (months)', linkedDoor.maintenanceIntervalMonths.toString()],
              ['Completed By', _safe(item.completedBy)],
              ['Approved By', _safe(item.approvedBy)],
              ['Completion Date', _fmtDateTime(item.completedDate)],
              ['Approval Date', _fmtDateTime(item.approvedAt)],
              ['Approver Signature Source', _safeLabel(item.approval?.signatureMethod ?? '')],
              [
                'Approved Maintainer / Certificate Number',
                _safe(item.approval?.approvedMaintainerNumber ?? ''),
              ],
              ['DRW References', survey.projectDrawings.isEmpty ? 'None attached' : '${survey.projectDrawings.length} drawing(s) attached'],
              ['Status', 'Approved'],
            ]),
          ),
          if (item.approval?.signatureImageBytes.isNotEmpty == true) ...[
            pw.SizedBox(height: 10),
            _section(
              title: 'Manager Approval Signature',
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      width: double.infinity,
                      height: 96,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _border),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Image(
                        pw.MemoryImage(Uint8List.fromList(item.approval!.signatureImageBytes)),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Container(
                    width: 170,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Approver', style: _style(8.5, bold: true, color: _secondaryText)),
                        pw.Text(_safe(item.approvedBy), style: _style(9)),
                        pw.SizedBox(height: 4),
                        pw.Text('Role', style: _style(8.5, bold: true, color: _secondaryText)),
                        pw.Text('Manager', style: _style(9)),
                        pw.SizedBox(height: 4),
                        pw.Text('Date', style: _style(8.5, bold: true, color: _secondaryText)),
                        pw.Text(_fmtDateTime(item.approvedAt), style: _style(9)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          pw.SizedBox(height: 10),
          _section(
            title: 'Door Specification Summary',
            child: _details([
              ['Door Configuration', _safeLabel(item.configuration)],
              ['Handing', _safeLabel(item.handingMode)],
              ['Glazing / Vision', _safeLabel(item.glazingType)],
              ['Door Material', _safeLabel(item.doorMaterial)],
              ['Frame Material', _safeLabel(item.frameMaterial)],
              ['Finish / Colour', _safeLabel('${item.finishType} ${item.colourRal}'.trim())],
            ]),
          ),
          pw.SizedBox(height: 10),
          _section(
            title: 'Final Installation Checklist',
            child: _taskTable(item.installationTasks, completedTasks),
          ),
          pw.SizedBox(height: 10),
          _section(
            title: 'Photo Evidence',
            child: _photoEvidence(item),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: pw.BoxDecoration(
              color: _okBg,
              border: pw.Border.all(color: _ok),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'FINAL COMPLETED WORK: APPROVED FOR HANDOVER',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: _ok),
            ),
          ),
          pw.Spacer(),
          _footer(companyName, reportFooterText, item.approvedAt),
        ],
      ),
    );
  }

  static pw.Widget _header({
    required pw.ImageProvider? logo,
    required String companyName,
    required String reportHeaderText,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _sectionBg,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.SizedBox(width: 108, height: 38, child: pw.Image(logo, fit: pw.BoxFit.contain))
        else
          pw.SizedBox(width: 108, height: 38),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'INSTALLATION AND HANDOVER RECORD',
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
          width: 150,
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
                companyName.trim().isEmpty ? kDefaultSystemCompanyName : companyName.trim(),
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

  static pw.Widget _footer(String companyName, String reportFooterText, DateTime? issuedDate) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _softLine))),
      child: pw.Row(
        children: [
          pw.Text(
            companyName.trim().isEmpty ? kDefaultSystemCompanyName : companyName.trim(),
            style: _style(7.2, color: _secondaryText),
          ),
          pw.Expanded(
            child: pw.Text(
              'Issued Date: ${_fmt(issuedDate)}',
              textAlign: pw.TextAlign.center,
              style: _style(7.2, color: _secondaryText),
            ),
          ),
          pw.Text(
            reportFooterText.trim().isEmpty ? 'Installation & Handover Record' : reportFooterText.trim(),
            style: _style(7.2, color: _secondaryText),
          ),
          pw.SizedBox(width: 10),
          pw.Text('Page 1 of 1', style: _style(7.2, color: _secondaryText)),
        ],
      ),
    );
  }

  static pw.Widget _section({required String title, required pw.Widget child}) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _sectionBg,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(title, style: _style(12, bold: true)),
          pw.SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  static pw.Widget _details(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: _border),
      columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(3)},
      children: rows
          .map(
            (row) => pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(row[0], style: _style(10, bold: true)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(row[1], style: _style(10)),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  static pw.Widget _taskTable(List<InstallationTask> tasks, int completedTasks) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text('Completed Tasks: $completedTasks/${tasks.length}', style: _style(10, bold: true)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _border),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.3),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(2.1),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _sectionBg),
              children: [
                _th('Task'),
                _th('Category'),
                _th('Status'),
                _th('Worker Note'),
              ],
            ),
            ...tasks.map(
              (task) => pw.TableRow(
                children: [
                  _td(task.title),
                  _td(task.category),
                  _td(_taskStatus(task.status)),
                  _td(task.workerNote),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _photoEvidence(PreInstallItem item) {
    if (item.preInstallPhotos.isEmpty &&
        item.installationPhotos.isEmpty &&
        item.managerApprovalPhotos.isEmpty) {
      return pw.Text('No photos attached', style: _style(10));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Before (Original Survey)', style: _style(10, bold: true)),
        pw.SizedBox(height: 5),
        if (item.preInstallPhotos.isEmpty)
          pw.Text('No before photos attached', style: _style(9))
        else
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final photo in item.preInstallPhotos) _photoTile(photo.bytes, 'Before'),
            ],
          ),
        pw.SizedBox(height: 10),
        pw.Text('During / After Installation', style: _style(10, bold: true)),
        pw.SizedBox(height: 5),
        if (item.installationPhotos.isEmpty)
          pw.Text('No installation photos attached', style: _style(9))
        else
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < item.installationPhotos.length; i++)
                _photoTile(item.installationPhotos[i].bytes, 'Installation ${i + 1}'),
            ],
          ),
        pw.SizedBox(height: 10),
        pw.Text('Final Manager Approval Evidence', style: _style(10, bold: true)),
        pw.SizedBox(height: 5),
        if (item.managerApprovalPhotos.isEmpty)
          pw.Text('No manager approval evidence attached', style: _style(9))
        else
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < item.managerApprovalPhotos.length; i++)
                _photoTile(item.managerApprovalPhotos[i].bytes, 'Manager approval ${i + 1}'),
            ],
          ),
      ],
    );
  }

  static pw.Widget _photoTile(List<int> bytes, String caption) {
    final image = pw.MemoryImage(Uint8List.fromList(bytes));
    return pw.Container(
      width: 160,
      height: 140,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Expanded(child: pw.Image(image, fit: pw.BoxFit.cover)),
          pw.SizedBox(height: 3),
          pw.Text(caption, style: _style(8), maxLines: 1),
        ],
      ),
    );
  }

  static pw.Widget _th(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, style: _style(9, bold: true)),
      );

  static pw.Widget _td(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text.trim().isEmpty ? '-' : text, style: _style(9)),
      );

  static String _taskStatus(InstallationTaskStatus status) {
    switch (status) {
      case InstallationTaskStatus.notCompleted:
        return 'Not Completed';
      case InstallationTaskStatus.completed:
        return 'Completed';
      case InstallationTaskStatus.notApplicable:
        return 'N/A';
    }
  }

  static String _safe(String value) => value.trim().isEmpty ? '-' : value.trim();

  static String _safeLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return '-';
    final withSpaces = cleaned.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return withSpaces
        .replaceAll('_', ' ')
        .split(' ')
        .where((e) => e.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  static String _safeSurveyName(Survey survey) => _safe(survey.reportName.isEmpty ? survey.siteName : survey.reportName);

  static Door? _findLinkedDoor({required Survey survey, required PreInstallItem item}) {
    final linkedDoorId = item.linkedDoorId.trim();
    if (linkedDoorId.isEmpty) return null;
    for (final door in survey.doors) {
      if (door.id == linkedDoorId) return door;
    }
    return null;
  }

  static String _fileSafeItemRef(PreInstallItem item) => _safe(item.doorRef).replaceAll(' ', '_');

  static String _safeFileName(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'Company' : cleaned;
  }

  static String _fmt(DateTime? date) {
    if (date == null) return '-';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year}';
  }

  static String _fmtDateTime(DateTime? date) {
    if (date == null) return '-';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year} $hh:$min';
  }

  static pw.TextStyle _style(double size, {bool bold = false, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? _text,
    );
  }

  static Future<pw.ImageProvider?> _loadLogo(List<int> companyLogoBytes) async {
    if (companyLogoBytes.isNotEmpty) {
      return pw.MemoryImage(Uint8List.fromList(companyLogoBytes));
    }
    final bytes = await _loadAssetBytes(_logoAssetPath);
    return bytes == null ? null : pw.MemoryImage(bytes);
  }

  static Future<Uint8List?> _loadAssetBytes(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}