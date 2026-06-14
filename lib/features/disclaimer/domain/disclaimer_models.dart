import 'package:cloud_firestore/cloud_firestore.dart';

const String kDisclaimerVersion = '2026.04.21';
const int kDisclaimerRenewalMonths = 6;
const int kDisclaimerNearExpiryDays = 30;

String disclaimerAcceptanceScopeForModule(String moduleType) {
  switch (moduleType.trim().toLowerCase()) {
    case 'pre-installation':
    case 'installation':
    case 'handover':
    case 'fire-door':
      return 'fire-door';
    case 'fire-stopping':
      return 'fire-stopping';
    case 'snagging':
      return 'snagging';
    default:
      return 'fire-door';
  }
}

DateTime disclaimerExpiresAtFrom(DateTime acceptedAt) {
  return _addMonths(acceptedAt, kDisclaimerRenewalMonths);
}

bool isDisclaimerAcceptanceCurrent({
  required DisclaimerAcceptanceRecord? record,
  required String moduleType,
  required String userId,
  DateTime? now,
  String expectedVersion = kDisclaimerVersion,
}) {
  if (record == null) return false;
  if (!record.disclaimerAccepted) return false;
  if (record.userId.trim() != userId.trim()) return false;

  final expectedScope = disclaimerAcceptanceScopeForModule(moduleType);
  final recordScope = disclaimerAcceptanceScopeForModule(record.moduleType);
  if (recordScope != expectedScope) return false;

  if (record.disclaimerVersion.trim() != expectedVersion.trim()) {
    return false;
  }

  final acceptedAt = record.disclaimerAcceptedAt ?? record.createdAt;
  final expiresAt = record.expiresAt ?? disclaimerExpiresAtFrom(acceptedAt);
  final checkAt = now ?? DateTime.now();
  return !checkAt.isAfter(expiresAt);
}

int? disclaimerDaysUntilExpiry({
  required DisclaimerAcceptanceRecord? record,
  required String moduleType,
  required String userId,
  DateTime? now,
}) {
  if (!isDisclaimerAcceptanceCurrent(
    record: record,
    moduleType: moduleType,
    userId: userId,
    now: now,
  )) {
    return null;
  }
  if (record == null) return null;

  final acceptedAt = record.disclaimerAcceptedAt ?? record.createdAt;
  final expiresAt = record.expiresAt ?? disclaimerExpiresAtFrom(acceptedAt);
  final checkAt = now ?? DateTime.now();
  final normalizedToday = DateTime(checkAt.year, checkAt.month, checkAt.day);
  final normalizedExpiry =
      DateTime(expiresAt.year, expiresAt.month, expiresAt.day);
  return normalizedExpiry.difference(normalizedToday).inDays;
}

DateTime _addMonths(DateTime date, int months) {
  final monthCount = (date.year * 12) + (date.month - 1) + months;
  final year = monthCount ~/ 12;
  final month = (monthCount % 12) + 1;
  final day = date.day <= _daysInMonth(year, month)
      ? date.day
      : _daysInMonth(year, month);
  return DateTime(
    year,
    month,
    day,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
    date.microsecond,
  );
}

int _daysInMonth(int year, int month) {
  if (month == 12) {
    final firstOfNextYear = DateTime(year + 1, 1, 1);
    final lastOfMonth = firstOfNextYear.subtract(const Duration(days: 1));
    return lastOfMonth.day;
  }
  final firstOfNextMonth = DateTime(year, month + 1, 1);
  final lastOfMonth = firstOfNextMonth.subtract(const Duration(days: 1));
  return lastOfMonth.day;
}

String disclaimerTitleForModule(String moduleType) {
  switch (moduleType.trim()) {
    case 'pre-installation':
      return 'Pre-Installation Declaration';
    case 'fire-stopping':
      return 'Fire Stopping Inspection Declaration';
    case 'snagging':
      return 'Snagging Inspection Declaration';
    case 'fire-door':
    default:
      return 'Fire Door Inspection Declaration';
  }
}

String disclaimerModuleLabel(String moduleType) {
  switch (moduleType.trim()) {
    case 'pre-installation':
      return 'Pre-Installation';
    case 'fire-stopping':
      return 'Fire Stopping';
    case 'snagging':
      return 'Snagging';
    case 'fire-door':
    default:
      return 'Fire Door';
  }
}

const String kDisclaimerAcceptanceCheckboxLabel =
    'I confirm that I have read, understood, and accept this inspection disclaimer.';

String disclaimerTextForModule(String moduleType) {
  switch (moduleType.trim()) {
    case 'pre-installation':
      return '''PRE-INSTALLATION DECLARATION

I confirm that all measurements, specifications, and site conditions recorded in this pre-installation survey have been assessed accurately to the best of my professional ability.

I understand that this information may be used for the manufacture, supply, or installation of fire-rated doorsets and associated components.

I confirm that any limitations, assumptions, or missing information have been clearly noted within this report.

Inspector signature confirms responsibility for the accuracy of this pre-installation data.''';
    case 'fire-stopping':
      return '''FIRE STOPPING INSPECTION DECLARATION

I confirm that this fire stopping inspection report reflects the observed condition of installed fire stopping systems at the time of inspection.

All findings have been recorded based on visible evidence and accessible areas only.

I confirm that any concealed, inaccessible, or unverified areas have been noted where applicable.

This report is completed to the best of my professional knowledge and competence.''';
    case 'snagging':
      return '''SNAGGING INSPECTION DECLARATION

I confirm that the items recorded in this snagging report reflect the visible condition and outstanding issues identified during inspection.

All observations are based on site conditions at the time of inspection.

I confirm that this report has been completed accurately and without omission to the best of my professional ability.

This report is intended to support rectification and completion of works.''';
    case 'fire-door':
    default:
      return '''FIRE DOOR INSPECTION DECLARATION

I confirm that this fire door inspection report reflects the observed condition of the inspected doors at the time of inspection.

All findings have been recorded based on visible evidence and accessible areas only.

I confirm that any concealed, inaccessible, or unverified areas have been noted where applicable.

This report is completed to the best of my professional knowledge and competence.''';
  }
}

class DisclaimerAcceptanceRecord {
  final String acceptanceId;
  final String companyId;
  final String projectId;
  final String reportId;
  final String moduleType;
  final String projectName;
  final String projectNumber;
  final String reportReference;
  final String userId;
  final String userEmail;
  final String userRole;
  final String inspectorName;
  final List<int> signatureImageBytes;
  final String signatureFileId;
  final String signatureStoragePath;
  final String signatureDownloadUrl;
  final bool disclaimerAccepted;
  final DateTime? disclaimerAcceptedAt;
  final String disclaimerVersion;
  final String acceptedTextSnapshot;
  final DateTime? expiresAt;
  final String pdfFileId;
  final String pdfStoragePath;
  final String pdfDownloadUrl;
  final String acceptanceStatus;
  final DateTime createdAt;

  DisclaimerAcceptanceRecord({
    required this.acceptanceId,
    required this.companyId,
    required this.projectId,
    required this.reportId,
    required this.moduleType,
    this.projectName = '',
    this.projectNumber = '',
    this.reportReference = '',
    required this.userId,
    required this.userEmail,
    required this.userRole,
    required this.inspectorName,
    this.signatureImageBytes = const [],
    this.signatureFileId = '',
    this.signatureStoragePath = '',
    this.signatureDownloadUrl = '',
    this.disclaimerAccepted = false,
    this.disclaimerAcceptedAt,
    this.disclaimerVersion = kDisclaimerVersion,
    this.acceptedTextSnapshot = '',
    this.expiresAt,
    this.pdfFileId = '',
    this.pdfStoragePath = '',
    this.pdfDownloadUrl = '',
    this.acceptanceStatus = 'Accepted',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? disclaimerAcceptedAt ?? DateTime.now();

  bool get hasPdf => pdfDownloadUrl.trim().isNotEmpty;
  bool get hasSignature =>
      signatureImageBytes.isNotEmpty || signatureDownloadUrl.trim().isNotEmpty;

  DisclaimerAcceptanceRecord copyWith({
    String? acceptanceId,
    String? companyId,
    String? projectId,
    String? reportId,
    String? moduleType,
    String? projectName,
    String? projectNumber,
    String? reportReference,
    String? userId,
    String? userEmail,
    String? userRole,
    String? inspectorName,
    List<int>? signatureImageBytes,
    String? signatureFileId,
    String? signatureStoragePath,
    String? signatureDownloadUrl,
    bool? disclaimerAccepted,
    DateTime? disclaimerAcceptedAt,
    String? disclaimerVersion,
    String? acceptedTextSnapshot,
    DateTime? expiresAt,
    String? pdfFileId,
    String? pdfStoragePath,
    String? pdfDownloadUrl,
    String? acceptanceStatus,
    DateTime? createdAt,
  }) {
    return DisclaimerAcceptanceRecord(
      acceptanceId: acceptanceId ?? this.acceptanceId,
      companyId: companyId ?? this.companyId,
      projectId: projectId ?? this.projectId,
      reportId: reportId ?? this.reportId,
      moduleType: moduleType ?? this.moduleType,
      projectName: projectName ?? this.projectName,
      projectNumber: projectNumber ?? this.projectNumber,
      reportReference: reportReference ?? this.reportReference,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
      userRole: userRole ?? this.userRole,
      inspectorName: inspectorName ?? this.inspectorName,
      signatureImageBytes: signatureImageBytes ?? this.signatureImageBytes,
      signatureFileId: signatureFileId ?? this.signatureFileId,
      signatureStoragePath: signatureStoragePath ?? this.signatureStoragePath,
      signatureDownloadUrl: signatureDownloadUrl ?? this.signatureDownloadUrl,
      disclaimerAccepted: disclaimerAccepted ?? this.disclaimerAccepted,
      disclaimerAcceptedAt: disclaimerAcceptedAt ?? this.disclaimerAcceptedAt,
      disclaimerVersion: disclaimerVersion ?? this.disclaimerVersion,
      acceptedTextSnapshot: acceptedTextSnapshot ?? this.acceptedTextSnapshot,
      expiresAt: expiresAt ?? this.expiresAt,
      pdfFileId: pdfFileId ?? this.pdfFileId,
      pdfStoragePath: pdfStoragePath ?? this.pdfStoragePath,
      pdfDownloadUrl: pdfDownloadUrl ?? this.pdfDownloadUrl,
      acceptanceStatus: acceptanceStatus ?? this.acceptanceStatus,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap({bool includeSignatureBytes = true}) {
    return {
      'acceptanceId': acceptanceId,
      'companyId': companyId,
      'projectId': projectId,
      'reportId': reportId,
      'moduleType': moduleType,
      'projectName': projectName,
      'projectNumber': projectNumber,
      'reportReference': reportReference,
      'userId': userId,
      'userEmail': userEmail,
      'userRole': userRole,
      'inspectorName': inspectorName,
      if (includeSignatureBytes) 'signatureImageBytes': signatureImageBytes,
      'signatureFileId': signatureFileId,
      'signatureStoragePath': signatureStoragePath,
      'signatureDownloadUrl': signatureDownloadUrl,
      'disclaimerAccepted': disclaimerAccepted,
      'disclaimerAcceptedAt': disclaimerAcceptedAt == null
          ? null
          : Timestamp.fromDate(disclaimerAcceptedAt!),
      'disclaimerVersion': disclaimerVersion,
      'acceptedTextSnapshot': acceptedTextSnapshot,
      'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
      'pdfFileId': pdfFileId,
      'pdfStoragePath': pdfStoragePath,
      'pdfDownloadUrl': pdfDownloadUrl,
      'acceptanceStatus': acceptanceStatus,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory DisclaimerAcceptanceRecord.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    return DisclaimerAcceptanceRecord(
      acceptanceId: map['acceptanceId'] as String? ?? '',
      companyId: map['companyId'] as String? ?? '',
      projectId: map['projectId'] as String? ?? '',
      reportId: map['reportId'] as String? ?? '',
      moduleType: map['moduleType'] as String? ?? 'fire-door',
      projectName: map['projectName'] as String? ?? '',
      projectNumber: map['projectNumber'] as String? ?? '',
      reportReference: map['reportReference'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      userEmail: map['userEmail'] as String? ?? '',
      userRole: map['userRole'] as String? ?? '',
      inspectorName: map['inspectorName'] as String? ?? '',
      signatureImageBytes: (map['signatureImageBytes'] as List? ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      signatureFileId: map['signatureFileId'] as String? ?? '',
      signatureStoragePath: map['signatureStoragePath'] as String? ?? '',
      signatureDownloadUrl: map['signatureDownloadUrl'] as String? ?? '',
      disclaimerAccepted: map['disclaimerAccepted'] as bool? ?? false,
      disclaimerAcceptedAt: parseDate(map['disclaimerAcceptedAt']),
      disclaimerVersion:
          map['disclaimerVersion'] as String? ?? kDisclaimerVersion,
      acceptedTextSnapshot: map['acceptedTextSnapshot'] as String? ?? '',
      expiresAt: parseDate(map['expiresAt']),
      pdfFileId: map['pdfFileId'] as String? ?? '',
      pdfStoragePath: map['pdfStoragePath'] as String? ?? '',
      pdfDownloadUrl: map['pdfDownloadUrl'] as String? ?? '',
      acceptanceStatus: map['acceptanceStatus'] as String? ?? 'Accepted',
      createdAt: parseDate(map['createdAt']),
    );
  }
}
