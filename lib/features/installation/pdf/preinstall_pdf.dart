import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/pdf/web_download_stub.dart'
    if (dart.library.html) '../../surveys/pdf/web_download.dart';

class PreInstallPdfBuilder {
  static const _logoAssetPath = kDefaultSystemLogoAssetPath;
  static const double _pageMargin = 24;
  static const double _sectionGap = 7;
  static const double _tableCellPadding = 4.2;
  static const double _tableCellPaddingCompact = 3.0;
  static final double _contentWidth =
      PdfPageFormat.a4.width - (_pageMargin * 2);
  static final double _photoTileWidth = (_contentWidth - 8) / 2;

  static final PdfColor _text = PdfColor.fromInt(0xFF1F2937);
  static final PdfColor _secondaryText = PdfColor.fromInt(0xFF667085);
  static final PdfColor _line = PdfColor.fromInt(0xFFD8E0E8);
  static final PdfColor _softLine = PdfColor.fromInt(0xFFE8EDF3);
  static final PdfColor _panel = PdfColor.fromInt(0xFFFFFFFF);
  static final PdfColor _panelAlt = PdfColor.fromInt(0xFFF8FAFC);
  static final PdfColor _sectionTint = PdfColor.fromInt(0xFFF7F9FC);
  static final PdfColor _info = PdfColor.fromInt(0xFF305F9C);

  static Future<Uint8List> buildCombinedProjectPdf(
    Survey survey, {
    List<int> companyLogoBytes = const [],
    String companyName = kDefaultSystemCompanyName,
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final doc = pw.Document();
    final logo = await _loadLogo(companyLogoBytes);
    final generatedAt = DateTime.now();
    final exportItems = survey.preInstallItems
        .where((item) => isSpecificationOrderWorkflowType(item.surveyType))
        .toList();

    for (final item in exportItems) {
      _addSpecificationPage(
        doc: doc,
        survey: survey,
        item: item,
        logo: logo,
        companyName: companyName,
        reportHeaderText: reportHeaderText,
        reportFooterText: reportFooterText,
        generatedAt: generatedAt,
      );
    }

    if (exportItems.isEmpty) {
      _addNoExportableItemsPage(
        doc: doc,
        logo: logo,
        companyName: companyName,
        generatedAt: generatedAt,
      );
    }

    return doc.save();
  }

  static Future<Uint8List> buildSeparateItemsZip(
    Survey survey, {
    List<int> companyLogoBytes = const [],
    String companyName = kDefaultSystemCompanyName,
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final archive = Archive();
    final logo = await _loadLogo(companyLogoBytes);
    final generatedAt = DateTime.now();
    final exportItems = survey.preInstallItems
        .where((item) => isSpecificationOrderWorkflowType(item.surveyType))
        .toList();

    for (final item in exportItems) {
      final doc = pw.Document();
      _addSpecificationPage(
        doc: doc,
        survey: survey,
        item: item,
        logo: logo,
        companyName: companyName,
        reportHeaderText: reportHeaderText,
        reportFooterText: reportFooterText,
        generatedAt: generatedAt,
      );
      final bytes = await doc.save();
      final fileName =
          '${_safeFile(companyName)}_Door_Spec_${_safeFile(item.doorRef.isEmpty ? item.id : item.doorRef)}.pdf';
      archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
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

  static void _addSpecificationPage({
    required pw.Document doc,
    required Survey survey,
    required PreInstallItem item,
    required pw.ImageProvider? logo,
    required String companyName,
    required String reportHeaderText,
    required String reportFooterText,
    required DateTime generatedAt,
  }) {
    final selectedFeatures = item.features.where((f) => f.selected).toList();
    final extras = _extrasList(item, selectedFeatures);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_pageMargin),
        header: (context) => _pageHeader(
          logo: logo,
          companyName: companyName,
          reportHeaderText: reportHeaderText,
          survey: survey,
          item: item,
          generatedAt: generatedAt,
        ),
        footer: (context) => _pageFooter(
          context: context,
          reportFooterText: reportFooterText,
          generatedAt: generatedAt,
        ),
        build: (_) => [
          _sectionCard(
            title: 'Project Details',
            child: _projectDetailsTable(
              survey: survey,
              item: item,
              generatedAt: generatedAt,
            ),
          ),
          pw.SizedBox(height: _sectionGap),
          _sectionCard(
            title: 'Door / Doorset Specification',
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _doorSpecTable(item),
                pw.SizedBox(height: 8),
                _doorPreview(item),
                if (extras.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text('Extras', style: _style(8.5, bold: true)),
                  pw.SizedBox(height: 3),
                  _chips(extras),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: _sectionGap),
          _sectionCard(
            title: 'Measurements',
            child: _measurementsSection(item),
          ),
          pw.SizedBox(height: _sectionGap),
          _sectionCard(
            title: 'Ironmongery / Extras',
            child: _ironmongerySection(item, selectedFeatures),
          ),
          pw.SizedBox(height: _sectionGap),
          _sectionCard(
            title: 'Materials & Finish',
            child: _materialsTable(item),
          ),
          if (item.preInstallPhotos.isNotEmpty) ...[
            pw.SizedBox(height: _sectionGap),
            _sectionCard(
              title: 'Photos',
              child: _photoGrid(item.preInstallPhotos),
            ),
          ],
          if (_hasText(item.manufactureNotes) ||
              _hasText(item.preInstallComments)) ...[
            pw.SizedBox(height: _sectionGap),
            _sectionCard(
              title: 'Notes for Manufacture',
              child: _notesSection(item),
            ),
          ],
          pw.SizedBox(height: _sectionGap),
          _sectionCard(
            title: 'Inspector Declaration / Disclaimer',
            child: _inspectorDisclaimerSection(survey, generatedAt),
          ),
        ],
      ),
    );
  }

  static void _addNoExportableItemsPage({
    required pw.Document doc,
    required pw.ImageProvider? logo,
    required String companyName,
    required DateTime generatedAt,
  }) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_pageMargin),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _simpleTopBar(logo: logo, companyName: companyName),
            pw.SizedBox(height: 16),
            pw.Text(
              'Factory / Supplier Specification Sheet',
              style: _style(16, bold: true),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'No exportable pre-installation items found. Installation Only items are excluded from this document.',
              style: _style(10),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Generated: ${_fmtDateTime(generatedAt)}',
              style: _style(8.5, color: _secondaryText),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pageHeader({
    required pw.ImageProvider? logo,
    required String companyName,
    required String reportHeaderText,
    required Survey survey,
    required PreInstallItem item,
    required DateTime generatedAt,
  }) {
    final titleCompany = _safe(companyName).isEmpty
        ? kDefaultSystemCompanyName
        : _safe(companyName);

    final summaryRows = <List<String>>[
      ['Workflow', preInstallWorkflowTypeLabel(item.surveyType)],
      ['Fire rating', _safe(item.fireRating)],
      ['Configuration', _safe(item.configuration)],
      ['Supply', _supplyLabel(item)],
      ['Status', _statusLabel(item.preInstallationStatus)],
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _simpleTopBar(logo: logo, companyName: titleCompany),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Factory / Supplier Specification Sheet',
                      style: _style(15, bold: true),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Generated: ${_fmtDateTime(generatedAt)}',
                      style: _style(8.3, color: _secondaryText),
                    ),
                    if (reportHeaderText.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        _safe(reportHeaderText),
                        style: _style(8.2, color: _secondaryText),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 2,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: _panelAlt,
                    border: pw.Border.all(color: _softLine),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: _kvTable(
                    summaryRows,
                    leftRatio: 1.1,
                    rightRatio: 1.9,
                    compact: true,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          _kvTable(
            [
              ['Project', _safe(survey.reportName)],
              ['Project Ref', _safe(survey.reference)],
              ['Door / Opening Ref', _safe(item.doorRef)],
              [
                'Revision',
                _safe(item.revisionVersion).isEmpty
                    ? 'v1'
                    : _safe(item.revisionVersion),
              ],
            ],
            leftRatio: 1.2,
            rightRatio: 3.0,
            compact: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _pageFooter({
    required pw.Context context,
    required String reportFooterText,
    required DateTime generatedAt,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line, width: 0.8)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Generated ${_fmtDateTime(generatedAt)}',
              style: _style(7.6, color: _secondaryText),
            ),
          ),
          if (reportFooterText.trim().isNotEmpty)
            pw.Expanded(
              child: pw.Text(
                _safe(reportFooterText),
                style: _style(7.6, color: _secondaryText),
                textAlign: pw.TextAlign.center,
              ),
            )
          else
            pw.Spacer(),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: _style(7.6, color: _secondaryText),
          ),
        ],
      ),
    );
  }

  static pw.Widget _simpleTopBar({
    required pw.ImageProvider? logo,
    required String companyName,
  }) {
    return pw.Row(
      children: [
        if (logo != null)
          pw.SizedBox(
            width: 106,
            height: 36,
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          )
        else
          pw.SizedBox(width: 106, height: 36),
        pw.Spacer(),
        pw.Text(companyName, style: _style(12.2, bold: true)),
      ],
    );
  }

  static pw.Widget _projectDetailsTable({
    required Survey survey,
    required PreInstallItem item,
    required DateTime generatedAt,
  }) {
    final address = [
      survey.addressLine1,
      survey.addressLine2,
      survey.cityTown,
      survey.postCode,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');

    return _kvTable(
      [
        ['Project name', _safe(survey.reportName)],
        ['Client', _safe(survey.clientName)],
        ['Address', address.isEmpty ? '-' : address],
        ['Surveyor', _safe(survey.reportCompletedBy)],
        ['Survey date', _fmtDate(survey.reportDate)],
        ['Generated', _fmtDateTime(generatedAt)],
      ],
    );
  }

  static pw.Widget _doorSpecTable(PreInstallItem item) {
    return _kvTable(
      [
        ['Fire rating', _safe(item.fireRating)],
        ['Configuration', _safe(item.configuration)],
        ['Door purpose', _safe(item.doorPurpose)],
        ['Frame configuration', item.hasFrame ? 'Door + frame' : 'Door only'],
        ['Handing', _safe(item.handingMode)],
        ['Glazing', _safe(item.glazingType)],
        ['Panels', _panelSummary(item)],
        [
          'Removal required',
          item.existingDoorRemovalRequired ? 'Yes' : 'No',
        ],
      ],
    );
  }

  static pw.Widget _materialsTable(PreInstallItem item) {
    return _kvTable(
      [
        ['Finish type', _safe(item.finishType)],
        ['Finish', _safe(item.finish)],
        ['Colour / RAL', _safe(item.colourRal)],
        ['Door material', _safe(item.doorMaterial)],
        ['Frame material', _safe(item.frameMaterial)],
        ['Special finish notes', _safe(item.specialFinishNotes)],
      ],
    );
  }

  static pw.Widget _measurementsSection(PreInstallItem item) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _measureTable(item.measurements, item.hasFrame),
        if (_hasText(item.threshold) ||
            _hasText(item.specialNotes) ||
            _hasText(item.accessNotes)) ...[
          pw.SizedBox(height: 6),
          _kvTable(
            [
              ['Threshold', _safe(item.threshold)],
              ['Structural / site notes', _safe(item.accessNotes)],
              ['Additional notes', _safe(item.specialNotes)],
            ],
            leftRatio: 1.6,
            rightRatio: 2.4,
          ),
        ],
      ],
    );
  }

  static pw.Widget _ironmongerySection(
    PreInstallItem item,
    List<DoorFeatureItem> selectedFeatures,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _hardwareFromFeatures(selectedFeatures, item),
        pw.SizedBox(height: 6),
        _featureTable(selectedFeatures),
      ],
    );
  }

  static pw.Widget _notesSection(PreInstallItem item) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Manufacture notes: ${_safe(item.manufactureNotes)}',
          style: _style(8.7),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Survey comments: ${_safe(item.preInstallComments)}',
          style: _style(8.7),
        ),
      ],
    );
  }

  static pw.Widget _inspectorDisclaimerSection(
    Survey survey,
    DateTime generatedAt,
  ) {
    final record = survey.disclaimerAcceptance;
    final signedAt = record?.disclaimerAcceptedAt ?? record?.createdAt;
    final signatureImage = (record?.signatureImageBytes.isNotEmpty ?? false)
        ? pw.MemoryImage(Uint8List.fromList(record!.signatureImageBytes))
        : null;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _kvTable(
          [
            [
              'Inspector name',
              _safe(record?.inspectorName ?? survey.reportCompletedBy)
            ],
            [
              'Signed date/time',
              signedAt == null ? '-' : _fmtDateTime(signedAt)
            ],
            ['Disclaimer version', _safe(record?.disclaimerVersion ?? '-')],
          ],
          leftRatio: 1.6,
          rightRatio: 2.4,
          compact: true,
        ),
        pw.SizedBox(height: 6),
        pw.Text('Inspector signature', style: _style(8.5, bold: true)),
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 3),
          height: 46,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6),
          alignment: pw.Alignment.centerLeft,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _softLine),
            borderRadius: pw.BorderRadius.circular(3),
            color: _panel,
          ),
          child: signatureImage == null
              ? pw.Text('Signature not available',
                  style: _style(8, color: _secondaryText))
              : pw.Image(signatureImage, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(height: 7),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _softLine),
            borderRadius: pw.BorderRadius.circular(3),
            color: _sectionTint,
          ),
          child: pw.Text(
            'Dimensions and specifications recorded in this document are for pricing, specification, and manufacturing reference purposes only. Final manufacturing dimensions and site conditions must be verified before manufacture, ordering, or installation.',
            style: _style(8.2, color: _secondaryText),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Record generated on ${_fmtDateTime(generatedAt)}.',
          style: _style(7.8, color: _secondaryText),
        ),
      ],
    );
  }

  static pw.Widget _doorPreview(PreInstallItem item) {
    final configuration = item.configuration.toLowerCase();
    final isDouble = configuration.contains('double');
    final hasSidePanel = configuration.contains('side');
    final hasOverPanel = configuration.contains('over');

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _panelAlt,
        border: pw.Border.all(color: _softLine),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Door Elevation Preview',
            style: _style(8.5, bold: true),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 6),
          pw.Container(
            height: 186,
            alignment: pw.Alignment.center,
            child: pw.Container(
              width: 278,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                color: _panel,
                border: pw.Border.all(color: _line, width: 1.0),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (hasSidePanel)
                    pw.Container(
                      width: 36,
                      margin: const pw.EdgeInsets.only(right: 4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _line),
                        color: _panelAlt,
                      ),
                      child: pw.Center(
                        child: pw.Text('Side',
                            style: _style(7.2, color: _secondaryText)),
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        if (hasOverPanel)
                          pw.Container(
                            height: 24,
                            margin: const pw.EdgeInsets.only(bottom: 4),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: _line),
                              color: _panelAlt,
                            ),
                            child: pw.Center(
                              child: pw.Text('Over panel',
                                  style: _style(7.2, color: _secondaryText)),
                            ),
                          ),
                        pw.Expanded(
                          child: isDouble
                              ? pw.Row(
                                  children: [
                                    pw.Expanded(child: _doorLeafSketch(item)),
                                    pw.SizedBox(width: 4),
                                    pw.Expanded(child: _doorLeafSketch(item)),
                                  ],
                                )
                              : _doorLeafSketch(item),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Handing / opening: ${_safe(item.handingMode)}',
            style: _style(8, color: _secondaryText),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  static pw.Widget _doorLeafSketch(PreInstallItem item) {
    final glazing = _safe(item.glazingType).toLowerCase();
    final hasGlazing = glazing != '-' && glazing != 'none';
    final hasLowGrille = glazing.contains('low_grille') ||
        glazing == 'low_grille' ||
        glazing == 'glazing_low_grille';
    final hasHighGrille = glazing == 'high_grille';

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        color: _panel,
      ),
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: 1,
            top: 14,
            bottom: 14,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: List.generate(
                3,
                (_) => pw.Container(
                  width: 3,
                  height: 11,
                  decoration: pw.BoxDecoration(
                    color: _panelAlt,
                    border: pw.Border.all(color: _line, width: 0.8),
                  ),
                ),
              ),
            ),
          ),
          if (hasGlazing)
            pw.Positioned(
              left: glazing.contains('narrow_vertical') ||
                      glazing.contains('half_height') ||
                      glazing.contains('full_height')
                  ? 10
                  : 8,
              right: glazing.contains('narrow_vertical') ||
                      glazing.contains('half_height') ||
                      glazing.contains('full_height')
                  ? null
                  : 8,
              top: glazing.contains('top')
                  ? 10
                  : glazing.contains('full_glazed')
                      ? 8
                      : 16,
              bottom: glazing.contains('full_glazed')
                  ? 8
                  : glazing.contains('full_height')
                      ? 10
                      : glazing.contains('half_height')
                          ? 54
                          : 62,
              child: pw.Container(
                width: glazing.contains('narrow_vertical') ||
                        glazing.contains('half_height') ||
                        glazing.contains('full_height')
                    ? 14
                    : null,
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFDCEBFF),
                  border: pw.Border.all(color: _line),
                ),
              ),
            ),
          if (hasLowGrille || hasHighGrille)
            pw.Positioned(
              left: 9,
              right: 9,
              top: hasHighGrille ? 10 : null,
              bottom: hasHighGrille ? null : 10,
              child: pw.Container(
                height: 16,
                decoration: pw.BoxDecoration(
                  color: _panelAlt,
                  border: pw.Border.all(color: _line),
                ),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    4,
                    (_) => pw.Container(height: 0.8, color: _line),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static List<String> _extrasList(
    PreInstallItem item,
    List<DoorFeatureItem> selectedFeatures,
  ) {
    final values = <String>[];

    void addIf(String label, bool condition) {
      if (condition) values.add(label);
    }

    final letterplate = _safe(item.letterplate).toLowerCase();
    final viewer = _safe(item.viewer).toLowerCase();
    final signage = _safe(
      item.signage == 'Custom signage' ? item.customSignage : item.signage,
    );

    addIf('Letter plate', letterplate != '-' && letterplate != 'none');
    addIf('Spyhole', viewer != '-' && viewer != 'none');
    addIf('Grille', item.ventilationGrilleEnabled);
    addIf('Drop seal', _safe(item.seals).toLowerCase().contains('drop'));
    addIf('Signage', signage != '-');
    addIf('Door number plaque',
        _safe(item.doorRef).isNotEmpty && _safe(item.doorRef) != '-');

    for (final feature in selectedFeatures) {
      switch (feature.type.trim().toLowerCase()) {
        case 'grille':
          values.add('Grille');
          break;
        case 'dropsel':
        case 'dropseal':
          values.add('Drop seal');
          break;
        case 'viewer':
          values.add('Spyhole');
          break;
        case 'letterplate':
          values.add('Letter plate');
          break;
      }
    }

    final dedup = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final key = value.toLowerCase();
      if (seen.add(key)) {
        dedup.add(value);
      }
    }
    return dedup;
  }

  static pw.Widget _chips(List<String> values) {
    return pw.Wrap(
      spacing: 6,
      runSpacing: 6,
      children: values
          .map(
            (value) => pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _softLine),
                borderRadius: pw.BorderRadius.circular(12),
                color: _panel,
              ),
              child: pw.Text(value, style: _style(8.2, color: _info)),
            ),
          )
          .toList(),
    );
  }

  static pw.Widget _sectionCard({
    required String title,
    required pw.Widget child,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _panel,
        border: pw.Border.all(color: _softLine),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: pw.BoxDecoration(
              color: _sectionTint,
              border: pw.Border.all(color: _softLine),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(title, style: _style(10, bold: true)),
          ),
          pw.SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  static pw.Widget _kvTable(
    List<List<String>> rows, {
    double leftRatio = 1.25,
    double rightRatio = 2.75,
    bool compact = false,
  }) {
    final cellPadding = compact ? _tableCellPaddingCompact : _tableCellPadding;
    final textSize = compact ? 8.0 : 8.8;

    return pw.Table(
      border: pw.TableBorder.all(color: _softLine, width: 0.6),
      columnWidths: {
        0: pw.FlexColumnWidth(leftRatio),
        1: pw.FlexColumnWidth(rightRatio),
      },
      children: [
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isOdd ? _panelAlt : _panel,
            ),
            children: [
              pw.Padding(
                padding: pw.EdgeInsets.all(cellPadding),
                child: pw.Text(
                  _safe(rows[i][0]),
                  style: _style(textSize, bold: true),
                ),
              ),
              pw.Padding(
                padding: pw.EdgeInsets.all(cellPadding),
                child: pw.Text(_safe(rows[i][1]), style: _style(textSize)),
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _hardwareFromFeatures(
    List<DoorFeatureItem> features,
    PreInstallItem item,
  ) {
    final rows = <List<String>>[];

    if (item.closer.trim().isNotEmpty &&
        item.closer.trim().toLowerCase() != 'none') {
      rows.add(['Door closer', _safe(item.closer), '-']);
    }
    if (item.lockLatchType.trim().isNotEmpty &&
        item.lockLatchType.trim().toLowerCase() != 'none') {
      rows.add(['Lock / latch', _safe(item.lockLatchType), '-']);
    }

    const handleTypes = {
      'leverhandle': 'Lever handle',
      'pullhandle': 'Pull handle',
      'knob': 'Door knob',
    };

    for (final feature in features) {
      final key = feature.type.trim().toLowerCase();
      if (handleTypes.containsKey(key)) {
        rows.add([
          handleTypes[key]!,
          feature.value.trim().isEmpty ? '-' : feature.value.trim(),
          feature.position.trim().isEmpty ? '-' : feature.position.trim(),
        ]);
      }
    }

    if (rows.isEmpty) {
      return pw.Text('No hardware specified',
          style: _style(8.8, color: _secondaryText));
    }

    return _threeColumnTable(
      headers: const ['Item', 'Type / detail', 'Note'],
      rows: rows,
    );
  }

  static pw.Widget _featureTable(List<DoorFeatureItem> rows) {
    if (rows.isEmpty) {
      return pw.Text('No additional feature selected',
          style: _style(8.8, color: _secondaryText));
    }

    final featureRows = rows
        .map(
          (row) => [
            _safe(row.type),
            row.value.trim().isEmpty ? '-' : row.value.trim(),
            row.position.trim().isEmpty ? '-' : row.position.trim(),
          ],
        )
        .toList();

    return _threeColumnTable(
      headers: const ['Feature', 'Value', 'Position'],
      rows: featureRows,
    );
  }

  static pw.Widget _threeColumnTable({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: _softLine, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.5),
        1: pw.FlexColumnWidth(1.8),
        2: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _sectionTint),
          children: headers
              .map(
                (header) => pw.Padding(
                  padding: const pw.EdgeInsets.all(_tableCellPadding),
                  child: pw.Text(header, style: _style(8.4, bold: true)),
                ),
              )
              .toList(),
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isOdd ? _panelAlt : _panel,
            ),
            children: rows[i]
                .map(
                  (value) => pw.Padding(
                    padding: const pw.EdgeInsets.all(_tableCellPadding),
                    child: pw.Text(_safe(value), style: _style(8.3)),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  static pw.Widget _measureTable(DoorMeasurementSet? m, bool hasFrame) {
    if (m == null) {
      return pw.Text('No measurements captured',
          style: _style(8.8, color: _secondaryText));
    }

    final headers = hasFrame
        ? const ['Measurement', 'Primary', 'Secondary', 'Notes']
        : const ['Measurement', 'W', 'H', 'T'];

    final rows = <List<String>>[];

    if (hasFrame) {
      rows
        ..add([
          'Overall frame size (mm)',
          _num(m.frameWidth),
          _num(m.frameHeight),
          _num(m.frameDepth),
        ])
        ..add([
          'Structural opening (mm)',
          _num(m.openingWidthMiddle),
          _num(m.openingHeightCentre),
          'W x H',
        ])
        ..add([
          'Door leaf (optional) (mm)',
          _num(m.leafWidth),
          _num(m.leafHeight),
          _num(m.leafThickness),
        ]);
    } else {
      rows.add([
        'Door leaf (mm)',
        _num(m.leafWidth),
        _num(m.leafHeight),
        _num(m.leafThickness),
      ]);
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _softLine, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _sectionTint),
          children: headers
              .map(
                (header) => pw.Padding(
                  padding: const pw.EdgeInsets.all(_tableCellPadding),
                  child: pw.Text(header, style: _style(8.4, bold: true)),
                ),
              )
              .toList(),
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isOdd ? _panelAlt : _panel,
            ),
            children: rows[i]
                .map(
                  (value) => pw.Padding(
                    padding: const pw.EdgeInsets.all(_tableCellPadding),
                    child: pw.Text(value, style: _style(8.3)),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  static pw.Widget _photoGrid(List<PreInstallPhoto> photos) {
    final imagePhotos =
        photos.where((photo) => photo.bytes.isNotEmpty).toList();
    if (imagePhotos.isEmpty) {
      return pw.Text('No survey photos available',
          style: _style(8.8, color: _secondaryText));
    }

    if (imagePhotos.length == 1) {
      final photo = imagePhotos.first;
      return pw.Center(
        child: _photoTile(photo, width: _contentWidth * 0.72, height: 188),
      );
    }

    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: imagePhotos
          .map(
              (photo) => _photoTile(photo, width: _photoTileWidth, height: 142))
          .toList(),
    );
  }

  static pw.Widget _photoTile(
    PreInstallPhoto photo, {
    required double width,
    required double height,
  }) {
    final img = pw.MemoryImage(Uint8List.fromList(photo.bytes));
    final name =
        photo.fileName.trim().isEmpty ? 'Photo' : photo.fileName.trim();

    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _softLine),
        borderRadius: pw.BorderRadius.circular(3),
        color: _panel,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            height: height,
            alignment: pw.Alignment.center,
            color: _panelAlt,
            child: pw.Image(img, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(height: 3),
          pw.Text(name, style: _style(7.6, color: _secondaryText), maxLines: 1),
        ],
      ),
    );
  }

  static String _statusLabel(PreInstallationWorkflowStatus status) {
    switch (status) {
      case PreInstallationWorkflowStatus.draft:
        return 'Draft';
      case PreInstallationWorkflowStatus.survey_completed:
        return 'Survey completed';
      case PreInstallationWorkflowStatus.approved_for_order:
        return 'Approved for order';
      case PreInstallationWorkflowStatus.ready_for_factory_order:
        return 'Ready for factory order';
      case PreInstallationWorkflowStatus.ordered:
        return 'Ordered';
      case PreInstallationWorkflowStatus.delivered_ready:
        return 'Delivered / ready';
      case PreInstallationWorkflowStatus.available_on_site:
        return 'Available on site';
      case PreInstallationWorkflowStatus.released_to_installation:
        return 'Released to installation';
    }
  }

  static String _supplyLabel(PreInstallItem item) {
    switch (item.supplyResponsibility) {
      case PreInstallSupplyResponsibility.bw_supply_install:
        return 'BW Supply + Install';
      case PreInstallSupplyResponsibility.client_supplied:
        return 'Client supplied';
      case PreInstallSupplyResponsibility.main_contractor_supplied:
        return 'Main contractor supplied';
      case PreInstallSupplyResponsibility.custom:
        return _safe(item.customSupplyResponsibility);
    }
  }

  static String _panelSummary(PreInstallItem item) {
    final cfg = item.configuration.toLowerCase();
    final side = cfg.contains('side') ? 'Side panel' : 'No side panel';
    final over = cfg.contains('over') ? 'Over panel' : 'No over panel';
    return '$side; $over';
  }

  static String _num(double? value) {
    if (value == null) return '-';
    return value.toStringAsFixed(1);
  }

  static String _safe(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? '-' : text;
  }

  static bool _hasText(String? value) {
    return (value ?? '').trim().isNotEmpty;
  }

  static String _safeFile(String value) {
    final v = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return v.isEmpty ? 'item' : v;
  }

  static String _fmtDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year}';
  }

  static String _fmtTime(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String _fmtDateTime(DateTime date) {
    return '${_fmtDate(date)} - ${_fmtTime(date)}';
  }

  static pw.TextStyle _style(double size,
      {bool bold = false, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      color: color ?? _text,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
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
