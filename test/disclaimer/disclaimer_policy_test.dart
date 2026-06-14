import 'package:fd_app/features/disclaimer/domain/disclaimer_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('disclaimerAcceptanceScopeForModule', () {
    test('maps fire-door family to fire-door', () {
      expect(disclaimerAcceptanceScopeForModule('fire-door'), 'fire-door');
      expect(
          disclaimerAcceptanceScopeForModule('pre-installation'), 'fire-door');
      expect(disclaimerAcceptanceScopeForModule('installation'), 'fire-door');
      expect(disclaimerAcceptanceScopeForModule('handover'), 'fire-door');
    });

    test('keeps fire-stopping and snagging separate', () {
      expect(
          disclaimerAcceptanceScopeForModule('fire-stopping'), 'fire-stopping');
      expect(disclaimerAcceptanceScopeForModule('snagging'), 'snagging');
    });
  });

  group('isDisclaimerAcceptanceCurrent', () {
    DisclaimerAcceptanceRecord buildRecord({
      required String moduleType,
      required String userId,
      required DateTime acceptedAt,
      String version = kDisclaimerVersion,
      DateTime? expiresAt,
    }) {
      return DisclaimerAcceptanceRecord(
        acceptanceId: 'a1',
        companyId: 'c1',
        projectId: 'p1',
        reportId: 'r1',
        moduleType: moduleType,
        userId: userId,
        userEmail: 'u@example.com',
        userRole: 'manager',
        inspectorName: 'User',
        disclaimerAccepted: true,
        disclaimerAcceptedAt: acceptedAt,
        disclaimerVersion: version,
        expiresAt: expiresAt,
      );
    }

    test('accepts matching module family and user', () {
      final acceptedAt = DateTime(2026, 1, 1);
      final record = buildRecord(
        moduleType: 'fire-door',
        userId: 'u1',
        acceptedAt: acceptedAt,
      );

      expect(
        isDisclaimerAcceptanceCurrent(
          record: record,
          moduleType: 'pre-installation',
          userId: 'u1',
          now: DateTime(2026, 3, 1),
        ),
        isTrue,
      );
    });

    test('rejects expired acceptance', () {
      final acceptedAt = DateTime(2026, 1, 1);
      final record = buildRecord(
        moduleType: 'fire-door',
        userId: 'u1',
        acceptedAt: acceptedAt,
      );

      expect(
        isDisclaimerAcceptanceCurrent(
          record: record,
          moduleType: 'fire-door',
          userId: 'u1',
          now: DateTime(2026, 8, 2),
        ),
        isFalse,
      );
    });

    test('rejects outdated disclaimer version', () {
      final record = buildRecord(
        moduleType: 'snagging',
        userId: 'u1',
        acceptedAt: DateTime(2026, 1, 1),
        version: '2025.01.01',
      );

      expect(
        isDisclaimerAcceptanceCurrent(
          record: record,
          moduleType: 'snagging',
          userId: 'u1',
          now: DateTime(2026, 2, 1),
        ),
        isFalse,
      );
    });
  });
}
