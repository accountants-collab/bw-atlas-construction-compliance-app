import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../app/ui/branding_resolver.dart';
import '../domain/inspection_definitions.dart';
import '../domain/models.dart';

class SurveyPdfBuilder {
  static const _logoAssetPath = kDefaultSystemLogoAssetPath;
  static const _defaultSupportEmail = 'support@example.com';
  static const _defaultSupportPhone = '+44 (0)20 0000 0000';
  static const _replacementRequiredPdfMessage =
      'Full door set replacement required - immediate action recommended';
  static const _replacementDimensionDisclaimerPdfMessage =
      'Dimensions recorded for pricing/survey reference only. Final manufacturing/order dimensions must be verified on site by the installer/supplier before ordering or manufacture.';

  static const double _pageMargin = 20;
  static const double _sectionGap = 8;
  static const double _sectionPadding = 8;
  static final double _contentWidth =
      PdfPageFormat.a4.width - (_pageMargin * 2);
  static const double _gridGap = 8;
  static final double _photoTileWidth = (_contentWidth - _gridGap) / 2;
  static const double _photoTileHeight = 118;
  static final double _singlePhotoMaxWidth = _contentWidth * 0.65;
  static const double _singlePhotoHeight = 170;
  static const double _cardRadius = 6;
  static const double _cardInnerGap = 4;
  static const double _sectionTitleGap = 3;

  static final PdfColor _text = PdfColor.fromInt(0xFF1F2937);
  static final PdfColor _secondaryText = PdfColor.fromInt(0xFF667085);
  static final PdfColor _line = PdfColor.fromInt(0xFFD8E0E8);
  static final PdfColor _softLine = PdfColor.fromInt(0xFFE8EDF3);
  static final PdfColor _panel = PdfColor.fromInt(0xFFFFFFFF);
  static final PdfColor _panelAlt = PdfColor.fromInt(0xFFF8FAFC);
  static final PdfColor _sectionTint = PdfColor.fromInt(0xFFF7F9FC);
  static final PdfColor _pass = PdfColor.fromInt(0xFF15803D);
  static final PdfColor _passBg = PdfColor.fromInt(0xFFF3FAF5);
  static final PdfColor _fail = PdfColor.fromInt(0xFFB91C1C);
  static final PdfColor _failBg = PdfColor.fromInt(0xFFFFF4F4);
  static final PdfColor _info = PdfColor.fromInt(0xFF305F9C);

  static Future<Uint8List> buildWholeObjectPdf(
    Survey survey, {
    List<int> companyLogoBytes = const [],
    String companyName = kDefaultSystemCompanyName,
    String companyAddress = '',
    String companyEmail = '',
    String companyPhone = '',
    String reportHeaderText = '',
    String reportFooterText = '',
    String generatedBy = '',
  }) async {
    final theme = await _loadPdfTheme();
    final doc = pw.Document(theme: theme);
    final logo = await _loadLogo(companyLogoBytes);
    for (final door in survey.doors) {
      await _addDoorReport(
        doc: doc,
        survey: survey,
        door: door,
        logo: logo,
        companyName: companyName,
        companyAddress: companyAddress,
        companyEmail: companyEmail,
        companyPhone: companyPhone,
        reportHeaderText: reportHeaderText,
        reportFooterText: reportFooterText,
        generatedBy: generatedBy,
      );
    }
    return doc.save();
  }

  static Future<Uint8List> buildSingleDoorPdf(
    Survey survey,
    Door door, {
    List<int> companyLogoBytes = const [],
    String companyName = kDefaultSystemCompanyName,
    String companyAddress = '',
    String companyEmail = '',
    String companyPhone = '',
    String reportHeaderText = '',
    String reportFooterText = '',
    String generatedBy = '',
  }) async {
    final theme = await _loadPdfTheme();
    final doc = pw.Document(theme: theme);
    final logo = await _loadLogo(companyLogoBytes);
    await _addDoorReport(
      doc: doc,
      survey: survey,
      door: door,
      logo: logo,
      companyName: companyName,
      companyAddress: companyAddress,
      companyEmail: companyEmail,
      companyPhone: companyPhone,
      reportHeaderText: reportHeaderText,
      reportFooterText: reportFooterText,
      generatedBy: generatedBy,
    );
    return doc.save();
  }

  static Future<void> _addDoorReport({
    required pw.Document doc,
    required Survey survey,
    required Door door,
    required pw.ImageProvider? logo,
    required String companyName,
    required String companyAddress,
    required String companyEmail,
    required String companyPhone,
    required String reportHeaderText,
    required String reportFooterText,
    required String generatedBy,
  }) async {
    final startPageCount = doc.document.pdfPageList.pages.length;
    final approval = _latestApproval(door);
    final resolvedCompanyName = _resolveCompanyName(companyName);
    final resolvedCompanyAddress = _cleanText(companyAddress);
    final resolvedCompanyEmail = _resolveCompanyEmail(companyEmail);
    final resolvedCompanyPhone = _resolveCompanyPhone(companyPhone);
    final reportReference = _reportReference(survey);
    final registerReference = _registerReference(survey, approval, door);
    final reportTitle = _reportTitleForType(survey.type);
    final isFireStopping = survey.type == SurveyType.fireStopping;
    final issuedDate = survey.reportDate;
    final generatedAt = DateTime.now();
    final startGlobalPageNumber = startPageCount + 1;
    var doorPagesCount = 1;

    _touchExistingHelpers(
      survey: survey,
      door: door,
      approval: approval,
      reportReference: reportReference,
      registerReference: registerReference,
      companyName: resolvedCompanyName,
    );

    final content = <pw.Widget>[
      _clientHeaderSummarySection(
        survey: survey,
        door: door,
        reportReference: reportReference,
        registerReference: registerReference,
      ),
      pw.SizedBox(height: _sectionGap),
      _assetInformationSection(survey: survey, door: door),
    ];

    final drawingReference =
        await _fireStoppingDrawingReferenceWidget(survey: survey, door: door);

    if (isFireStopping) {
      content
        ..add(pw.SizedBox(height: _sectionGap))
        ..add(_fireStoppingItemContentSection(
            door: door, drawingReference: drawingReference));
    } else {
      if (drawingReference != null) {
        content
          ..add(pw.SizedBox(height: _sectionGap))
          ..add(drawingReference);
      }
      content
        ..add(pw.SizedBox(height: _sectionGap))
        ..add(_inspectionResultsSection(door));

      if (door.replacementRequired) {
        content
          ..add(pw.SizedBox(height: _sectionGap))
          ..add(_fullDoorsetReplacementSection(door));
      }

      final defectTable = _defectsTableWidget(door);
      if (defectTable != null) {
        content
          ..add(pw.SizedBox(height: _sectionGap))
          ..add(defectTable);
      }

      final recSummary = _recommendedActionsSummaryWidget(door);
      if (recSummary != null) {
        content
          ..add(pw.SizedBox(height: _sectionGap))
          ..add(recSummary);
      }
    }

    if (!isFireStopping) {
      final videoEvidence = _videoEvidenceWidget(survey: survey, door: door);
      if (videoEvidence != null) {
        content
          ..add(pw.SizedBox(height: _sectionGap))
          ..add(videoEvidence);
      }
    }

    final photoWidgets = _photoEvidenceWidgets(survey: survey, door: door);
    if (photoWidgets.isNotEmpty) {
      content
        ..add(pw.NewPage())
        ..addAll(photoWidgets);
    }

    content
      ..add(pw.SizedBox(height: _sectionGap))
      ..add(_inspectorDetailsSection(
        survey: survey,
        door: door,
        approval: approval,
        companyName: resolvedCompanyName,
      ))
      ..add(pw.SizedBox(height: 6))
      ..add(_inspectionDisclaimerCard(
          survey: survey, isFireStopping: isFireStopping))
      ..add(pw.SizedBox(height: 6))
      ..add(_declarationAndSignatureCard(
          survey: survey, approval: approval, door: door));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_pageMargin),
        header: (context) => _pageHeader(
          logo: logo,
          survey: survey,
          companyName: resolvedCompanyName,
          companyAddress: resolvedCompanyAddress,
          companyEmail: resolvedCompanyEmail,
          companyPhone: resolvedCompanyPhone,
          reportTitle: reportTitle,
          reportHeaderText: reportHeaderText,
        ),
        footer: (context) => _pageFooter(
          context: context,
          companyName: resolvedCompanyName,
          registerReference: registerReference,
          qrData: '${survey.id}:${door.id}',
          generatedBy: _cleanText(generatedBy).isEmpty
              ? _inspectorName(survey, approval, door)
              : generatedBy,
          generatedAt: generatedAt,
          issuedDate: issuedDate,
          reportFooterText: reportFooterText,
          localPageNumber: context.pageNumber - startGlobalPageNumber + 1,
          localPagesCount: doorPagesCount,
        ),
        build: (_) => content,
      ),
    );
    doorPagesCount = doc.document.pdfPageList.pages.length - startPageCount;
  }

  static pw.Widget _pageHeader({
    required pw.ImageProvider? logo,
    required Survey survey,
    required String companyName,
    required String companyAddress,
    required String companyEmail,
    required String companyPhone,
    required String reportTitle,
    required String reportHeaderText,
  }) {
    final headerText = _cleanText(reportHeaderText);
    final companyLines = <String>[
      _cleanText(companyName),
      if (_cleanText(companyAddress).isNotEmpty) _cleanText(companyAddress),
      _cleanText(companyEmail),
      _cleanText(companyPhone),
    ].where((line) => line.isNotEmpty).toList();
    final headerLogo = logo == null
        ? pw.Container(
            height: 52,
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: pw.BoxDecoration(
              color: _panelAlt,
              border: pw.Border.all(color: _softLine),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              _cleanText(companyName),
              style: _style(9.2, bold: true, color: _text),
              textAlign: pw.TextAlign.center,
            ),
          )
        : pw.Image(logo, fit: pw.BoxFit.contain, height: 52);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              constraints: pw.BoxConstraints(
                  maxWidth: _contentWidth * 0.25, maxHeight: 44),
              alignment: pw.Alignment.centerLeft,
              child: headerLogo,
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    reportTitle,
                    textAlign: pw.TextAlign.center,
                    style: _style(12.4, bold: true, color: _text),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    _safeSurveyName(survey),
                    textAlign: pw.TextAlign.center,
                    style: _style(8, color: _secondaryText),
                  ),
                  if (headerText.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      headerText,
                      textAlign: pw.TextAlign.center,
                      style: _style(7.3, color: _secondaryText),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Container(
              width: _contentWidth * 0.30,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                color: _panelAlt,
                border: pw.Border.all(color: _softLine),
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Company',
                      style: _style(7.0, bold: true, color: _secondaryText)),
                  pw.SizedBox(height: 2),
                  for (final line in companyLines)
                    pw.Text(
                      line,
                      textAlign: pw.TextAlign.right,
                      style: _style(6.8, color: _secondaryText),
                    ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 1.2, color: _line),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.Widget _clientHeaderSummarySection({
    required Survey survey,
    required Door door,
    required String reportReference,
    required String registerReference,
  }) {
    final isFireStopping = survey.type == SurveyType.fireStopping;
    final pinLabel = _fireStoppingPinLabel(survey: survey, door: door);
    final failEntries = _failedEntries(door);
    final actionsRequired = failEntries.where((entry) {
      final check = _findCheck(entry.key);
      final action = entry.value.recommendedAction.trim().isNotEmpty
          ? entry.value.recommendedAction.trim()
          : (check?.recommendedAction ?? '');
      return _cleanText(action).isNotEmpty;
    }).length;
    final overall = _overallResultLabel(door);
    final style = _resultStyle(overall);
    final showReplacementNotice = door.replacementRequired && !isFireStopping;

    return _sectionCard(
      title: 'Report Summary',
      trailing: _statusBadge(overall, style.color, style.background),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Table(
                  border: pw.TableBorder.all(color: _softLine, width: 0.6),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.1),
                    1: pw.FlexColumnWidth(1.4)
                  },
                  children: [
                    _compactRow('Inspection Date', _date(door.inspectionDate)),
                    _compactRow(
                        isFireStopping ? 'Pin Number' : 'Door ID / Reference',
                        _safeDoorRef(door)),
                    _compactRow(
                        'Project / Development', _safeSurveyName(survey)),
                    _compactRow(
                        isFireStopping ? 'Exact Location' : 'Door location',
                        _safe(door.area)),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Table(
                  border: pw.TableBorder.all(color: _softLine, width: 0.6),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.1),
                    1: pw.FlexColumnWidth(1.4)
                  },
                  children: [
                    _compactRow(
                        isFireStopping ? 'Room / Area' : 'Floor / Level',
                        _safe(door.floor)),
                    _compactRow(
                        isFireStopping ? 'Item Findings' : 'Non-Conformities',
                        failEntries.length.toString()),
                    _compactRow(
                        isFireStopping
                            ? 'Recommended Actions'
                            : 'Remedial Actions',
                        actionsRequired.toString()),
                    // DEDUPLICATION RULE: Only show Door Pin if it differs from Door ID / Reference
                    if (_shouldShowDoorPin(isFireStopping, pinLabel, door))
                      _compactRow(
                        isFireStopping
                            ? 'PIN Number'
                            : (survey.type == SurveyType.snagging
                                ? 'Snag Pin'
                                : 'Door Pin'),
                        _safe(pinLabel),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (showReplacementNotice) ...[
            pw.SizedBox(height: 6),
            _replacementRequiredBanner(),
          ],
        ],
      ),
    );
  }

  static pw.Widget _assetInformationSection(
      {required Survey survey, required Door door}) {
    final isFireStopping = survey.type == SurveyType.fireStopping;
    if (isFireStopping) {
      final firstDefect = _primaryFireStoppingDefect(door);
      final pinLabel = _fireStoppingPinLabel(survey: survey, door: door);
      final statusLabel = _fireStoppingStatusLabel(door);
      final notes = _fireStoppingNotes(door);
      final acousticRating =
          _fireStoppingAcousticRating(door: door, defect: firstDefect);
      return _sectionCard(
        title: 'Fire Stopping Report Information',
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Table(
              border: pw.TableBorder.all(color: _softLine, width: 0.6),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.9),
                1: pw.FlexColumnWidth(1.5),
                2: pw.FlexColumnWidth(0.9),
                3: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(children: [
                  _tCellHdr('Pin N'),
                  _tCell(_safe(pinLabel)),
                  _tCellHdr('Status'),
                  _tCell(statusLabel),
                ]),
                pw.TableRow(children: [
                  _tCellHdr('Operative'),
                  _tCell(_safe(survey.reportCompletedBy)),
                  _tCellHdr('Inspection Date / Time'),
                  _tCell(_dateTime(door.inspectionDate)),
                ]),
                pw.TableRow(children: [
                  _tCellHdr('Site Address'),
                  _tCell(_projectAddress(survey)),
                  _tCellHdr('Acoustic Rating'),
                  _tCell(acousticRating),
                ]),
                pw.TableRow(children: [
                  _tCellHdr('Room / Area'),
                  _tCell(_safe(door.floor)),
                  _tCellHdr('Exact Location'),
                  _tCell(_safe(door.area)),
                ]),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text('Notes', style: _style(8.2, bold: true, color: _text)),
            pw.SizedBox(height: 3),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: _panelAlt,
                border: pw.Border.all(color: _softLine),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(notes, style: _style(7.9, color: _text)),
            ),
          ],
        ),
      );
    }

    return _sectionCard(
      title: 'Fire Door Asset Information',
      child: pw.Table(
        border: pw.TableBorder.all(color: _softLine, width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(0.85),
          1: pw.FlexColumnWidth(1.15),
          2: pw.FlexColumnWidth(0.85),
          3: pw.FlexColumnWidth(1.15),
        },
        children: [
          pw.TableRow(children: [
            _tCellHdr('Door configuration'),
            _tCell(_doorConfigurationLabel(door.configuration)),
            _tCellHdr('Door type'),
            _tCell(_doorTypeLabel(door.doorType)),
          ]),
          pw.TableRow(children: [
            _tCellHdr('Material'),
            _tCell(_doorMaterialLabel(door)),
            _tCellHdr('Certification Status'),
            _tCell(_doorCertificationStatusLabel(door.classification)),
          ]),
          pw.TableRow(children: [
            _tCellHdr('Certification Body'),
            _tCell(_doorCertificationBodyLabel(door)),
            _tCellHdr('Fire Rating'),
            _tCell(_fireRatingLabel(door.fireRating)),
          ]),
          pw.TableRow(children: [
            _tCellHdr('Evidence Level'),
            _tCell(_gradingLevelLabel(door.gradingLevel)),
            _tCellHdr('Maintenance interval'),
            _tCell('${door.maintenanceIntervalMonths} months'),
          ]),
          pw.TableRow(children: [
            _tCellHdr('Door function'),
            _tCell(_doorFunctionLabel(door.doorFunction)),
            _tCellHdr('Property / Site Address'),
            _tCell(_projectAddress(survey)),
          ]),
        ],
      ),
    );
  }

  static pw.Widget _fireStoppingItemContentSection({
    required Door door,
    pw.Widget? drawingReference,
  }) {
    final defects = door.fireStoppingDefects.isNotEmpty
        ? door.fireStoppingDefects
        : [
            FireStoppingDefect(
              id: 'legacy',
              description: door.fireStoppingDefectDescription,
              recommendedAction: door.fireStoppingRecommendedAction,
            ),
          ]
            .where((d) =>
                d.description.trim().isNotEmpty ||
                d.recommendedAction.trim().isNotEmpty)
            .toList();
    final statusLabel = _fireStoppingStatusLabel(door);

    return _sectionCard(
      title: 'Item ${door.number}',
      trailing: _statusBadge(
        statusLabel,
        statusLabel == 'Completed'
            ? _pass
            : (statusLabel == 'Action Required' ? _fail : _secondaryText),
        statusLabel == 'Completed'
            ? _passBg
            : (statusLabel == 'Action Required' ? _failBg : _panelAlt),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (defects.isNotEmpty) ...[
            pw.Text('Defects', style: _style(8.2, bold: true, color: _text)),
            pw.SizedBox(height: 3),
            pw.Table(
              border: pw.TableBorder.all(color: _softLine, width: 0.6),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.45),
                1: pw.FlexColumnWidth(2.2),
                2: pw.FlexColumnWidth(1.8),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: _sectionTint),
                  children: [
                    _tCellHdr('No'),
                    _tCellHdr('Defect'),
                    _tCellHdr('Recommended Action'),
                  ],
                ),
                for (var i = 0; i < defects.length; i++)
                  pw.TableRow(children: [
                    _tCell((i + 1).toString()),
                    _tCell(_safe(
                        _composeFireStoppingDefectDescription(defects[i]))),
                    _tCell(_safe(defects[i].recommendedAction)),
                  ]),
              ],
            ),
          ],
          if (drawingReference != null) ...[
            pw.SizedBox(height: 6),
            drawingReference,
          ],
        ],
      ),
    );
  }

  static pw.Widget _inspectorDetailsSection({
    required Survey survey,
    required Door door,
    required Approval? approval,
    required String companyName,
  }) {
    return _sectionCard(
      title: 'Inspector Details',
      child: pw.Table(
        border: pw.TableBorder.all(color: _softLine, width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(0.8),
          1: pw.FlexColumnWidth(1.3),
          2: pw.FlexColumnWidth(0.8),
          3: pw.FlexColumnWidth(1.3),
        },
        children: [
          pw.TableRow(children: [
            _tCellHdr('Inspector Name'),
            _tCell(_inspectorName(survey, approval, door)),
            _tCellHdr('Inspection Date'),
            _tCell(_date(door.inspectionDate)),
          ]),
          pw.TableRow(children: [
            _tCellHdr('Inspection Time'),
            _tCell(_fmtTime(door.inspectionDate)),
            _tCellHdr('Company'),
            _tCell(_cleanText(companyName)),
          ]),
        ],
      ),
    );
  }

  static pw.Widget _inspectionDisclaimerCard(
      {required Survey survey, required bool isFireStopping}) {
    final disclaimer = survey.disclaimerAcceptance;
    final signatureImage =
        disclaimer != null && disclaimer.signatureImageBytes.isNotEmpty
            ? pw.MemoryImage(Uint8List.fromList(disclaimer.signatureImageBytes))
            : null;
    return _sectionCard(
      title: isFireStopping
          ? 'Fire Stopping Disclaimer Acknowledgement'
          : 'Disclaimer Acknowledgement',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            disclaimer == null
                ? 'No saved disclaimer acceptance record was linked to this report when this PDF was generated.'
                : 'The full inspection disclaimer was reviewed and accepted on a separate saved disclaimer form linked to this report.',
            style: _style(7.8, color: _text),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'For full legal wording and audit history, see the saved disclaimer records in system compliance files.',
            style: _style(7.6, color: _text),
          ),
          if (disclaimer != null) ...[
            pw.SizedBox(height: 6),
            pw.Text('Inspector: ${_cleanText(disclaimer.inspectorName)}',
                style: _style(7.8, color: _text)),
            pw.Text(
                'Accepted on: ${_nullableDate(disclaimer.disclaimerAcceptedAt)}',
                style: _style(7.8, color: _text)),
            pw.Text('Version: ${_cleanText(disclaimer.disclaimerVersion)}',
                style: _style(7.8, color: _text)),
            pw.SizedBox(height: 6),
            pw.Text('Signature', style: _style(7.8, color: _text, bold: true)),
            pw.SizedBox(height: 3),
            if (signatureImage != null)
              pw.Container(
                height: 42,
                width: 120,
                alignment: pw.Alignment.centerLeft,
                child: pw.Image(signatureImage,
                    height: 42, fit: pw.BoxFit.contain),
              )
            else
              pw.Text('Captured on saved disclaimer form.',
                  style: _style(7.8, color: _text)),
          ],
        ],
      ),
    );
  }

  static List<MapEntry<String, InspectionCheckResult>> _failedEntries(
      Door door) {
    final ordered = <MapEntry<String, InspectionCheckResult>>[];
    final seen = <String>{};

    for (final check in inspectionChecks) {
      final result = door.inspectionResults[check.id.name];
      if (result == null) {
        continue;
      }
      final outcome = result.outcome;
      if (outcome == InspectionOutcome.fail ||
          outcome == InspectionOutcome.criticalFail ||
          outcome == InspectionOutcome.advisory) {
        ordered.add(MapEntry(check.id.name, result));
        seen.add(check.id.name);
      }
    }

    for (final entry in door.inspectionResults.entries) {
      if (seen.contains(entry.key)) {
        continue;
      }
      final outcome = entry.value.outcome;
      if (outcome == InspectionOutcome.fail ||
          outcome == InspectionOutcome.criticalFail ||
          outcome == InspectionOutcome.advisory) {
        ordered.add(entry);
      }
    }

    return ordered;
  }

  static void _touchExistingHelpers({
    required Survey survey,
    required Door door,
    required Approval? approval,
    required String reportReference,
    required String registerReference,
    required String companyName,
  }) {
    if (DateTime.now().millisecondsSinceEpoch == -1) {
      _siteDetailsCard(
        survey: survey,
        door: door,
        reportReference: reportReference,
        registerReference: registerReference,
      );
      _inspectorDetailsCard(
        survey: survey,
        door: door,
        approval: approval,
        companyName: companyName,
      );
      _reportSummaryCard(survey);
      _doorMaintenanceTableSection(door: door, approval: approval);
      _doorSummaryCard(survey: survey, door: door);
      _recommendedActionsWidgets(door);
    }
  }

  static pw.Widget _pageFooter({
    required pw.Context context,
    required String companyName,
    required String registerReference,
    required String qrData,
    required String generatedBy,
    required DateTime generatedAt,
    required DateTime issuedDate,
    required String reportFooterText,
    required int localPageNumber,
    required int localPagesCount,
  }) {
    final customFooter = _cleanText(reportFooterText);
    final by =
        _cleanText(generatedBy).isEmpty ? 'System' : _cleanText(generatedBy);
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(height: 1, color: _softLine),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_cleanText(companyName),
                      style: _style(7.0, color: _secondaryText)),
                  if (_cleanText(registerReference).isNotEmpty)
                    pw.Text('Register Ref: ${_cleanText(registerReference)}',
                        style: _style(6.5, color: _secondaryText)),
                  pw.Text('Generated on: ${_dateTime(generatedAt)}',
                      style: _style(6.5, color: _secondaryText)),
                  pw.Text('Generated by: $by',
                      style: _style(6.5, color: _secondaryText)),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'Version: v1.0  |  Issued Date: ${_date(issuedDate)}',
                    textAlign: pw.TextAlign.center,
                    style: _style(6.6, color: _secondaryText),
                  ),
                  if (customFooter.isNotEmpty) ...[
                    pw.SizedBox(height: 1),
                    pw.Text(
                      customFooter,
                      textAlign: pw.TextAlign.center,
                      style: _style(6.5, color: _secondaryText),
                    ),
                  ],
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.SizedBox(
                    width: 32,
                    height: 32,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: _cleanText(qrData),
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Page $localPageNumber of $localPagesCount',
                    textAlign: pw.TextAlign.right,
                    style: _style(7.2, color: _secondaryText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _siteDetailsCard({
    required Survey survey,
    required Door door,
    required String reportReference,
    required String registerReference,
  }) {
    final rows = <List<String>>[
      ['Project / Site', _safeSurveyName(survey)],
      ['Site Address', _projectAddress(survey)],
      ['Date', _date(door.inspectionDate)],
      [
        'Project Number',
        reportReference.isEmpty ? 'Not provided' : reportReference
      ],
    ];
    return _sectionCard(
      title: 'PROJECT DETAILS',
      child: _detailRows(rows),
    );
  }

  static pw.Widget _inspectorDetailsCard({
    required Survey survey,
    required Door door,
    required Approval? approval,
    required String companyName,
  }) {
    return _sectionCard(
      title: 'INSPECTOR DETAILS',
      child: _detailRows([
        ['Inspector Name', _inspectorName(survey, approval, door)],
        ['Role', 'Inspector'],
        ['Company', companyName],
      ]),
    );
  }

  static pw.Widget _reportSummaryCard(Survey survey) {
    var passed = 0;
    var failed = 0;
    for (final door in survey.doors) {
      if (_isPass(door)) {
        passed += 1;
      } else {
        failed += 1;
      }
    }
    return _sectionCard(
      title: 'REPORT SUMMARY',
      child: _detailGrid([
        ['Total Doors', survey.doors.length.toString()],
        ['Passed', passed.toString()],
        ['Failed', failed.toString()],
      ], columns: 2),
    );
  }

  static pw.Widget _doorMaintenanceTableSection(
      {required Door door, required Approval? approval}) {
    final answeredEntries = door.inspectionResults.entries.where((entry) {
      final outcome = entry.value.outcome;
      return outcome != InspectionOutcome.notAnswered &&
          outcome != InspectionOutcome.notApplicable;
    }).toList();

    final failEntries = answeredEntries.where((entry) {
      final outcome = entry.value.outcome;
      return outcome == InspectionOutcome.fail ||
          outcome == InspectionOutcome.criticalFail ||
          outcome == InspectionOutcome.advisory;
    }).toList();
    final passCount = answeredEntries
        .where((entry) => entry.value.outcome == InspectionOutcome.pass)
        .length;

    if (door.replacementRequired) {
      return _sectionCard(
        title: 'INSPECTION FINDINGS',
        child: pw.Text(
          'Result: FAIL - $_replacementRequiredPdfMessage',
          style: _style(9, bold: true, color: _fail),
        ),
      );
    }

    if (answeredEntries.isEmpty) {
      return _sectionCard(
        title: 'INSPECTION FINDINGS',
        child: pw.Text('Inspection incomplete',
            style: _style(9, bold: true, color: _secondaryText)),
      );
    }

    if (failEntries.isEmpty) {
      return _sectionCard(
        title: 'INSPECTION FINDINGS',
        child: pw.Text(
          'Result: PASS - No issues identified ($passCount checks passed).',
          style: _style(9, bold: true, color: _pass),
        ),
      );
    }

    return _sectionCard(
      title: 'INSPECTION FINDINGS',
      child: pw.Table(
        border: pw.TableBorder.all(color: _softLine, width: 0.8),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.2),
          1: pw.FlexColumnWidth(1.3),
          2: pw.FlexColumnWidth(0.9),
          3: pw.FlexColumnWidth(2.1),
          4: pw.FlexColumnWidth(0.9),
          5: pw.FlexColumnWidth(0.9),
          6: pw.FlexColumnWidth(1.2),
          7: pw.FlexColumnWidth(1.1),
          8: pw.FlexColumnWidth(1.2),
          9: pw.FlexColumnWidth(1.8),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _sectionTint),
            children: [
              _tableHeaderCell('Door Ref'),
              _tableHeaderCell('Location'),
              _tableHeaderCell('Fire Rating'),
              _tableHeaderCell('Finding / Description'),
              _tableHeaderCell('ARTs Required'),
              _tableHeaderCell('ARTs Completed'),
              _tableHeaderCell('Maintenance Completed Date'),
              _tableHeaderCell('Maintained By'),
              _tableHeaderCell('Next Maintenance Due'),
              _tableHeaderCell('Comments'),
            ],
          ),
          ...failEntries.map((entry) {
            final check = _findCheck(entry.key);
            final result = entry.value;
            final artCode = check?.artCodeOnFail;
            final remedial = _findRemedialForIssue(
                door: door, issueId: entry.key, checkTitle: check?.title ?? '');
            final prefix = '[FAIL] ';
            final description =
                _cleanText('$prefix${check?.title ?? entry.key}');
            final overrideComment = _cleanText(result.comment.trim());
            final fallbackRecommendation = _cleanText(
              result.recommendedAction.trim().isNotEmpty
                  ? result.recommendedAction.trim()
                  : (check?.recommendedAction ?? ''),
            );

            return pw.TableRow(
              children: [
                _tableCell(_safeDoorRef(door)),
                _tableCell(_doorLocation(door)),
                _tableCell(_fireRatingLabel(door.fireRating)),
                _tableCell(description),
                _tableCell(artCode == null
                    ? 'Not required'
                    : 'ART${artCode.toString().padLeft(2, '0')}'),
                _tableCell(remedial != null &&
                        remedial.status == RemedialStatus.approved
                    ? 'Yes'
                    : 'No'),
                _tableCell(_nullableDate(
                    remedial?.approvedAt ?? remedial?.completedDate)),
                _tableCell(_cleanText(remedial?.approvedBy ??
                    remedial?.completedBy ??
                    door.approvedMaintainerName)),
                _tableCell(_nullableDate(approval?.nextMaintenanceDueDate)),
                _tableCell(overrideComment.isNotEmpty
                    ? overrideComment
                    : fallbackRecommendation),
              ],
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _declarationAndSignatureCard({
    required Survey survey,
    required Approval? approval,
    required Door door,
  }) {
    final signatureDate = approval?.approvedDate ?? door.approvedAt;
    final inspectorName = _inspectorName(survey, approval, door);
    return _sectionCard(
      title: 'Declaration & Signature',
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              'I confirm this report reflects the visible condition of the inspected door at the time of inspection and that recorded findings are accurate to the best of my professional knowledge.',
              style: _style(7.6, color: _text),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text('Inspector',
                    style: _style(7.4, bold: true, color: _secondaryText)),
                pw.SizedBox(height: 3),
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: _panelAlt,
                    border: pw.Border.all(color: _line),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(inspectorName,
                      style: _style(7.6, bold: true, color: _text)),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Date & Time: ${_nullableDateTime(signatureDate)}',
                    style: _style(7.2, color: _secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _doorSummaryCard(
      {required Survey survey, required Door door}) {
    final resultText = _doorResultLabel(door);
    final resultColor = resultText == 'PASS' ? _pass : _fail;
    final resultBg = resultText == 'PASS' ? _passBg : _failBg;
    final rows = <List<String>>[
      ['Door ID', _safeDoorRef(door)],
      ['Location', _doorLocation(door)],
      ['Level', _safe(door.floor)],
      ['Material', _doorMaterialLabel(door)],
      ['Fire rating', _fireRatingLabel(door.fireRating)],
      [
        'Certification status',
        _doorCertificationStatusLabel(door.classification)
      ],
      ['Certification body', _doorCertificationBodyLabel(door)],
      ['Result', resultText],
      ['Inspection date', _date(door.inspectionDate)],
    ];

    return _sectionCard(
      title: 'Door Summary',
      trailing: _statusBadge(resultText, resultColor, resultBg),
      child: _detailGrid(rows, columns: 2),
    );
  }

  static pw.Widget _inspectionResultsSection(Door door) {
    final categories = <String, List<InspectionCheckDefinition>>{};
    for (final check in inspectionChecks) {
      if (!door.hasGlazing && isGlazingCheck(check.id)) {
        continue;
      }
      final sectionTitle = inspectionSectionTitle(check.section);
      categories
          .putIfAbsent(sectionTitle, () => <InspectionCheckDefinition>[])
          .add(check);
    }

    final rows = <List<String>>[];
    for (final entry in categories.entries) {
      var hasFail = false;
      var hasPass = false;
      var allNa = true;
      var hasAny = false;

      for (final check in entry.value) {
        final outcome = door.inspectionResults[check.id.name]?.outcome;
        if (outcome == null || outcome == InspectionOutcome.notAnswered) {
          continue;
        }
        hasAny = true;
        if (outcome != InspectionOutcome.notApplicable) {
          allNa = false;
        }
        if (outcome == InspectionOutcome.criticalFail ||
            outcome == InspectionOutcome.fail ||
            outcome == InspectionOutcome.advisory) {
          hasFail = true;
        }
        if (outcome == InspectionOutcome.pass) hasPass = true;
      }

      final result = !hasAny || allNa
          ? 'N/A'
          : hasFail
              ? 'FAIL'
              : hasPass
                  ? 'PASS'
                  : 'N/A';
      rows.add([entry.key, result]);
    }

    return _sectionCard(
      title: 'Inspection Record',
      child: pw.Table(
        border: pw.TableBorder.all(color: _softLine, width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.8),
          1: pw.FlexColumnWidth(1.2)
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _sectionTint),
            children: [
              _tCellHdr('Category'),
              _tCellHdr('Result'),
            ],
          ),
          ...rows.map((row) {
            final status = row[1];
            return pw.TableRow(
              children: [
                _tCell(row[0]),
                _tCellResult(status, _resultStyle(status)),
              ],
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _fullDoorsetReplacementSection(Door door) {
    final isSingleLeaf = door.configuration == DoorConfiguration.singleLeaf;
    final openingWidth = _cleanText(door.replacementDoor1Width);
    final openingHeight = _cleanText(door.replacementDoor1Height);
    final approxLeaf1Width = _cleanText(door.replacementDoor2Width);
    final approxLeaf2Width = _cleanText(door.replacementDoor2Height);

    final rows = <List<String>>[
      ['Overall result', 'FAIL'],
      ['Configuration', _doorConfigurationLabel(door.configuration)],
      [
        isSingleLeaf ? 'Opening width (mm)' : 'Overall opening width (mm)',
        openingWidth.isEmpty ? '-' : openingWidth,
      ],
      ['Opening height (mm)', openingHeight.isEmpty ? '-' : openingHeight],
    ];

    if (!isSingleLeaf) {
      rows.addAll([
        [
          'Leaf 1 approximate width (mm)',
          approxLeaf1Width.isEmpty ? '-' : approxLeaf1Width
        ],
        [
          'Leaf 2 approximate width (mm)',
          approxLeaf2Width.isEmpty ? '-' : approxLeaf2Width
        ],
      ]);
    }

    final replacementEvidence = _replacementEvidenceTiles(door);

    return _sectionCard(
      title: 'Full Doorset Replacement Required',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Replacement doorset / opening dimensions',
            style: _style(8.8, bold: true, color: _text),
          ),
          pw.SizedBox(height: 6),
          _detailGrid(rows, columns: 2),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              color: _panelAlt,
              border: pw.Border.all(color: _softLine, width: 0.8),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              _replacementDimensionDisclaimerPdfMessage,
              style: _style(7.6, color: _secondaryText),
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            'Replacement evidence photos',
            style: _style(8.4, bold: true, color: _text),
          ),
          pw.SizedBox(height: 5),
          if (replacementEvidence.isEmpty)
            pw.Text('None uploaded', style: _style(7.8, color: _secondaryText))
          else
            _photoLayout(replacementEvidence),
        ],
      ),
    );
  }

  static List<({List<int> bytes, String caption})> _replacementEvidenceTiles(
      Door door) {
    final targetIds = _replacementEvidencePhotoIds(door);
    if (targetIds.isEmpty) return const [];

    final tiles = <({List<int> bytes, String caption})>[];
    final seen = <String>{};
    var index = 1;

    for (final photo in door.doorPhotos) {
      if (!targetIds.contains(photo.id) || _isVideoMedia(photo)) {
        continue;
      }
      final normalized = _normalizePhotoBytes(photo.bytes);
      if (normalized == null) continue;
      final key = _photoFingerprint(normalized);
      if (!seen.add(key)) continue;
      tiles.add((bytes: normalized, caption: 'Replacement evidence $index'));
      index += 1;
    }

    return tiles;
  }

  static Set<String> _replacementEvidencePhotoIds(Door door) {
    final meta = _parseFireDoorMetaMap(_cleanText(door.fireStoppingItemType));
    final raw = _cleanText(meta['certPhotoIds'] ?? '');
    if (raw.isEmpty) return const {};
    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  static Map<String, String> _parseFireDoorMetaMap(String raw) {
    final value = raw.trim();
    if (value.isEmpty || !value.contains('=')) return const {};

    final map = <String, String>{};
    for (final pair in value.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = Uri.decodeComponent(pair.substring(0, eq));
      final val = Uri.decodeComponent(pair.substring(eq + 1));
      map[key] = val;
    }
    return map;
  }

  static List<pw.Widget> _recommendedActionsWidgets(Door door) {
    return const [];
  }

  /// Compact table listing every non-conformity (replaces large block cards).
  static pw.Widget? _defectsTableWidget(Door door) {
    final failEntries = _failedEntries(door);
    if (failEntries.isEmpty) return null;

    final commentedEntries = failEntries.where((entry) {
      final comment = _cleanText(entry.value.comment.trim());
      return comment.isNotEmpty;
    }).toList();

    // Render this section only when there are additional inspector comments.
    if (commentedEntries.isEmpty) return null;

    return _sectionCard(
      title: 'Non-Conformities / Defects',
      child: pw.Table(
        border: pw.TableBorder.all(color: _softLine, width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.4),
          1: pw.FlexColumnWidth(1.8),
          2: pw.FlexColumnWidth(2.4),
          3: pw.FlexColumnWidth(0.65),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _sectionTint),
            children: [
              _tCellHdr('ART / Item'),
              _tCellHdr('Issue'),
              _tCellHdr('Recommended Actions'),
              _tCellHdr('Result'),
            ],
          ),
          ...commentedEntries.map((entry) {
            final check = _findCheck(entry.key);
            final result = entry.value;
            final artCode = check?.artCodeOnFail;
            final title = _cleanText(check?.title ?? entry.key);
            final artHeading = artCode == null
                ? title
                : 'ART${artCode.toString().padLeft(2, '0')} $title';
            final outcomeLabel = 'FAIL';
            final issueText = _cleanText(result.comment.trim()).isNotEmpty
                ? _cleanText(result.comment.trim())
                : _cleanText(check?.helperText ?? 'Issue identified.');
            final gapText = _gapMeasurementsText(
              door: door,
              check: check,
              result: result,
            );
            final issueDetails = gapText == null
                ? issueText
                : '$issueText\nGap measurements: $gapText';
            final recommendation = result.recommendedAction.trim().isNotEmpty
                ? result.recommendedAction.trim()
                : (check?.recommendedAction ?? '');
            final recLines = _resolvedRecommendationLines(
              result: result,
              fallbackRecommendation: recommendation,
            );
            return pw.TableRow(
              children: [
                _tCell(artHeading, bold: true),
                _tCell(issueDetails),
                recLines.isEmpty ? _tCell('-') : _tCellMulti(recLines),
                _tCellResult(outcomeLabel, _resultStyle(outcomeLabel)),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// Deduplicated summary of all recommended actions across all defects.
  static pw.Widget? _recommendedActionsSummaryWidget(Door door) {
    final failEntries = _failedEntries(door);
    if (failEntries.isEmpty) return null;

    final allLines = <String>[];
    final seen = <String>{};
    for (final entry in failEntries) {
      final result = entry.value;
      final check = _findCheck(entry.key);
      final recommendation = result.recommendedAction.trim().isNotEmpty
          ? result.recommendedAction.trim()
          : (check?.recommendedAction ?? '');
      final lines = _resolvedRecommendationLines(
        result: result,
        fallbackRecommendation: recommendation,
      );
      for (final line in lines) {
        final key = line.trim().toLowerCase();
        if (key.isNotEmpty && seen.add(key)) {
          allLines.add(line.trim());
        }
      }
    }

    if (allLines.isEmpty) return null;

    final codePattern = RegExp(
        r'^(ART\d{2}[a-zA-Z]*(?:-custom)?)\s*(?:-|:)?\s*(.+)$',
        caseSensitive: false);
    return _sectionCard(
      title: 'Recommended Actions Summary',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: allLines.map((line) {
          final m = codePattern.firstMatch(line.trim());
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: m != null
                ? pw.RichText(
                    text: pw.TextSpan(children: [
                      pw.TextSpan(
                        text: '${m.group(1)} - ',
                        style: _style(7.8, bold: true, color: _info),
                      ),
                      pw.TextSpan(
                        text: _cleanText(m.group(2) ?? ''),
                        style: _style(7.8, color: _text),
                      ),
                    ]),
                  )
                : pw.Text(_cleanText(line), style: _style(7.8, color: _text)),
          );
        }).toList(),
      ),
    );
  }

  static List<String> _resolvedRecommendationLines({
    required InspectionCheckResult result,
    required String fallbackRecommendation,
  }) {
    final fromMappings = <String>[];
    for (final item in result.selectedActionMappings) {
      final actionText = _cleanText(item['actionText'] ?? '');
      final customText = _cleanText(item['customText'] ?? '');
      final text = actionText.isNotEmpty ? actionText : customText;
      if (text.isEmpty) {
        continue;
      }

      // Prefer the stored display code (e.g. 'ART22b'), then fall back to
      // actualArtCode ('ART22'), then uiCode ('ART04d').
      final displayCode = _cleanText(item['displayCode'] ?? '');
      final actualArtCode = _cleanText(item['actualArtCode'] ?? '');
      final uiCode = _cleanText(item['uiCode'] ?? '');
      final prefix = displayCode.isNotEmpty
          ? displayCode
          : actualArtCode.isNotEmpty
              ? actualArtCode
              : uiCode;

      if (prefix.isNotEmpty) {
        fromMappings.add('$prefix - $text'.trim());
      } else {
        fromMappings.add(text);
      }
    }

    if (fromMappings.isNotEmpty) {
      return fromMappings;
    }

    return fallbackRecommendation
        .split('\n')
        .map(_normalizeRecommendationLineForPdf)
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String _normalizeRecommendationLineForPdf(String raw) {
    final line = raw.trim();
    if (line.isEmpty) {
      return '';
    }

    final m = RegExp(
      r'^(ART\d{2}[a-zA-Z]*(?:-custom)?)\s*(?:-|:)?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (m == null) {
      return line;
    }

    final code = _cleanText(m.group(1) ?? '');
    final text = _cleanText(m.group(2) ?? '');
    if (code.isEmpty || text.isEmpty) {
      return line;
    }
    return '$code - $text';
  }

  static pw.Widget? _videoEvidenceWidget(
      {required Survey survey, required Door door}) {
    final isFireStopping = survey.type == SurveyType.fireStopping;
    if (isFireStopping) {
      return null;
    }

    final links = <String>[];
    final seenLinks = <String>{};

    for (final result in door.inspectionResults.values) {
      final url = result.optionalVideoPath.trim();
      if (url.isEmpty) continue;
      final isHttp = url.startsWith('http://') || url.startsWith('https://');
      if (!isHttp) continue;
      if (seenLinks.add(url)) {
        links.add(url);
      }
    }

    final videoFileNames = <String>[];
    final seenNames = <String>{};
    for (final media in door.doorPhotos) {
      if (!media.mimeType.startsWith('video/')) continue;
      final name =
          media.fileName.trim().isEmpty ? 'video_file' : media.fileName.trim();
      if (seenNames.add(name)) {
        videoFileNames.add(name);
      }
    }

    if (links.isEmpty && videoFileNames.isEmpty) return null;

    final items = <pw.Widget>[];
    for (var i = 0; i < links.length; i++) {
      items.add(
        pw.UrlLink(
          destination: links[i],
          child: pw.Text(
            links[i],
            style: _style(8.2, color: _info).copyWith(
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ),
      );
      if (i < links.length - 1 || videoFileNames.isNotEmpty) {
        items.add(pw.SizedBox(height: 4));
      }
    }
    for (var i = 0; i < videoFileNames.length; i++) {
      items.add(
        pw.Text(
          'Video: ${_cleanText(videoFileNames[i])}',
          style: _style(8.2, color: _text),
        ),
      );
      if (i < videoFileNames.length - 1) {
        items.add(pw.SizedBox(height: 4));
      }
    }

    return _sectionCard(
      title: 'Video Evidence:',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: items,
      ),
    );
  }

  static List<pw.Widget> _photoEvidenceWidgets(
      {required Survey survey, required Door door}) {
    final tiles = _gatherPhotoTiles(survey: survey, door: door);
    if (tiles.isEmpty) {
      return const [];
    }

    return [
      _sectionHeader('Photo Evidence'),
      pw.SizedBox(height: 10),
      _photoLayout(tiles),
    ];
  }

  static pw.Widget _photoLayout(
      List<({List<int> bytes, String caption})> photos) {
    if (photos.length == 1) {
      final photo = photos.first;
      return pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: _photoTile(
          bytes: photo.bytes,
          caption: photo.caption,
          width: _singlePhotoMaxWidth,
          imageHeight: _singlePhotoHeight,
          captionLines: 3,
        ),
      );
    }

    return pw.Wrap(
      spacing: _gridGap,
      runSpacing: _gridGap,
      children: [
        for (final photo in photos)
          _photoTile(
            bytes: photo.bytes,
            caption: photo.caption,
            width: _photoTileWidth,
            imageHeight: _photoTileHeight,
            captionLines: 2,
          ),
      ],
    );
  }

  static pw.Widget _sectionHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(
          horizontal: _sectionPadding, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _panelAlt,
        border: pw.Border.all(color: _softLine),
        borderRadius: pw.BorderRadius.circular(_cardRadius),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(_cleanText(title),
              style: _style(10.2, bold: true, color: _text)),
          pw.SizedBox(height: 3),
          pw.Container(height: 1, color: _softLine),
        ],
      ),
    );
  }

  static pw.Widget _photoTile({
    required List<int> bytes,
    required String caption,
    required double width,
    required double imageHeight,
    required int captionLines,
  }) {
    final image = pw.MemoryImage(Uint8List.fromList(bytes));
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: _panel,
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(_cardRadius),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            height: imageHeight,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _panelAlt,
              border: pw.Border.all(color: _softLine),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            padding: const pw.EdgeInsets.all(8),
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            _cleanText(caption),
            style: _style(7.1, color: _secondaryText),
            maxLines: captionLines,
          ),
        ],
      ),
    );
  }

  static List<({List<int> bytes, String caption})> _gatherPhotoTiles(
      {required Survey survey, required Door door}) {
    final result = <({List<int> bytes, String caption})>[];
    final seen = <String>{};
    final isFireStopping = survey.type == SurveyType.fireStopping;

    if (isFireStopping) {
      final photoBytes = <List<int>>[];
      for (final photo in door.doorPhotos) {
        if (_isVideoMedia(photo)) continue;
        final normalized = _normalizePhotoBytes(photo.bytes);
        if (normalized == null) continue;
        final key = _photoFingerprint(normalized);
        if (!seen.add(key)) continue;
        photoBytes.add(normalized);
      }
      for (var i = 0; i < photoBytes.length; i++) {
        result.add((
          bytes: photoBytes[i],
          caption: _cleanText('Pin Photo ${i + 1} of ${photoBytes.length}')
        ));
      }
      return result;
    }

    for (final entry in door.inspectionResults.entries) {
      final inspection = entry.value;
      final outcome = inspection.outcome;
      if (outcome == InspectionOutcome.notAnswered ||
          outcome == InspectionOutcome.notApplicable) {
        continue;
      }
      if (inspection.photos.isEmpty) {
        continue;
      }

      final check = _findCheck(entry.key);
      final isFail = outcome == InspectionOutcome.fail ||
          outcome == InspectionOutcome.criticalFail;
      final artCode = isFail ? check?.artCodeOnFail : null;
      final title = _cleanText(check?.title ?? 'Inspection item');
      final outcomeLabel = outcome == InspectionOutcome.pass
          ? 'PASS'
          : isFail || outcome == InspectionOutcome.advisory
              ? 'FAIL'
              : 'INSPECTION';
      final artLabel =
          artCode == null ? '' : 'ART${artCode.toString().padLeft(2, '0')} - ';
      for (final photo in inspection.photos) {
        final normalized = _normalizePhotoBytes(photo.bytes);
        if (normalized == null) continue;
        final key = _photoFingerprint(normalized);
        if (!seen.add(key)) continue;
        result.add((
          bytes: normalized,
          caption: _cleanText('$outcomeLabel - $artLabel$title')
        ));
      }
    }

    for (final item in door.remedialItems) {
      for (final photo in item.originalInspectionPhotos) {
        final normalized = _normalizePhotoBytes(photo.bytes);
        if (normalized == null) continue;
        final key = _photoFingerprint(normalized);
        if (!seen.add(key)) continue;
        result.add(
            (bytes: normalized, caption: _cleanText('Before - ${item.title}')));
      }
      for (final photo in item.afterRepairPhotos) {
        final normalized = _normalizePhotoBytes(photo.bytes);
        if (normalized == null) continue;
        final key = _photoFingerprint(normalized);
        if (!seen.add(key)) continue;
        result.add(
            (bytes: normalized, caption: _cleanText('After - ${item.title}')));
      }
    }

    for (final photo in door.doorPhotos) {
      // Skip videos by checking both MIME type and file extension
      if (_isVideoMedia(photo)) continue;

      final normalized = _normalizePhotoBytes(photo.bytes);
      if (normalized == null) continue;
      final key = _photoFingerprint(normalized);
      if (!seen.add(key)) continue;
      final labelPrefix = isFireStopping ? 'Item' : 'Door';
      result.add((
        bytes: normalized,
        caption: _cleanText('$labelPrefix - ${_safeDoorRef(door)}')
      ));
    }

    return result;
  }

  static List<int>? _normalizePhotoBytes(List<int> source) {
    if (source.isEmpty) return null;
    try {
      final decoded = img.decodeImage(Uint8List.fromList(source));
      if (decoded == null) return null;
      return img.encodeJpg(decoded, quality: 88);
    } catch (_) {
      return null;
    }
  }

  /// Check if media is a video file (by MIME type or file extension)
  static bool _isVideoMedia(PhotoAttachment media) {
    // Check MIME type first
    if (media.mimeType.startsWith('video/')) {
      return true;
    }

    // Check file extension as fallback
    final ext = media.fileName.toLowerCase().split('.').last;
    return const [
      'mp4',
      'mov',
      'webm',
      'm4v',
      'avi',
      'mkv',
      '3gp',
      'flv',
      'wmv',
      'webm'
    ].contains(ext);
  }

  static Future<pw.Widget?> _fireStoppingDrawingReferenceWidget(
      {required Survey survey, required Door door}) async {
    if (survey.projectDrawings.isEmpty) return null;

    String metaDrawingId = _cleanText(door.doorDrawingId);
    String metaPinId = _cleanText(door.doorPinId);
    if (survey.type == SurveyType.fireStopping) {
      final meta = _cleanText(door.fireStoppingItemType).trim();
      if (meta.contains('=')) {
        for (final part in meta.split(';')) {
          final eq = part.indexOf('=');
          if (eq <= 0) continue;
          final key = part.substring(0, eq).trim().toLowerCase();
          final value = part.substring(eq + 1).trim();
          if (key == 'drawing') metaDrawingId = value;
          if (key == 'pin') metaPinId = value;
        }
      }
    }

    if (metaPinId.isEmpty || metaDrawingId.isEmpty) {
      return null;
    }

    ProjectDrawing? matchedDrawing;
    FloorPlanPin? matchedPin;

    for (final drawing in survey.projectDrawings) {
      for (final pin in drawing.pins) {
        final byMeta = (metaPinId.isNotEmpty && pin.id == metaPinId) &&
            (metaDrawingId.isEmpty || drawing.id == metaDrawingId);
        if (byMeta) {
          matchedDrawing = drawing;
          matchedPin = pin;
          break;
        }
      }
      if (matchedPin != null) break;
    }

    if (matchedDrawing == null || matchedPin == null) return null;

    final sourceBytes = await _drawingSourceBytesForPreview(
        drawing: matchedDrawing, page: matchedPin.page);
    if (sourceBytes == null) {
      return _sectionCard(
        title: 'Drawing Reference',
        child: pw.Text(
          _cleanText(
              'Pin linked but drawing preview is unavailable for this file.'),
          style: _style(7.9, color: _secondaryText),
        ),
      );
    }

    final decoded = img.decodeImage(Uint8List.fromList(sourceBytes));
    if (decoded == null) {
      return _sectionCard(
        title: 'Drawing Reference',
        child: pw.Text(
          _cleanText('Pin linked but drawing preview could not be decoded.'),
          style: _style(7.9, color: _secondaryText),
        ),
      );
    }

    final full = img.copyResize(
      decoded,
      width: decoded.width > 2200 ? 2200 : decoded.width,
    );
    final markerX = (matchedPin.x.clamp(0.0, 1.0) * full.width)
        .round()
        .clamp(0, full.width - 1);
    final markerY = (matchedPin.y.clamp(0.0, 1.0) * full.height)
        .round()
        .clamp(0, full.height - 1);
    final cropHalfWidth = math.min(360, full.width ~/ 2);
    final cropHalfHeight = math.min(250, full.height ~/ 2);
    final left = math.max(0, markerX - cropHalfWidth);
    final top = math.max(0, markerY - cropHalfHeight);
    final right = math.min(full.width - 1, markerX + cropHalfWidth);
    final bottom = math.min(full.height - 1, markerY + cropHalfHeight);
    final cropWidth = math.max(1, right - left);
    final cropHeight = math.max(1, bottom - top);

    final snippet = img.copyCrop(
      full,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );

    final localX = (markerX - left).clamp(0, snippet.width - 1);
    final localY = (markerY - top).clamp(0, snippet.height - 1);
    img.fillCircle(snippet,
        x: localX, y: localY, radius: 11, color: img.ColorRgb8(198, 40, 40));
    img.drawCircle(snippet,
        x: localX, y: localY, radius: 18, color: img.ColorRgb8(255, 255, 255));
    img.drawCircle(snippet,
        x: localX, y: localY, radius: 19, color: img.ColorRgb8(255, 255, 255));
    final snippetBytes = img.encodeJpg(snippet, quality: 92);

    final rawPinLabel = _cleanText(matchedPin.label).isNotEmpty
        ? _cleanText(matchedPin.label)
        : _cleanText(matchedPin.doorNumber);
    final pinPrefix = survey.type == SurveyType.fireStopping
        ? 'Pin'
        : (survey.type == SurveyType.snagging ? 'Snag Pin' : 'Door Pin');
    final pinLabel = rawPinLabel.toLowerCase().startsWith('pin')
        ? rawPinLabel
        : '$pinPrefix $rawPinLabel';
    final title = survey.type == SurveyType.fireStopping
        ? 'Drawing Reference'
        : (survey.type == SurveyType.snagging
            ? 'Snagging Plan Reference'
            : 'Door Plan Reference');

    return _sectionCard(
      title: title,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _cleanText(pinLabel),
            style: _style(8.0, bold: true, color: _text),
          ),
          pw.SizedBox(height: 5),
          pw.Container(
            width: _contentWidth * 0.58,
            height: 150,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: _panelAlt,
              border: pw.Border.all(color: _softLine),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Image(
              pw.MemoryImage(Uint8List.fromList(snippetBytes)),
              fit: pw.BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  static Future<List<int>?> _drawingSourceBytesForPreview({
    required ProjectDrawing drawing,
    required int page,
  }) async {
    final isPdf = drawing.mimeType.toLowerCase().contains('pdf') ||
        drawing.fileName.toLowerCase().endsWith('.pdf');
    if (!isPdf) {
      return drawing.bytes;
    }

    try {
      final targetPage = math.max(0, page - 1);
      await for (final raster in Printing.raster(
          Uint8List.fromList(drawing.bytes),
          pages: [targetPage],
          dpi: 240)) {
        final bytes = await raster.toPng();
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _composeFireStoppingDefectDescription(
      FireStoppingDefect defect) {
    final template = _cleanText(defect.template);
    final description = _cleanText(defect.description);
    final dimensions = [
      if (_cleanText(defect.lengthMm).isNotEmpty)
        'L: ${_cleanText(defect.lengthMm)} mm',
      if (_cleanText(defect.widthMm).isNotEmpty)
        'W: ${_cleanText(defect.widthMm)} mm',
    ].join(', ');
    final mainText = description.isNotEmpty ? description : template;
    if (mainText.isEmpty) return dimensions;
    if (dimensions.isEmpty) return mainText;
    return '$mainText | $dimensions';
  }

  static String _fireStoppingStatusLabel(Door door) {
    return door.approvedAt != null ? 'Completed' : 'Action Required';
  }

  static String _fireStoppingNotes(Door door) {
    final firstDefect = _primaryFireStoppingDefect(door);
    final notes = _cleanText(firstDefect?.description ?? '');
    if (notes.isNotEmpty) return notes;
    final legacy = _cleanText(door.fireStoppingDefectDescription);
    return legacy.isNotEmpty ? legacy : '-';
  }

  static String _fireStoppingAcousticRating(
      {required Door door, required FireStoppingDefect? defect}) {
    final defectRating = _cleanText(defect?.fireRating ?? '');
    if (defectRating.isNotEmpty) return defectRating;
    final legacyRating = _cleanText(door.fireStoppingFireRating);
    if (legacyRating.isNotEmpty) return legacyRating;
    final fallback = _cleanText(_fireRatingLabel(door.fireRating));
    return fallback.isEmpty || fallback == 'Unknown' ? '-' : fallback;
  }

  static FireStoppingDefect? _primaryFireStoppingDefect(Door door) {
    if (door.fireStoppingDefects.isNotEmpty)
      return door.fireStoppingDefects.first;
    if (door.fireStoppingDefectDescription.trim().isEmpty &&
        door.fireStoppingRecommendedAction.trim().isEmpty) {
      return null;
    }
    return FireStoppingDefect(
      id: 'legacy',
      fireRating: door.fireStoppingFireRating,
      serviceType: door.fireStoppingServiceType,
      description: door.fireStoppingDefectDescription,
      recommendedAction: door.fireStoppingRecommendedAction,
    );
  }

  static String _fireStoppingPinLabel({Survey? survey, required Door door}) {
    String drawingId = _cleanText(door.doorDrawingId);
    String pinId = _cleanText(door.doorPinId);
    if (survey?.type == SurveyType.fireStopping) {
      final meta = _cleanText(door.fireStoppingItemType);
      if (meta.contains('=')) {
        for (final part in meta.split(';')) {
          final eq = part.indexOf('=');
          if (eq <= 0) continue;
          final key = part.substring(0, eq).trim().toLowerCase();
          final value = part.substring(eq + 1).trim();
          if (key == 'drawing') drawingId = value;
          if (key == 'pin') pinId = value;
        }
      }
    }
    if (pinId.isEmpty) {
      return survey?.type == SurveyType.fireStopping ? _safeDoorRef(door) : '';
    }
    if (survey != null) {
      for (final drawing in survey.projectDrawings) {
        if (drawingId.isNotEmpty && drawing.id != drawingId) continue;
        for (final pin in drawing.pins) {
          if (pinId.isNotEmpty && pin.id == pinId) {
            return _cleanText(
                pin.label.isNotEmpty ? pin.label : pin.doorNumber);
          }
        }
      }
    }
    return survey?.type == SurveyType.fireStopping ? _safeDoorRef(door) : '';
  }

  static Approval? _latestApproval(Door door) {
    Approval? latest;
    for (final item in door.remedialItems) {
      final approval = item.approval;
      if (approval == null) {
        continue;
      }
      if (latest == null ||
          approval.approvedDate.isAfter(latest.approvedDate)) {
        latest = approval;
      }
    }
    return latest;
  }

  static InspectionCheckDefinition? _findCheck(String key) {
    for (final check in inspectionChecks) {
      if (check.id.name == key) {
        return check;
      }
    }
    return null;
  }

  static String _reportReference(Survey survey) {
    return _cleanText(survey.reference);
  }

  static String _registerReference(
      Survey survey, Approval? approval, Door door) {
    final projectRegisterReference = _cleanText(survey.registerReference);
    if (projectRegisterReference.isNotEmpty) {
      return projectRegisterReference;
    }
    final override = approval == null
        ? ''
        : _cleanText(approval.certificateJobReferenceOverride);
    if (override.isNotEmpty) {
      return override;
    }
    // MANDATORY RULE: Never auto-generate Register Reference Number.
    // Return empty string if no manual entry was provided.
    return '';
  }

  static String _reportTitleForType(SurveyType type) {
    switch (type) {
      case SurveyType.maintenance:
        return 'FIRE DOOR MAINTENANCE REPORT';
      case SurveyType.fireStopping:
        return 'FIRE STOPPING INSPECTION REPORT';
      case SurveyType.snagging:
        return 'SNAGGING INSPECTION REPORT';
      case SurveyType.survey:
      case SurveyType.installation:
      case SurveyType.installationSurvey:
        return 'FIRE DOOR INSPECTION REPORT';
    }
  }

  static String _inspectorName(Survey survey, Approval? approval, Door door) {
    final bySurvey = _cleanText(survey.reportCompletedBy);
    if (bySurvey.isNotEmpty) {
      return bySurvey;
    }
    final byApproval = _cleanText(approval?.approvedBy ?? '');
    if (byApproval.isNotEmpty) {
      return byApproval;
    }
    final byDoor = _cleanText(door.approvedMaintainerName);
    if (byDoor.isNotEmpty) {
      return byDoor;
    }
    return 'Not provided';
  }

  static RemedialItem? _findRemedialForIssue(
      {required Door door,
      required String issueId,
      required String checkTitle}) {
    for (final item in door.remedialItems) {
      if (_cleanText(item.issueId) == _cleanText(issueId)) {
        return item;
      }
      if (_cleanText(item.title).toLowerCase() ==
          _cleanText(checkTitle).toLowerCase()) {
        return item;
      }
    }
    return null;
  }

  static String _resolveCompanyName(String companyName) {
    final clean = _cleanText(companyName);
    return clean.isEmpty ? kDefaultSystemCompanyName : clean;
  }

  static String _resolveCompanyEmail(String companyEmail) {
    final clean = _cleanText(companyEmail);
    return clean.isEmpty ? _defaultSupportEmail : clean;
  }

  static String _resolveCompanyPhone(String companyPhone) {
    final clean = _cleanText(companyPhone);
    return clean.isEmpty ? _defaultSupportPhone : clean;
  }

  static ({PdfColor color, PdfColor background}) _resultStyle(String status) {
    final normalized = _cleanText(status).toUpperCase();
    if (normalized == 'PASS') {
      return (color: _pass, background: _passBg);
    }
    if (normalized == 'FAIL' ||
        normalized == 'ADVISORY' ||
        normalized == 'CRITICAL FAIL') {
      return (color: _fail, background: _failBg);
    }
    return (
      color: PdfColor.fromInt(0xFF6B7280),
      background: PdfColor.fromInt(0xFFF3F4F6),
    );
  }

  static String _overallResultLabel(Door door) {
    if (door.replacementRequired) return 'FAIL';

    var hasFail = false;
    var hasPass = false;

    for (final result in door.inspectionResults.values) {
      final outcome = result.outcome;
      if (outcome == InspectionOutcome.notAnswered ||
          outcome == InspectionOutcome.notApplicable) {
        continue;
      }
      if (outcome == InspectionOutcome.criticalFail ||
          outcome == InspectionOutcome.fail ||
          outcome == InspectionOutcome.advisory) {
        hasFail = true;
      }
      if (outcome == InspectionOutcome.pass) hasPass = true;
    }

    if (hasFail) return 'FAIL';
    if (hasPass) return 'PASS';
    return 'N/A';
  }

  static String _doorResultLabel(Door door) {
    return _isPass(door) ? 'PASS' : 'FAIL';
  }

  static String _doorLocation(Door door) {
    final area = _cleanText(door.area);
    final floor = _cleanText(door.floor);
    if (area.isNotEmpty && floor.isNotEmpty) {
      return '$area / $floor';
    }
    return area.isNotEmpty ? area : (floor.isNotEmpty ? floor : '-');
  }

  static String _doorMaterialLabel(Door door) {
    if (door.material == DoorMaterial.otherCustom &&
        _cleanText(door.customMaterial).isNotEmpty) {
      return _cleanText(door.customMaterial);
    }
    switch (door.material) {
      case DoorMaterial.timber:
        return 'Timber';
      case DoorMaterial.metalDoor:
        return 'Metal door';
      case DoorMaterial.composite:
        return 'Composite';
      case DoorMaterial.aluminium:
        return 'Aluminium';
      case DoorMaterial.upvc:
        return 'uPVC';
      case DoorMaterial.otherCustom:
        return 'Other (custom)';
      case DoorMaterial.unknown:
        return 'Unknown';
    }
  }

  static String _doorCertificationStatusLabel(
      DoorClassification classification) {
    switch (classification) {
      case DoorClassification.thirdPartyCertified:
        return 'Third-party certified';
      case DoorClassification.manufacturerEvidenceAvailable:
        return 'Manufacturer evidence available';
      case DoorClassification.noEvidenceClientStatedFireRated:
        return 'No evidence (client states door is fire-rated)';
      case DoorClassification.unknownNotVerified:
        return 'Unknown / not verified';
    }
  }

  static String _doorCertificationBodyLabel(Door door) {
    if (door.classification != DoorClassification.thirdPartyCertified) {
      return 'Not applicable';
    }
    final body = _cleanText(door.certificationBodyName);
    return body.isEmpty ? 'Not specified' : body;
  }

  static String _doorTypeLabel(DoorType type) {
    switch (type) {
      case DoorType.corridor:
        return 'Corridor';
      case DoorType.storeroom:
        return 'Storeroom';
      case DoorType.entrance:
        return 'Entrance';
      case DoorType.kitchen:
        return 'Kitchen';
      case DoorType.bedroom:
        return 'Bedroom';
      case DoorType.other:
        return 'Other';
    }
  }

  static String _doorFunctionLabel(DoorFunction function) {
    switch (function) {
      case DoorFunction.apartmentInternal:
        return 'Apartment Internal';
      case DoorFunction.flatEntrance:
        return 'Flat Entrance';
      case DoorFunction.corridor:
        return 'Corridor';
      case DoorFunction.stairwell:
        return 'Stairwell';
      case DoorFunction.communal:
        return 'Communal';
      case DoorFunction.other:
        return 'Other';
      case DoorFunction.unknown:
        return 'Unknown';
    }
  }

  static String _doorConfigurationLabel(DoorConfiguration configuration) {
    switch (configuration) {
      case DoorConfiguration.singleLeaf:
        return 'Single leaf';
      case DoorConfiguration.doubleLeaf:
        return 'Double leaf';
      case DoorConfiguration.leafAndAHalf:
        return 'Leaf and a half';
    }
  }

  static String? _gapMeasurementsText({
    required Door door,
    required InspectionCheckDefinition? check,
    required InspectionCheckResult result,
  }) {
    if (check?.id != InspectionCheckId.doorGapsIncorrect) {
      return null;
    }

    final parts = <String>[];
    if (result.gapTopMm != null)
      parts.add('Top ${_formatGapValue(result.gapTopMm!)} mm');
    if (result.gapBottomMm != null)
      parts.add('Bottom ${_formatGapValue(result.gapBottomMm!)} mm');
    if (result.gapLeftMm != null)
      parts.add('Left ${_formatGapValue(result.gapLeftMm!)} mm');
    if (result.gapRightMm != null)
      parts.add('Right ${_formatGapValue(result.gapRightMm!)} mm');

    final showMeeting = door.configuration == DoorConfiguration.doubleLeaf ||
        door.configuration == DoorConfiguration.leafAndAHalf;
    if (showMeeting && result.gapMeetingMm != null) {
      parts.add('Meeting ${_formatGapValue(result.gapMeetingMm!)} mm');
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(', ');
  }

  static String _formatGapValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  static String _gradingLevelLabel(GradingLevel value) {
    switch (value) {
      case GradingLevel.level1:
        return 'Level 1 (High evidence)';
      case GradingLevel.level2:
        return 'Level 2 (Moderate evidence)';
      case GradingLevel.level3:
        return 'Level 3 (Limited evidence)';
      case GradingLevel.level4:
        return 'Level 4 (No evidence / visual only)';
    }
  }

  static bool _isPass(Door door) {
    if (door.replacementRequired) {
      return false;
    }
    final hasFailure = door.issues.any(
      (issue) =>
          issue.severity == IssueSeverity.fail ||
          issue.severity == IssueSeverity.criticalFail ||
          issue.severity == IssueSeverity.advisory,
    );
    if (hasFailure) {
      return false;
    }
    return door.result == DoorResult.pass;
  }

  static pw.Widget _replacementRequiredBanner() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _failBg,
        border: pw.Border.all(color: _fail, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(
        _replacementRequiredPdfMessage,
        style: _style(8.2, bold: true, color: _fail),
      ),
    );
  }

  static pw.Widget _sectionCard(
      {required String title, required pw.Widget child, pw.Widget? trailing}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(_sectionPadding),
      decoration: pw.BoxDecoration(
        color: _panel,
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(_cardRadius),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Text(_cleanText(title),
                    style: _style(9.0, bold: true, color: _text)),
              ),
              if (trailing != null) trailing,
            ],
          ),
          pw.SizedBox(height: _sectionTitleGap),
          pw.Container(height: 1, color: _softLine),
          pw.SizedBox(height: _cardInnerGap),
          child,
        ],
      ),
    );
  }

  static pw.Widget _detailRows(List<List<String>> rows) {
    if (rows.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 118,
                child: pw.Text(
                  _cleanText(rows[index][0]),
                  style: _style(8.8, bold: true, color: _text),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Text(
                  _cleanText(rows[index][1]),
                  style: _style(8.9, color: _text),
                ),
              ),
            ],
          ),
          if (index < rows.length - 1) ...[
            pw.SizedBox(height: 7),
            pw.Container(height: 1, color: _softLine),
            pw.SizedBox(height: 7),
          ],
        ],
      ],
    );
  }

  static pw.Widget _detailGrid(List<List<String>> rows,
      {required int columns}) {
    final widgets = <pw.Widget>[];
    for (var index = 0; index < rows.length; index += columns) {
      final slice = rows.skip(index).take(columns).toList();
      widgets.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < slice.length; i++) ...[
              pw.Expanded(child: _detailTile(slice[i][0], slice[i][1])),
              if (i < slice.length - 1) pw.SizedBox(width: 10),
            ],
            for (var i = slice.length; i < columns; i++) ...[
              pw.Expanded(child: pw.SizedBox()),
              if (i < columns - 1) pw.SizedBox(width: 10),
            ],
          ],
        ),
      );
      if (index + columns < rows.length) {
        widgets
          ..add(pw.SizedBox(height: 10))
          ..add(pw.Container(height: 1, color: _softLine))
          ..add(pw.SizedBox(height: 10));
      }
    }
    return pw.Column(children: widgets);
  }

  static pw.Widget _detailTile(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(_cleanText(label),
            style: _style(8.1, bold: true, color: _secondaryText)),
        pw.SizedBox(height: 4),
        pw.Text(_cleanText(value),
            style: _style(9.5, bold: true, color: _text)),
      ],
    );
  }

  static pw.Widget _statusBadge(
      String label, PdfColor color, PdfColor background) {
    return pw.Container(
      constraints: const pw.BoxConstraints(minWidth: 48),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: color.shade(.65)),
      ),
      child: pw.Text(
        _cleanText(label),
        textAlign: pw.TextAlign.center,
        style: _style(7.4, bold: true, color: color),
      ),
    );
  }

  static pw.Widget _tableHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(_cleanText(text),
          style: _style(7.6, bold: true, color: _text)),
    );
  }

  static pw.Widget _tableCell(String text,
      {PdfColor? color, bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(_cleanText(text),
          style: _style(7.8, bold: bold, color: color ?? _text)),
    );
  }

  // ── Compact table cell helpers ──────────────────────────────────────────────

  /// Tight label cell used in compact tables.
  static pw.Widget _tCellHdr(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: pw.Text(_cleanText(text),
          style: _style(7.2, bold: true, color: _secondaryText)),
    );
  }

  /// Tight data cell used in compact tables.
  static pw.Widget _tCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: pw.Text(_cleanText(text),
          style: _style(7.7, bold: bold, color: _text)),
    );
  }

  /// Compact label/value table row.
  static pw.TableRow _compactRow(String label, String value) {
    return pw.TableRow(children: [_tCellHdr(label), _tCell(value)]);
  }

  /// Multi-line cell with ART codes bolded in accent colour.
  static pw.Widget _tCellMulti(List<String> lines) {
    final codePattern = RegExp(
        r'^(ART\d{2}[a-zA-Z]*(?:-custom)?)\s*(?:-|:)?\s*(.+)$',
        caseSensitive: false);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines.map((line) {
          final m = codePattern.firstMatch(line.trim());
          if (m != null) {
            return pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(
                    text: '${m.group(1)} - ',
                    style: _style(7.1, bold: true, color: _info)),
                pw.TextSpan(
                    text: _cleanText(m.group(2) ?? ''),
                    style: _style(7.1, color: _text)),
              ]),
            );
          }
          return pw.Text(_cleanText(line), style: _style(7.1, color: _text));
        }).toList(),
      ),
    );
  }

  /// Tight coloured result badge cell.
  static pw.Widget _tCellResult(
      String label, ({PdfColor color, PdfColor background}) style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: pw.BoxDecoration(
          color: style.background,
          border: pw.Border.all(color: style.color.shade(.65)),
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Text(_cleanText(label),
            style: _style(6.8, bold: true, color: style.color)),
      ),
    );
  }

  static String _safeSurveyName(Survey survey) {
    final reportName = _cleanText(survey.reportName);
    if (reportName.isNotEmpty) {
      return reportName;
    }
    final siteName = _cleanText(survey.siteName);
    return siteName.isEmpty ? 'Project' : siteName;
  }

  static String _projectAddress(Survey survey) {
    final line1 = _cleanText(survey.addressLine1);
    final line2 = _cleanText(survey.addressLine2);
    final city = _cleanText(survey.cityTown);
    final postCode = _cleanText(survey.postCode);
    final legacy = _cleanText(survey.siteAddress);

    final combined = [line1, line2, city, postCode]
        .where((part) => part.isNotEmpty)
        .join(', ');
    if (combined.isNotEmpty) {
      return combined;
    }
    if (legacy.isNotEmpty) {
      return legacy;
    }
    return 'Not provided';
  }

  static String _safeDoorRef(Door door) {
    final ref = _cleanText(door.doorIdTag);
    if (ref.isNotEmpty) {
      return ref;
    }
    return 'Door ${door.number.toString().padLeft(3, '0')}';
  }

  static bool _shouldShowDoorPin(
      bool isFireStopping, String pinLabel, Door door) {
    // MANDATORY DEDUPLICATION RULE:
    // Only show Door Pin row if:
    // 1. pinLabel is not empty
    // 2. It's a different value than Door ID / Reference
    if (pinLabel.isEmpty) return false;

    final doorRef = _cleanText(_safeDoorRef(door)).toLowerCase().trim();
    final pinRef = _cleanText(pinLabel).toLowerCase().trim();

    // If they're identical, don't show the duplicate
    if (doorRef == pinRef) return false;

    // Show only if they're different
    return true;
  }

  static String _safe(String value) {
    final clean = _cleanText(value);
    return clean.isEmpty ? '-' : clean;
  }

  static String _date(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  static String _nullableDate(DateTime? date) {
    return date == null ? '-' : _date(date);
  }

  static String _nullableDateTime(DateTime? date) {
    return date == null ? '-' : _dateTime(date);
  }

  static String _fmtTime(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String _dateTime(DateTime date) {
    final d = _date(date);
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$d $hh:$mm';
  }

  static String _photoFingerprint(List<int> bytes) {
    var hash = 5381;
    for (final b in bytes) {
      hash = ((hash << 5) + hash) ^ b;
    }
    return '${bytes.length}:$hash';
  }

  static pw.TextStyle _style(double size,
      {bool bold = false, required PdfColor color}) {
    return pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
      lineSpacing: 1.2,
    );
  }

  static Future<pw.ThemeData> _loadPdfTheme() async {
    try {
      final base = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      final italic = await PdfGoogleFonts.notoSansItalic();
      final boldItalic = await PdfGoogleFonts.notoSansBoldItalic();
      return pw.ThemeData.withFont(
        base: base,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
      );
    } catch (_) {
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      );
    }
  }

  static Future<pw.ImageProvider?> _loadLogo(List<int> companyLogoBytes) async {
    if (companyLogoBytes.isNotEmpty) {
      return _memoryImageFromBytes(companyLogoBytes);
    }
    final bytes = await _loadAssetBytes(_logoAssetPath);
    return bytes == null ? null : _memoryImageFromBytes(bytes);
  }

  static pw.MemoryImage? _memoryImageFromBytes(List<int> bytes) {
    final normalized = _normalizePhotoBytes(bytes);
    if (normalized == null || normalized.isEmpty) return null;
    return pw.MemoryImage(Uint8List.fromList(normalized));
  }

  static Future<Uint8List?> _loadAssetBytes(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static String _cleanText(String value) {
    if (value.isEmpty) {
      return '';
    }

    final lines = <String>[];
    final currentLine = StringBuffer();
    var previousWasSpace = false;

    void flushLine() {
      final line = currentLine.toString().trim();
      if (line.isNotEmpty) {
        lines.add(line);
      }
      currentLine.clear();
    }

    for (final rune in value.runes) {
      final replacement = switch (rune) {
        0x2013 || 0x2014 || 0x2212 => '-',
        0x2018 || 0x2019 => "'",
        0x201C || 0x201D => '"',
        0x2022 => '*',
        0x00A0 => ' ',
        _ => null,
      };
      final char = replacement ?? String.fromCharCode(rune);

      if (char == '\r') {
        continue;
      }
      if (char == '\n') {
        flushLine();
        previousWasSpace = false;
        continue;
      }

      final codePoint = char.runes.first;
      final isControl =
          codePoint < 0x20 || (codePoint >= 0x7F && codePoint <= 0x9F);
      if (isControl) {
        continue;
      }

      if (char == ' ' || char == '\t') {
        if (!previousWasSpace) {
          currentLine.write(' ');
          previousWasSpace = true;
        }
        continue;
      }

      currentLine.write(char);
      previousWasSpace = false;
    }

    flushLine();
    return lines.join('\n');
  }

  static String _fireRatingLabel(FireRating value) {
    switch (value) {
      case FireRating.notAFireDoor:
        return 'Not a fire door';
      case FireRating.fd30:
        return 'FD30';
      case FireRating.fd30s:
        return 'FD30S';
      case FireRating.fd60:
        return 'FD60';
      case FireRating.fd60s:
        return 'FD60S';
      case FireRating.fd90:
        return 'FD90';
      case FireRating.fd90s:
        return 'FD90S';
      case FireRating.fd120:
        return 'FD120';
      case FireRating.fd120s:
        return 'FD120S';
      case FireRating.unknown:
        return 'Unknown';
    }
  }
}
