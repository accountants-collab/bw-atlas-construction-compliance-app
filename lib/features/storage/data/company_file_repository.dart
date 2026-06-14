import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../domain/company_file_record.dart';

class CompanyFileRepository {
  CompanyFileRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> _filesCollection(String companyId) {
    return _firestore.collection('companies').doc(companyId).collection('files');
  }

  String _sanitizeFileName(String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) return 'file';
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _storagePath({
    required String companyId,
    required String entityType,
    required String entityId,
    required String fileId,
    required String fileName,
  }) {
    final safeEntityType = entityType.trim().isEmpty ? 'misc' : entityType.trim();
    final safeEntityId = entityId.trim().isEmpty ? 'general' : entityId.trim();
    final safeName = _sanitizeFileName(fileName);
    return 'companies/$companyId/uploads/$safeEntityType/$safeEntityId/${fileId}_$safeName';
  }

  Future<CompanyFileRecord> uploadBytes({
    required String companyId,
    required String entityType,
    required String entityId,
    required String createdByUid,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    required CompanyFileKind kind,
    List<String> tags = const [],
  }) async {
    final fileId = _uuid.v4();
    final path = _storagePath(
      companyId: companyId,
      entityType: entityType,
      entityId: entityId,
      fileId: fileId,
      fileName: fileName,
    );

    final storageRef = _storage.ref(path);
    await storageRef.putData(
      bytes,
      SettableMetadata(
        contentType: mimeType,
        customMetadata: {
          'companyId': companyId,
          'entityType': entityType,
          'entityId': entityId,
          'createdByUid': createdByUid,
          'kind': kind.name,
        },
      ),
    );

    final url = await storageRef.getDownloadURL();
    final createdAt = DateTime.now();
    final record = CompanyFileRecord(
      fileId: fileId,
      companyId: companyId,
      entityType: entityType,
      entityId: entityId,
      kind: kind,
      originalName: fileName,
      storagePath: path,
      downloadUrl: url,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      createdByUid: createdByUid,
      createdAt: createdAt,
      tags: tags,
    );

    await _filesCollection(companyId).doc(fileId).set({
      ...record.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return record;
  }

  Future<List<CompanyFileRecord>> listEntityFiles({
    required String companyId,
    required String entityType,
    required String entityId,
    int limit = 200,
  }) async {
    final snapshot = await _filesCollection(companyId)
        .where('entityType', isEqualTo: entityType)
        .where('entityId', isEqualTo: entityId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((d) {
          final map = d.data();
          final withId = {
            ...map,
            'fileId': (map['fileId'] as String?)?.trim().isNotEmpty == true ? map['fileId'] : d.id,
          };
          return CompanyFileRecord.fromMap(withId);
        })
        .toList();
  }

  Stream<List<CompanyFileRecord>> watchEntityFiles({
    required String companyId,
    required String entityType,
    required String entityId,
    int limit = 200,
  }) {
    return _filesCollection(companyId)
        .where('entityType', isEqualTo: entityType)
        .where('entityId', isEqualTo: entityId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((d) {
                final map = d.data();
                final withId = {
                  ...map,
                  'fileId': (map['fileId'] as String?)?.trim().isNotEmpty == true ? map['fileId'] : d.id,
                };
                return CompanyFileRecord.fromMap(withId);
              })
              .toList(),
        );
  }

  Future<void> deleteFile({
    required String companyId,
    required String fileId,
  }) async {
    final doc = await _filesCollection(companyId).doc(fileId).get();
    final data = doc.data();
    if (data == null) return;

    final path = data['storagePath'] as String?;
    if (path != null && path.trim().isNotEmpty) {
      try {
        await _storage.ref(path).delete();
      } catch (_) {
        // Deleting metadata is still useful even if object is already gone.
      }
    }

    await _filesCollection(companyId).doc(fileId).delete();
  }
}
