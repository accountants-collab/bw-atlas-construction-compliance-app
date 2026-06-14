import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum SnaggingStatus { open, awaitingVerification, approved, returned }

enum SnagPriority { low, medium, high }

enum SnagProgrammeImpact { yes, no, na }

/// Represents operational responsibility for resolving a snag
enum ResponsibleParty {
  mainContractor,
  subcontractor,
  client,
  unknown,
  other,
}

String responsiblePartyLabel(ResponsibleParty party) {
  switch (party) {
    case ResponsibleParty.mainContractor:
      return 'Main Contractor';
    case ResponsibleParty.subcontractor:
      return 'Subcontractor';
    case ResponsibleParty.client:
      return 'Client';
    case ResponsibleParty.unknown:
      return 'Unknown';
    case ResponsibleParty.other:
      return 'Custom';
  }
}

class SnaggingIssue {
  final String id;
  final int snagNumber;
  final String reference;
  final String location;
  final bool useDrawingPin;
  final String drawingFileName;
  final String drawingMimeType;
  final String drawingBytesBase64;
  final String sharedDrawingId;
  final String sharedPinId;
  final double pinX;
  final double pinY;
  final String assignedToName;
  final DateTime dateTime;
  final SnagPriority priority;
  final SnagProgrammeImpact programmeImpact;
  final List<String> originalPhotoBase64;
  final List<String> photoDescriptions;
  final List<String> completionPhotoBase64;
  final String workerNotes;
  final String assignedToUserId;
  final SnaggingStatus status;
  // Responsibility and company assignment
  final ResponsibleParty responsibleParty;
  final String responsiblePartyCustom;
  final String assignedCompanyId;
  final String assignedCompanyName;

  /// Combined descriptions from all photos, joined by newline.
  String get description =>
      photoDescriptions.where((d) => d.isNotEmpty).join('\n');

  const SnaggingIssue({
    required this.id,
    this.snagNumber = 1,
    this.reference = '',
    this.location = '',
    this.useDrawingPin = false,
    this.drawingFileName = '',
    this.drawingMimeType = '',
    this.drawingBytesBase64 = '',
    this.sharedDrawingId = '',
    this.sharedPinId = '',
    this.pinX = -1,
    this.pinY = -1,
    this.assignedToName = '',
    required this.dateTime,
    this.priority = SnagPriority.medium,
    this.programmeImpact = SnagProgrammeImpact.na,
    this.originalPhotoBase64 = const [],
    this.photoDescriptions = const [],
    this.completionPhotoBase64 = const [],
    this.workerNotes = '',
    this.assignedToUserId = '',
    this.status = SnaggingStatus.open,
    this.responsibleParty = ResponsibleParty.unknown,
    this.responsiblePartyCustom = '',
    this.assignedCompanyId = '',
    this.assignedCompanyName = '',
  });

  factory SnaggingIssue.create({required int snagNumber}) => SnaggingIssue(
      id: _uuid.v4(), snagNumber: snagNumber, dateTime: DateTime.now());

  SnaggingIssue copyWith({
    int? snagNumber,
    String? reference,
    String? location,
    bool? useDrawingPin,
    String? drawingFileName,
    String? drawingMimeType,
    String? drawingBytesBase64,
    String? sharedDrawingId,
    String? sharedPinId,
    double? pinX,
    double? pinY,
    String? assignedToName,
    DateTime? dateTime,
    SnagPriority? priority,
    SnagProgrammeImpact? programmeImpact,
    List<String>? originalPhotoBase64,
    List<String>? photoDescriptions,
    List<String>? completionPhotoBase64,
    String? workerNotes,
    String? assignedToUserId,
    SnaggingStatus? status,
    ResponsibleParty? responsibleParty,
    String? responsiblePartyCustom,
    String? assignedCompanyId,
    String? assignedCompanyName,
  }) {
    return SnaggingIssue(
      id: id,
      snagNumber: snagNumber ?? this.snagNumber,
      reference: reference ?? this.reference,
      location: location ?? this.location,
      useDrawingPin: useDrawingPin ?? this.useDrawingPin,
      drawingFileName: drawingFileName ?? this.drawingFileName,
      drawingMimeType: drawingMimeType ?? this.drawingMimeType,
      drawingBytesBase64: drawingBytesBase64 ?? this.drawingBytesBase64,
      sharedDrawingId: sharedDrawingId ?? this.sharedDrawingId,
      sharedPinId: sharedPinId ?? this.sharedPinId,
      pinX: pinX ?? this.pinX,
      pinY: pinY ?? this.pinY,
      assignedToName: assignedToName ?? this.assignedToName,
      dateTime: dateTime ?? this.dateTime,
      priority: priority ?? this.priority,
      programmeImpact: programmeImpact ?? this.programmeImpact,
      originalPhotoBase64: originalPhotoBase64 ?? this.originalPhotoBase64,
      photoDescriptions: photoDescriptions ?? this.photoDescriptions,
      completionPhotoBase64:
          completionPhotoBase64 ?? this.completionPhotoBase64,
      workerNotes: workerNotes ?? this.workerNotes,
      assignedToUserId: assignedToUserId ?? this.assignedToUserId,
      status: status ?? this.status,
      responsibleParty: responsibleParty ?? this.responsibleParty,
      responsiblePartyCustom:
          responsiblePartyCustom ?? this.responsiblePartyCustom,
      assignedCompanyId: assignedCompanyId ?? this.assignedCompanyId,
      assignedCompanyName: assignedCompanyName ?? this.assignedCompanyName,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'snagNumber': snagNumber,
        'reference': reference,
        'location': location,
        'useDrawingPin': useDrawingPin,
        'drawingFileName': drawingFileName,
        'drawingMimeType': drawingMimeType,
        'drawingBytesBase64': drawingBytesBase64,
        'sharedDrawingId': sharedDrawingId,
        'sharedPinId': sharedPinId,
        'pinX': pinX,
        'pinY': pinY,
        'assignedToName': assignedToName,
        'dateTime': dateTime.toIso8601String(),
        'priority': priority.name,
        'programmeImpact': programmeImpact.name,
        'originalPhotoBase64': originalPhotoBase64,
        'photoDescriptions': photoDescriptions,
        'completionPhotoBase64': completionPhotoBase64,
        'workerNotes': workerNotes,
        'assignedToUserId': assignedToUserId,
        'status': status.name,
        'responsibleParty': responsibleParty.name,
        'responsiblePartyCustom': responsiblePartyCustom,
        'assignedCompanyId': assignedCompanyId,
        'assignedCompanyName': assignedCompanyName,
      };

  factory SnaggingIssue.fromMap(Map<String, dynamic> map) {
    return SnaggingIssue(
      id: map['id'] as String? ?? _uuid.v4(),
      snagNumber: (map['snagNumber'] as num?)?.toInt() ?? 1,
      reference: map['reference'] as String? ?? '',
      location: map['location'] as String? ?? '',
      useDrawingPin: map['useDrawingPin'] as bool? ?? false,
      drawingFileName: map['drawingFileName'] as String? ?? '',
      drawingMimeType: map['drawingMimeType'] as String? ?? '',
      drawingBytesBase64: map['drawingBytesBase64'] as String? ?? '',
      sharedDrawingId: map['sharedDrawingId'] as String? ?? '',
      sharedPinId: map['sharedPinId'] as String? ?? '',
      pinX: (map['pinX'] as num?)?.toDouble() ?? -1,
      pinY: (map['pinY'] as num?)?.toDouble() ?? -1,
      assignedToName: map['assignedToName'] as String? ?? '',
      dateTime:
          DateTime.tryParse(map['dateTime'] as String? ?? '') ?? DateTime.now(),
      priority: SnagPriority.values.firstWhere(
        (e) => e.name == (map['priority'] as String? ?? ''),
        orElse: () => SnagPriority.medium,
      ),
      programmeImpact: SnagProgrammeImpact.values.firstWhere(
        (e) => e.name == (map['programmeImpact'] as String? ?? ''),
        orElse: () => SnagProgrammeImpact.na,
      ),
      originalPhotoBase64: (map['originalPhotoBase64'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      photoDescriptions: (map['photoDescriptions'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      completionPhotoBase64: (map['completionPhotoBase64'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      workerNotes: map['workerNotes'] as String? ?? '',
      assignedToUserId: map['assignedToUserId'] as String? ?? '',
      status: SnaggingStatus.values.firstWhere(
        (e) => e.name == (map['status'] as String? ?? ''),
        orElse: () => SnaggingStatus.open,
      ),
      responsibleParty: ResponsibleParty.values.firstWhere(
        (e) => e.name == (map['responsibleParty'] as String? ?? ''),
        orElse: () => ResponsibleParty.unknown,
      ),
      responsiblePartyCustom: map['responsiblePartyCustom'] as String? ?? '',
      assignedCompanyId: map['assignedCompanyId'] as String? ?? '',
      assignedCompanyName: map['assignedCompanyName'] as String? ?? '',
    );
  }
}

class SnaggingProject {
  final String id;
  final String surveyId;
  final String name;
  final String client;
  final String addressLine1;
  final String addressLine2;
  final String postcode;
  final String city;
  final String clientEmail;
  final String clientPhone;
  final String preparedFor;
  final DateTime date;
  final List<SnaggingIssue> issues;
  final bool isArchived;
  final DateTime? archivedAt;
  final String archivedBy;
  final DateTime? restoredAt;
  final String restoredBy;

  const SnaggingProject({
    required this.id,
    this.surveyId = '',
    this.name = '',
    this.client = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.postcode = '',
    this.city = '',
    this.clientEmail = '',
    this.clientPhone = '',
    this.preparedFor = '',
    required this.date,
    this.issues = const [],
    this.isArchived = false,
    this.archivedAt,
    this.archivedBy = '',
    this.restoredAt,
    this.restoredBy = '',
  });

  factory SnaggingProject.create() =>
      SnaggingProject(id: _uuid.v4(), date: DateTime.now());

  SnaggingProject copyWith({
    String? surveyId,
    String? name,
    String? client,
    String? addressLine1,
    String? addressLine2,
    String? postcode,
    String? city,
    String? clientEmail,
    String? clientPhone,
    String? preparedFor,
    DateTime? date,
    List<SnaggingIssue>? issues,
    bool? isArchived,
    DateTime? archivedAt,
    String? archivedBy,
    DateTime? restoredAt,
    String? restoredBy,
  }) {
    return SnaggingProject(
      id: id,
      surveyId: surveyId ?? this.surveyId,
      name: name ?? this.name,
      client: client ?? this.client,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      postcode: postcode ?? this.postcode,
      city: city ?? this.city,
      clientEmail: clientEmail ?? this.clientEmail,
      clientPhone: clientPhone ?? this.clientPhone,
      preparedFor: preparedFor ?? this.preparedFor,
      date: date ?? this.date,
      issues: issues ?? this.issues,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      restoredAt: restoredAt ?? this.restoredAt,
      restoredBy: restoredBy ?? this.restoredBy,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'surveyId': surveyId,
        'name': name,
        'client': client,
        'addressLine1': addressLine1,
        'addressLine2': addressLine2,
        'postcode': postcode,
        'city': city,
        'clientEmail': clientEmail,
        'clientPhone': clientPhone,
        'preparedFor': preparedFor,
        'date': date.toIso8601String(),
        'issues': issues.map((e) => e.toMap()).toList(),
        'isArchived': isArchived,
        'archivedAt': archivedAt?.toIso8601String(),
        'archivedBy': archivedBy,
        'restoredAt': restoredAt?.toIso8601String(),
        'restoredBy': restoredBy,
      };

  factory SnaggingProject.fromMap(Map<String, dynamic> map) {
    return SnaggingProject(
      id: map['id'] as String? ?? _uuid.v4(),
      surveyId: map['surveyId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      client: map['client'] as String? ?? '',
      addressLine1: map['addressLine1'] as String? ?? '',
      addressLine2: map['addressLine2'] as String? ?? '',
      postcode: map['postcode'] as String? ?? '',
      city: map['city'] as String? ?? '',
      clientEmail: map['clientEmail'] as String? ?? '',
      clientPhone: map['clientPhone'] as String? ?? '',
      preparedFor: map['preparedFor'] as String? ?? '',
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      issues: (map['issues'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => SnaggingIssue.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      isArchived: map['isArchived'] as bool? ?? false,
      archivedAt: DateTime.tryParse(map['archivedAt'] as String? ?? ''),
      archivedBy: map['archivedBy'] as String? ?? '',
      restoredAt: DateTime.tryParse(map['restoredAt'] as String? ?? ''),
      restoredBy: map['restoredBy'] as String? ?? '',
    );
  }
}
