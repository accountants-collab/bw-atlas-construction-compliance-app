import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/pdf/web_download_stub.dart'
    if (dart.library.html) '../../surveys/pdf/web_download.dart';

class FactorySupplierPdfBuilder {
  static const _logoAssetPath = kDefaultSystemLogoAssetPath;

  static final PdfColor _text = PdfColor.fromInt(0xFF333333);
  static final PdfColor _heading = PdfColor.fromInt(0xFF1A1A1A);
  static final PdfColor _section = PdfColor.fromInt(0xFFF0F4F8);
  static final PdfColor _accent = PdfColor.fromInt(0xFF0066CC);
  static final PdfColor _border = PdfColor.fromInt(0xFFD0D0D0);

  /// Generate Factory/Supplier Specification PDF for a single pre-install item
  static Future<Uint8List> buildFactorySpecPdf({
    required Survey survey,
    required PreInstallItem item,
    List<int> companyLogoBytes = const [],
    String companyName = kDefaultSystemCompanyName,
    String reportHeaderText = '',
    String reportFooterText = '',
  }) async {
    final doc = pw.Document();
    final logo = await _loadLogo(companyLogoBytes);

    doc.addPage(
      _buildFactorySpecPage(
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

  static pw.Page _buildFactorySpecPage({
    required Survey survey,
    required PreInstallItem item,
    required pw.ImageProvider? logo,
    required String companyName,
    required String reportHeaderText,
    required String reportFooterText,
  }) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final now = DateTime.now();

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header with logo and title
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logo != null) pw.Image(logo, width: 80, height: 60),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'FACTORY / SUPPLIER',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: _accent,
                      ),
                    ),
                    pw.Text(
                      'SPECIFICATION SHEET',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(color: _border, height: 20),

            // Project Header Section
            pw.Container(
              decoration: pw.BoxDecoration(
                color: _section,
                border: pw.Border.all(color: _border),
              ),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'PROJECT DETAILS',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _heading,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow(
                              'Project:',
                              survey.reportName.trim().isEmpty
                                  ? survey.siteName
                                  : survey.reportName),
                          _buildDetailRow('Reference:', survey.reference),
                          _buildDetailRow('Date:', dateFormat.format(now)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Survey Type:',
                              _surveyTypeLabel(item.surveyType)),
                          if (isSpecificationOrderWorkflowType(item.surveyType))
                            _buildDetailRow(
                              'Existing Door Removal:',
                              item.existingDoorRemovalRequired ? 'Yes' : 'No',
                            ),
                          _buildDetailRow('Company:', companyName),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Site Address:',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    [
                      survey.addressLine1,
                      survey.addressLine2,
                      survey.cityTown,
                      survey.postCode,
                    ]
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .join(', '),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Door/Opening Reference Section
            pw.Container(
              decoration: pw.BoxDecoration(
                color: _section,
                border: pw.Border.all(color: _border),
              ),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'DOOR / OPENING REFERENCE',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _heading,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Reference:', item.doorRef),
                          _buildDetailRow('Floor / Level:', item.level),
                          _buildDetailRow('Location:', item.location),
                          if (item.doorDrawingId.isNotEmpty)
                            _buildDetailRow('Drawing ID:', item.doorDrawingId),
                          if (item.doorPinId.isNotEmpty)
                            _buildDetailRow('DRW Pin:', item.doorPinId),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Fire Rating:', item.fireRating),
                          _buildDetailRow('Configuration:',
                              _configurationLabel(item.configuration)),
                          _buildDetailRow(
                              'Frame:', item.hasFrame ? 'Yes' : 'No'),
                          _buildDetailRow('Purpose:', item.doorPurpose),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Measurements Section
            pw.Container(
              decoration: pw.BoxDecoration(
                color: _section,
                border: pw.Border.all(color: _border),
              ),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'MEASUREMENTS & DIMENSIONS',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _heading,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _buildMeasurementsTable(item),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Specification Details
            pw.Container(
              decoration: pw.BoxDecoration(
                color: _section,
                border: pw.Border.all(color: _border),
              ),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'SPECIFICATION DETAILS',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _heading,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Frame Type:', item.frameType),
                          _buildDetailRow('Door Type:', item.doorType),
                          _buildDetailRow('Leaf Type:', item.leafType),
                          _buildDetailRow('Handing:', item.handingMode),
                          _buildDetailRow('Threshold:', item.threshold),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Glazing:', item.glazingType),
                          _buildDetailRow(
                              'Glazing Details:', item.glazingDetails),
                          _buildDetailRow('Seals:', item.seals),
                          _buildDetailRow('Colour / RAL:', item.colourRal),
                          _buildDetailRow('Finish:', item.finishType),
                        ],
                      ),
                    ],
                  ),
                  if (item.ironmongery.isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Ironmongery: ${item.ironmongery}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Notes Section
            if (item.preInstallComments.isNotEmpty ||
                item.manufactureNotes.isNotEmpty)
              pw.Container(
                decoration: pw.BoxDecoration(
                  color: _section,
                  border: pw.Border.all(color: _border),
                ),
                padding: const pw.EdgeInsets.all(12),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'NOTES & COMMENTS',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _heading,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    if (item.preInstallComments.isNotEmpty) ...[
                      pw.Text(
                        'Survey Comments:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        item.preInstallComments,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.SizedBox(height: 6),
                    ],
                    if (item.manufactureNotes.isNotEmpty) ...[
                      pw.Text(
                        'Manufacturing Notes:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        item.manufactureNotes,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ],
                ),
              ),
            pw.Spacer(),

            // Disclaimer Footer
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFFF8DC),
                border: pw.Border.all(color: PdfColor.fromInt(0xFFFFD700)),
              ),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'IMPORTANT DISCLAIMER',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF8B6914),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Dimensions and specifications recorded in this document are for pricing, specification, and manufacturing reference purposes only. Final manufacturing dimensions and site conditions must be verified before manufacture, ordering, or installation.',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: _text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static pw.Widget _buildDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 100,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '—' : value,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMeasurementsTable(PreInstallItem item) {
    final measurements = item.measurements;
    if (measurements == null) {
      return pw.Text(
        'No measurements recorded',
        style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _border),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _accent),
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(6),
              child: pw.Text(
                'Measurement',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(6),
              child: pw.Text(
                'Value (mm)',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
          ],
        ),
        if (item.hasFrame && measurements.frameWidth != null)
          _buildMeasurementRow('Overall Frame Width', measurements.frameWidth),
        if (item.hasFrame && measurements.frameHeight != null)
          _buildMeasurementRow(
              'Overall Frame Height', measurements.frameHeight),
        if (measurements.openingWidthMiddle != null)
          _buildMeasurementRow(
              item.hasFrame
                  ? 'Structural Opening Width'
                  : 'Opening Width (optional)',
              measurements.openingWidthMiddle),
        if (measurements.openingHeightCentre != null)
          _buildMeasurementRow(
              item.hasFrame
                  ? 'Structural Opening Height'
                  : 'Opening Height (optional)',
              measurements.openingHeightCentre),
        if (measurements.leafWidth != null)
          _buildMeasurementRow('Door Leaf Width', measurements.leafWidth),
        if (measurements.leafHeight != null)
          _buildMeasurementRow('Door Leaf Height', measurements.leafHeight),
        if (measurements.leafThickness != null)
          _buildMeasurementRow('Door Thickness', measurements.leafThickness),
        if (measurements.frameDepth != null)
          _buildMeasurementRow('Frame Depth', measurements.frameDepth),
      ],
    );
  }

  static pw.TableRow _buildMeasurementRow(String label, double? value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: pw.EdgeInsets.all(6),
          child: pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        pw.Padding(
          padding: pw.EdgeInsets.all(6),
          child: pw.Text(
            value != null ? value.toStringAsFixed(1) : '—',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
      ],
    );
  }

  static String _surveyTypeLabel(PreInstallSurveyType type) {
    if (isSpecificationOrderWorkflowType(type)) {
      return 'Specification / Order';
    }
    return 'Installation Only';
  }

  static String _configurationLabel(String config) {
    if (config.contains('double')) return 'Double Leaf';
    if (config.contains('side')) return 'With Side Panels';
    if (config.contains('over')) return 'With Over Panel';
    return 'Single Leaf';
  }

  static Future<pw.ImageProvider?> _loadLogo(List<int> companyLogoBytes) async {
    try {
      if (companyLogoBytes.isNotEmpty) {
        return pw.MemoryImage(Uint8List.fromList(companyLogoBytes));
      }
      final bytes = await rootBundle.load(_logoAssetPath);
      return pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }
}
