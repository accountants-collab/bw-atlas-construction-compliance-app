import 'dart:typed_data';

import 'package:fd_app/features/fire_door/inspection/domain/art_recommended_actions.dart';
import 'package:fd_app/features/fire_door/inspection/domain/inspection_definitions.dart';
import 'package:fd_app/features/fire_door/inspection/domain/models.dart';
import 'package:fd_app/features/fire_door/inspection/pdf/survey_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

List<int> _jpegBytes({int width = 320, int height = 220}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(230, 236, 244));
  return img.encodeJpg(image, quality: 85);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('N/A visibility matrix matches definitions', () {
    final allowsNa = <InspectionCheckId>{
      InspectionCheckId.holdOpenDevice,
      InspectionCheckId.damagedPerimeterSeals,
      InspectionCheckId.damagedGlazingSystem,
      InspectionCheckId.architraveSealingRefitOrReplace,
      InspectionCheckId.signage,
    };

    for (final check in inspectionChecks) {
      final hasNa = check.allowedOutcomes.contains(InspectionOutcome.notApplicable);
      if (allowsNa.contains(check.id)) {
        expect(hasNa, isTrue, reason: '${check.id.name} should allow N/A');
      } else {
        expect(hasNa, isFalse, reason: '${check.id.name} must not show N/A');
      }
    }
  });

  test('Applicability logic auto-targets only the intended checks', () {
    expect(
      isCheckApplicable(
        checkId: InspectionCheckId.doorCloserNotOperating,
        hasDoorCloser: false,
        hasSeals: true,
        hasGlazing: true,
        hasSignage: true,
      ),
      isFalse,
    );
    expect(
      isCheckApplicable(
        checkId: InspectionCheckId.damagedPerimeterSeals,
        hasDoorCloser: true,
        hasSeals: false,
        hasGlazing: true,
        hasSignage: true,
      ),
      isFalse,
    );
    expect(
      isCheckApplicable(
        checkId: InspectionCheckId.damagedGlazingSystem,
        hasDoorCloser: true,
        hasSeals: true,
        hasGlazing: false,
        hasSignage: true,
      ),
      isFalse,
    );
    expect(
      isCheckApplicable(
        checkId: InspectionCheckId.signage,
        hasDoorCloser: true,
        hasSeals: true,
        hasGlazing: true,
        hasSignage: false,
      ),
      isFalse,
    );

    // Unrelated check remains applicable.
    expect(
      isCheckApplicable(
        checkId: InspectionCheckId.doorLeafOutOfAlignment,
        hasDoorCloser: false,
        hasSeals: false,
        hasGlazing: false,
        hasSignage: false,
      ),
      isTrue,
    );
  });

  test('ART mapping is constrained and parent mappings are correct', () {
    for (final check in inspectionChecks) {
      if (check.artCodeOnFail == null) continue;
      final group = artGroupForCheck(check.id);
      expect(group, isNotNull, reason: 'Missing ART group for ${check.id.name}');
      expect(group!.parentArtNumber, check.artCodeOnFail);

      for (final option in group.options) {
        final mappings = buildSelectedActionMappings(
          selectedCodes: [option.code],
          customText: '',
          group: group,
        );
        expect(mappings, hasLength(1));
        final mapping = mappings.first;
        expect(mapping['uiCode'], option.code);
        expect(mapping['displayCode'], option.resolvedDisplayCode);
        expect(mapping['actualArtCode'], isNotNull);
        expect(mapping['actualArtCode']!.startsWith('ART'), isTrue);
      }
    }
  });

  test('Fire door PDF includes fail evidence photos payload', () async {
    final failPhoto = PhotoAttachment(
      fileName: 'fail-evidence.jpg',
      mimeType: 'image/jpeg',
      bytes: _jpegBytes(width: 240, height: 180),
    );

    final resultWithPhoto = InspectionCheckResult(
      outcome: InspectionOutcome.fail,
      comment: 'Closer not operating',
      recommendedAction: 'ART05c Replace door closer.',
      photos: [failPhoto],
      selectedActionCodes: const ['ART05c'],
      selectedActionMappings: const [
        {
          'uiCode': 'ART05c',
          'displayCode': 'ART05c',
          'actualArtCode': 'ART05',
          'actionText': 'Replace door closer.',
        },
      ],
    );

    final doorBase = Door(
      id: 'door-1',
      number: 1,
      doorIdTag: 'D-101',
      floor: 'L1',
      area: 'Corridor',
      fireRating: FireRating.fd30s,
      gradingLevel: GradingLevel.level2,
      inspectionDate: DateTime(2026, 4, 10),
      approvedMaintainerName: 'Inspector One',
    );

    final doorWithPhoto = doorBase.copyWith(
      inspectionResults: {
        InspectionCheckId.doorCloserNotOperating.name: resultWithPhoto,
      },
      issues: [
        Issue(
          artCode: 5,
          comment: 'Closer not operating',
          severity: IssueSeverity.fail,
          photos: [failPhoto],
          sourceKey: 'CHECK:doorCloserNotOperating',
        ),
      ],
      result: DoorResult.fail,
    );

    final doorWithoutPhoto = doorWithPhoto.copyWith(
      inspectionResults: {
        InspectionCheckId.doorCloserNotOperating.name: resultWithPhoto.copyWith(photos: const []),
      },
      issues: [
        Issue(
          artCode: 5,
          comment: 'Closer not operating',
          severity: IssueSeverity.fail,
          photos: const [],
          sourceKey: 'CHECK:doorCloserNotOperating',
        ),
      ],
    );

    final survey = Survey(
      id: 'survey-1',
      type: SurveyType.survey,
      workspace: InspectionWorkspace.fireDoor,
      reportName: 'Runtime Validation Site',
      addressLine1: '1 Test Street',
      cityTown: 'London',
      postCode: 'N1 1AA',
      reportCompletedBy: 'Inspector One',
      reference: 'JOB-RT-001',
      reportDate: DateTime(2026, 4, 10),
      doors: [doorWithPhoto],
    );

    final bytesWithPhoto = await SurveyPdfBuilder.buildSingleDoorPdf(survey, doorWithPhoto);
    final bytesWithoutPhoto = await SurveyPdfBuilder.buildSingleDoorPdf(survey, doorWithoutPhoto);

    expect(bytesWithPhoto, isNotEmpty);
    expect(Uint8List.fromList(bytesWithPhoto).length, greaterThan(1200));
    expect(
      Uint8List.fromList(bytesWithPhoto).length,
      greaterThan(Uint8List.fromList(bytesWithoutPhoto).length),
      reason: 'PDF with fail evidence should be larger because image payload is embedded.',
    );
  });
}
