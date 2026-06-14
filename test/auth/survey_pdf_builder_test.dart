import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fd_app/features/surveys/domain/models.dart';
import 'package:fd_app/features/surveys/pdf/survey_pdf.dart';
import 'package:image/image.dart' as img;

List<int> _jpegBytes({int w = 320, int h = 220}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(235, 239, 244));
  return img.encodeJpg(image, quality: 85);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildSingleDoorPdf: fire stopping linked drawing pin generates PDF bytes', () async {
    final drawingBytes = _jpegBytes();
    final drawing = ProjectDrawing(
      id: 'drw-1',
      name: 'Ground Plan',
      fileName: 'ground-plan.jpg',
      mimeType: 'image/jpeg',
      bytes: drawingBytes,
      pins: [
        FloorPlanPin(
          id: 'pin-1',
          drawingId: 'drw-1',
          x: 0.52,
          y: 0.47,
          doorNumber: 'Pin 1',
          label: 'Pin 1',
        ),
      ],
    );

    final door = Door(
      id: 'door-1',
      number: 1,
      doorIdTag: 'Pin 1',
      floor: 'Level 1',
      area: 'Plant room wall',
      inspectionDate: DateTime(2026, 4, 8),
      fireStoppingItemType: 'drawing=drw-1;pin=pin-1',
      fireStoppingDefects: [
        FireStoppingDefect(
          id: 'def-1',
          template: 'Void around cable',
          fireRating: '60',
          serviceType: 'Cable',
          description: 'Gap around cable penetration.',
          recommendedAction: 'Install tested fire-stopping system.',
          lengthMm: '140',
          widthMm: '90',
          drawingId: 'drw-1',
          pinId: 'pin-1',
        ),
      ],
      // Include one invalid image to verify safe skip logic.
      doorPhotos: [
        PhotoAttachment(
          fileName: 'broken.jpg',
          mimeType: 'image/jpeg',
          bytes: const [1, 2, 3, 4],
        ),
        PhotoAttachment(
          fileName: 'valid.jpg',
          mimeType: 'image/jpeg',
          bytes: _jpegBytes(w: 180, h: 140),
        ),
      ],
    );

    final survey = Survey(
      id: 's-1',
      type: SurveyType.fireStopping,
      workspace: InspectionWorkspace.fireStopping,
      reportName: 'Fire Stopping - Test Site',
      addressLine1: '12 Test Street',
      cityTown: 'London',
      postCode: 'N1 1AA',
      reportCompletedBy: 'Worker A',
      reference: 'JOB-001',
      reportDate: DateTime(2026, 4, 8),
      projectDrawings: [drawing],
      doors: [door],
    );

    final bytes = await SurveyPdfBuilder.buildSingleDoorPdf(
      survey,
      door,
      // Intentionally invalid logo bytes should be ignored safely.
      companyLogoBytes: const [1, 2, 3],
      companyName: 'Test Company',
    );

    expect(bytes, isNotEmpty);
    expect(Uint8List.fromList(bytes).length, greaterThan(1000));
  });

  test('buildSingleDoorPdf: fire stopping manual pin without drawing still builds', () async {
    final door = Door(
      id: 'door-2',
      number: 2,
      doorIdTag: 'PIN-MAN-22',
      floor: 'Room A',
      area: 'North wall',
      inspectionDate: DateTime(2026, 4, 8),
      fireStoppingItemType: '',
      fireStoppingDefects: const [
        FireStoppingDefect(
          id: 'def-2',
          template: 'Service opening',
          fireRating: '60',
          serviceType: 'Pipe',
          description: 'Unsealed annular space.',
          recommendedAction: 'Seal with tested material.',
          lengthMm: '120',
          widthMm: '75',
        ),
      ],
    );

    final survey = Survey(
      id: 's-2',
      type: SurveyType.fireStopping,
      workspace: InspectionWorkspace.fireStopping,
      reportName: 'Manual Pin Report',
      reference: 'JOB-002',
      reportDate: DateTime(2026, 4, 8),
      doors: [door],
    );

    final bytes = await SurveyPdfBuilder.buildSingleDoorPdf(
      survey,
      door,
      companyName: 'Test Company',
    );

    expect(bytes, isNotEmpty);
  });
}
