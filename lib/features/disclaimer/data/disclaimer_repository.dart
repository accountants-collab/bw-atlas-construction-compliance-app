import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../storage/data/company_file_repository.dart';
import '../../storage/domain/company_file_record.dart';
import '../domain/disclaimer_models.dart';
import '../pdf/disclaimer_pdf_builder.dart';

class DisclaimerRepository {
  DisclaimerRepository({
    FirebaseFirestore? firestore,
    required CompanyFileRepository fileRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _fileRepository = fileRepository;

  final FirebaseFirestore _firestore;
  final CompanyFileRepository _fileRepository;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> _collection(String companyId) {
    return _firestore
        .collection('companies')
        .doc(companyId)
        .collection('disclaimerAcceptances');
  }

  Future<DisclaimerAcceptanceRecord> _hydrateSignatureBytes(
      DisclaimerAcceptanceRecord record) async {
    if (record.signatureImageBytes.isNotEmpty) return record;
    final url = record.signatureDownloadUrl.trim();
    if (url.isEmpty) return record;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.isNotEmpty) {
        return record.copyWith(signatureImageBytes: response.bodyBytes);
      }
    } catch (e) {
      debugPrint('[DisclaimerRepo] Could not hydrate signature bytes: $e');
    }
    return record;
  }

  Future<DisclaimerAcceptanceRecord?> getById({
    required String companyId,
    required String acceptanceId,
  }) async {
    if (companyId.trim().isEmpty || acceptanceId.trim().isEmpty) return null;
    final doc = await _collection(companyId).doc(acceptanceId).get();
    final data = doc.data();
    if (data == null) return null;
    return DisclaimerAcceptanceRecord.fromMap(data);
  }

  Future<DisclaimerAcceptanceRecord?> findUserReportRecord({
    required String companyId,
    required String reportId,
    required String moduleType,
    required String userId,
  }) async {
    debugPrint(
        '[DisclaimerRepo] findUserReportRecord query: companyId=$companyId, reportId=$reportId, moduleType=$moduleType, userId=$userId');
    if (companyId.trim().isEmpty ||
        reportId.trim().isEmpty ||
        userId.trim().isEmpty) {
      debugPrint('[DisclaimerRepo] Early return: empty parameter');
      return null;
    }
    try {
      final snapshot = await _collection(companyId)
          .where('reportId', isEqualTo: reportId)
          .where('moduleType', isEqualTo: moduleType)
          .where('userId', isEqualTo: userId)
          .limit(5)
          .get();
      debugPrint(
          '[DisclaimerRepo] Query returned ${snapshot.docs.length} docs');
      if (snapshot.docs.isEmpty) {
        debugPrint('[DisclaimerRepo] No docs found');
        return null;
      }
      final records = List<DisclaimerAcceptanceRecord>.from(
        snapshot.docs.map((d) => DisclaimerAcceptanceRecord.fromMap(d.data())),
      );
      try {
        if (records.length > 1) {
          records.sort((a, b) {
            final aValue = a.disclaimerAcceptedAt ?? a.createdAt;
            final bValue = b.disclaimerAcceptedAt ?? b.createdAt;
            return bValue.compareTo(aValue);
          });
        }
      } catch (e) {
        debugPrint('Sort error (findUserReportRecord): $e');
      }
      final hydrated = await _hydrateSignatureBytes(records.first);
      debugPrint(
          '[DisclaimerRepo] Returning first record (signature bytes: ${hydrated.signatureImageBytes.length})');
      return hydrated;
    } catch (e) {
      debugPrint('[DisclaimerRepo] Firestore query error: $e');
      return null;
    }
  }

  Future<DisclaimerAcceptanceRecord?> findUserModuleRecord({
    required String companyId,
    required String moduleType,
    required String userId,
    bool onlyCurrent = true,
    DateTime? now,
  }) async {
    final normalizedUserId = userId.trim();
    final moduleScope = disclaimerAcceptanceScopeForModule(moduleType);
    debugPrint(
      '[DisclaimerRepo] findUserModuleRecord query: companyId=$companyId, moduleType=$moduleType, moduleScope=$moduleScope, userId=$normalizedUserId, onlyCurrent=$onlyCurrent',
    );

    if (companyId.trim().isEmpty || normalizedUserId.isEmpty) {
      debugPrint('[DisclaimerRepo] Early return: empty parameter');
      return null;
    }

    try {
      final snapshot = await _collection(companyId)
          .where('userId', isEqualTo: normalizedUserId)
          .limit(200)
          .get();
      debugPrint(
        '[DisclaimerRepo] Module query returned ${snapshot.docs.length} docs',
      );
      if (snapshot.docs.isEmpty) return null;

      final matching = snapshot.docs
          .map((d) => DisclaimerAcceptanceRecord.fromMap(d.data()))
          .where(
            (record) =>
                disclaimerAcceptanceScopeForModule(record.moduleType) ==
                moduleScope,
          )
          .toList();

      if (matching.isEmpty) {
        debugPrint('[DisclaimerRepo] No module-matching records found');
        return null;
      }

      matching.sort((a, b) {
        final aValue = a.disclaimerAcceptedAt ?? a.createdAt;
        final bValue = b.disclaimerAcceptedAt ?? b.createdAt;
        return bValue.compareTo(aValue);
      });

      final eligible = onlyCurrent
          ? matching
              .where(
                (record) => isDisclaimerAcceptanceCurrent(
                  record: record,
                  moduleType: moduleScope,
                  userId: normalizedUserId,
                  now: now,
                ),
              )
              .toList()
          : matching;

      if (eligible.isEmpty) {
        debugPrint('[DisclaimerRepo] No current module records found');
        return null;
      }

      return _hydrateSignatureBytes(eligible.first);
    } catch (e) {
      debugPrint('[DisclaimerRepo] Module query error: $e');
      return null;
    }
  }

  Stream<List<DisclaimerAcceptanceRecord>> watchCompanyRecords({
    required String companyId,
  }) {
    if (companyId.trim().isEmpty) return const Stream.empty();
    return _collection(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((d) => DisclaimerAcceptanceRecord.fromMap(d.data()))
            .toList());
  }

  Stream<List<DisclaimerAcceptanceRecord>> watchReportRecords({
    required String companyId,
    required String reportId,
  }) {
    return watchCompanyRecords(companyId: companyId).map(
      (records) =>
          records.where((record) => record.reportId == reportId).toList(),
    );
  }

  Future<DisclaimerAcceptanceRecord> createAcceptance({
    required String companyId,
    required String projectId,
    required String reportId,
    required String moduleType,
    required String projectName,
    required String projectNumber,
    required String reportReference,
    required String userId,
    required String userEmail,
    required String userRole,
    required String inspectorName,
    required List<int> signatureImageBytes,
    required String companyName,
    required String companyAddress,
    required String companyEmail,
    required String companyPhone,
    required List<int> companyLogoBytes,
  }) async {
    final acceptedAt = DateTime.now();
    final acceptanceId = _uuid.v4();
    final moduleScope = disclaimerAcceptanceScopeForModule(moduleType);
    final textSnapshot = disclaimerTextForModule(moduleType);
    final expiresAt = disclaimerExpiresAtFrom(acceptedAt);

    debugPrint(
      '[DisclaimerRepo] createAcceptance start: companyId=$companyId, reportId=$reportId, moduleType=$moduleType, userId=$userId, acceptanceId=$acceptanceId',
    );

    CompanyFileRecord? signatureRecord;
    if (signatureImageBytes.isNotEmpty) {
      try {
        signatureRecord = await _fileRepository.uploadBytes(
          companyId: companyId,
          entityType: 'disclaimer-signature',
          entityId: acceptanceId,
          createdByUid: userId,
          fileName: 'disclaimer_signature_$acceptanceId.png',
          bytes: Uint8List.fromList(signatureImageBytes),
          mimeType: 'image/png',
          kind: CompanyFileKind.image,
          tags: [moduleScope, reportId, 'disclaimer-signature'],
        );
        debugPrint(
            '[DisclaimerRepo] Signature upload ok: fileId=${signatureRecord.fileId}');
      } catch (e) {
        debugPrint('[DisclaimerRepo] Signature upload failed: $e');
        rethrow;
      }
    }

    var record = DisclaimerAcceptanceRecord(
      acceptanceId: acceptanceId,
      companyId: companyId,
      projectId: projectId,
      reportId: reportId,
      moduleType: moduleScope,
      projectName: projectName,
      projectNumber: projectNumber,
      reportReference: reportReference,
      userId: userId,
      userEmail: userEmail,
      userRole: userRole,
      inspectorName: inspectorName,
      signatureImageBytes: signatureImageBytes,
      signatureFileId: signatureRecord?.fileId ?? '',
      signatureStoragePath: signatureRecord?.storagePath ?? '',
      signatureDownloadUrl: signatureRecord?.downloadUrl ?? '',
      disclaimerAccepted: true,
      disclaimerAcceptedAt: acceptedAt,
      disclaimerVersion: kDisclaimerVersion,
      acceptedTextSnapshot: textSnapshot,
      expiresAt: expiresAt,
      acceptanceStatus: 'Accepted',
      createdAt: acceptedAt,
    );

    late final Uint8List pdfBytes;
    try {
      pdfBytes = await DisclaimerPdfBuilder.build(
        record: record,
        companyName: companyName,
        companyAddress: companyAddress,
        companyEmail: companyEmail,
        companyPhone: companyPhone,
        logoBytes: companyLogoBytes,
      );
      debugPrint('[DisclaimerRepo] PDF build ok: bytes=${pdfBytes.length}');
    } catch (e) {
      debugPrint('[DisclaimerRepo] PDF build failed: $e');
      rethrow;
    }

    late final CompanyFileRecord pdfRecord;
    try {
      pdfRecord = await _fileRepository.uploadBytes(
        companyId: companyId,
        entityType: 'disclaimer-acceptance',
        entityId: acceptanceId,
        createdByUid: userId,
        fileName: 'disclaimer_record_$acceptanceId.pdf',
        bytes: pdfBytes,
        mimeType: 'application/pdf',
        kind: CompanyFileKind.document,
        tags: [moduleScope, reportId, 'disclaimer-pdf'],
      );
      debugPrint('[DisclaimerRepo] PDF upload ok: fileId=${pdfRecord.fileId}');
    } catch (e) {
      debugPrint('[DisclaimerRepo] PDF upload failed: $e');
      rethrow;
    }

    record = record.copyWith(
      pdfFileId: pdfRecord.fileId,
      pdfStoragePath: pdfRecord.storagePath,
      pdfDownloadUrl: pdfRecord.downloadUrl,
    );

    try {
      final payload = record.toMap(includeSignatureBytes: false);
      debugPrint(
          '[DisclaimerRepo] Writing disclaimer record with fields: ${payload.keys.toList()}');
      await _collection(companyId).doc(acceptanceId).set(payload);
      debugPrint(
          '[DisclaimerRepo] Disclaimer record write ok: acceptanceId=$acceptanceId');
    } catch (e) {
      debugPrint('[DisclaimerRepo] Disclaimer record write failed: $e');
      rethrow;
    }

    return record;
  }
}
