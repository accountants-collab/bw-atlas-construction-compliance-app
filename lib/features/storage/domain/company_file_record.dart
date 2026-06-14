import 'package:cloud_firestore/cloud_firestore.dart';

enum CompanyFileKind { image, video, document, drawing, other }

class CompanyFileRecord {
  final String fileId;
  final String companyId;
  final String entityType;
  final String entityId;
  final CompanyFileKind kind;
  final String originalName;
  final String storagePath;
  final String downloadUrl;
  final String mimeType;
  final int sizeBytes;
  final String createdByUid;
  final DateTime createdAt;
  final List<String> tags;

  const CompanyFileRecord({
    required this.fileId,
    required this.companyId,
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.originalName,
    required this.storagePath,
    required this.downloadUrl,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdByUid,
    required this.createdAt,
    required this.tags,
  });

  Map<String, dynamic> toMap() {
    return {
      'fileId': fileId,
      'companyId': companyId,
      'entityType': entityType,
      'entityId': entityId,
      'kind': kind.name,
      'originalName': originalName,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'createdByUid': createdByUid,
      'createdAt': Timestamp.fromDate(createdAt),
      'tags': tags,
    };
  }

  factory CompanyFileRecord.fromMap(Map<String, dynamic> map) {
    final createdAtRaw = map['createdAt'];
    final createdAt = createdAtRaw is Timestamp
        ? createdAtRaw.toDate()
        : DateTime.tryParse(createdAtRaw as String? ?? '') ?? DateTime.now();

    return CompanyFileRecord(
      fileId: map['fileId'] as String? ?? '',
      companyId: map['companyId'] as String? ?? '',
      entityType: map['entityType'] as String? ?? '',
      entityId: map['entityId'] as String? ?? '',
      kind: CompanyFileKind.values.firstWhere(
        (k) => k.name == (map['kind'] as String? ?? ''),
        orElse: () => CompanyFileKind.other,
      ),
      originalName: map['originalName'] as String? ?? '',
      storagePath: map['storagePath'] as String? ?? '',
      downloadUrl: map['downloadUrl'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      createdByUid: map['createdByUid'] as String? ?? '',
      createdAt: createdAt,
      tags: (map['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
