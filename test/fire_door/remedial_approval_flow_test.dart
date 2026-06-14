import 'dart:io';

import 'package:fd_app/features/surveys/domain/models.dart';
import 'package:fd_app/features/surveys/state/survey_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('fd_app_remedial_tests');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      try {
        await hiveDir.delete(recursive: true);
      } catch (_) {
        // Windows can briefly hold the Hive files after close; test assertions already ran.
      }
    }
  });

  test('approveDoorRemedial stores approval signature payload for PDF generation', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(surveyControllerFamilyProvider(InspectionWorkspace.fireDoor).notifier);

    final survey = controller.createSurvey(SurveyType.survey);
    final item = _buildRemedialItem(status: RemedialStatus.forApproval);
    final door = Door(
      id: 'door-1',
      number: 1,
      doorIdTag: 'D-001',
      remedialStatus: RemedialStatus.forApproval,
      remedialItems: [item],
    );
    controller.saveNewDoor(surveyId: survey.id, door: door);

    controller.approveDoorRemedial(
      surveyId: survey.id,
      doorId: door.id,
      approvedBy: 'Manager Name',
      defectPassByItemId: {item.id: true},
      signatureMethod: 'disclaimer',
      signatureImageBytes: const [1, 2, 3, 4],
      approvedMaintainerName: 'Maintainer',
      approvedMaintainerNumber: 'M-100',
    );

    final updatedDoor = controller.getDoorById(surveyId: survey.id, doorId: door.id);
    expect(updatedDoor, isNotNull);
    expect(updatedDoor!.remedialStatus, RemedialStatus.approved);
    final updatedItem = updatedDoor.remedialItems.single;
    expect(updatedItem.status, RemedialStatus.approved);
    expect(updatedItem.approvedBy, 'Manager Name');
    expect(updatedItem.approval, isNotNull);
    expect(updatedItem.approval!.signatureMethod, 'disclaimer');
    expect(updatedItem.approval!.signatureImageBytes, const [1, 2, 3, 4]);
    expect(updatedItem.approval!.approvedMaintainerName, 'Maintainer');
    expect(updatedItem.approval!.approvedMaintainerNumber, 'M-100');
  });

  test('reopenDoorRemedial clears approval metadata and returns items for approval', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(surveyControllerFamilyProvider(InspectionWorkspace.fireDoor).notifier);

    final survey = controller.createSurvey(SurveyType.survey);
    final item = _buildRemedialItem(
      status: RemedialStatus.approved,
      approvedBy: 'Manager Name',
      approvedAt: DateTime(2026, 5, 1),
      managerApprovalPhotos: [
        RemedialPhoto(
          projectId: 'survey-1',
          doorId: 'door-1',
          remedialItemId: 'item-1',
          issueId: 'issue-1',
          type: 'approval',
          fileName: 'approval.jpg',
          mimeType: 'image/jpeg',
          bytes: [9, 9, 9],
        ),
      ],
      approval: Approval(
        projectId: 'survey-1',
        doorId: 'door-1',
        approvedBy: 'Manager Name',
        decision: 'approved',
        signatureMethod: 'disclaimer',
        signatureImageBytes: const [8, 8, 8],
      ),
    );
    final door = Door(
      id: 'door-1',
      number: 1,
      doorIdTag: 'D-001',
      remedialStatus: RemedialStatus.approved,
      remedialItems: [item],
    );
    controller.saveNewDoor(surveyId: survey.id, door: door);

    controller.reopenDoorRemedial(surveyId: survey.id, doorId: door.id);

    final reopenedDoor = controller.getDoorById(surveyId: survey.id, doorId: door.id);
    expect(reopenedDoor, isNotNull);
    expect(reopenedDoor!.remedialStatus, RemedialStatus.forApproval);
    final reopenedItem = reopenedDoor.remedialItems.single;
    expect(reopenedItem.status, RemedialStatus.forApproval);
    expect(reopenedItem.approvedBy, isEmpty);
    expect(reopenedItem.approvedAt, isNull);
    expect(reopenedItem.rejectedBy, isEmpty);
    expect(reopenedItem.rejectedAt, isNull);
    expect(reopenedItem.rejectionNote, isEmpty);
    expect(reopenedItem.managerApprovalPhotos, isEmpty);
    expect(reopenedItem.managerRejectionPhotos, isEmpty);
    expect(reopenedItem.managerRejectionNote, isEmpty);
    expect(reopenedItem.approval, isNull);
  });
}

RemedialItem _buildRemedialItem({
  required RemedialStatus status,
  String approvedBy = '',
  DateTime? approvedAt,
  List<RemedialPhoto> managerApprovalPhotos = const [],
  Approval? approval,
}) {
  return RemedialItem(
    id: 'item-1',
    projectId: 'survey-1',
    doorId: 'door-1',
    issueId: 'issue-1',
    category: 'General',
    title: 'Closer issue',
    severity: 'major',
    originalComment: 'Original issue',
    originalInspectionPhotos: const [],
    recommendedAction: 'Adjust closer',
    status: status,
    approvedBy: approvedBy,
    approvedAt: approvedAt,
    managerApprovalPhotos: managerApprovalPhotos,
    approval: approval,
  );
}