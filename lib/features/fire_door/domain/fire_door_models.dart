import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum FireDoorIssueSeverity { advisory, fail, critical }

enum FireDoorResult { notInspected, pass, advisory, fail }

class FireDoorIssue {
  final String id;
  final String title;
  final String comment;
  final FireDoorIssueSeverity severity;

  const FireDoorIssue({
    required this.id,
    this.title = '',
    this.comment = '',
    this.severity = FireDoorIssueSeverity.fail,
  });

  factory FireDoorIssue.create() => FireDoorIssue(id: _uuid.v4());

  FireDoorIssue copyWith({
    String? title,
    String? comment,
    FireDoorIssueSeverity? severity,
  }) {
    return FireDoorIssue(
      id: id,
      title: title ?? this.title,
      comment: comment ?? this.comment,
      severity: severity ?? this.severity,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'comment': comment,
        'severity': severity.name,
      };

  factory FireDoorIssue.fromMap(Map<String, dynamic> map) {
    return FireDoorIssue(
      id: map['id'] as String? ?? _uuid.v4(),
      title: map['title'] as String? ?? '',
      comment: map['comment'] as String? ?? '',
      severity: FireDoorIssueSeverity.values.firstWhere(
        (e) => e.name == (map['severity'] as String? ?? ''),
        orElse: () => FireDoorIssueSeverity.fail,
      ),
    );
  }
}

class FireDoorItem {
  final String id;
  final String doorRef;
  final String level;
  final String location;
  final DateTime inspectionDate;
  final FireDoorResult result;
  final List<FireDoorIssue> issues;

  const FireDoorItem({
    required this.id,
    this.doorRef = '',
    this.level = '',
    this.location = '',
    required this.inspectionDate,
    this.result = FireDoorResult.notInspected,
    this.issues = const [],
  });

  factory FireDoorItem.create() => FireDoorItem(
        id: _uuid.v4(),
        inspectionDate: DateTime.now(),
      );

  FireDoorItem copyWith({
    String? doorRef,
    String? level,
    String? location,
    DateTime? inspectionDate,
    FireDoorResult? result,
    List<FireDoorIssue>? issues,
  }) {
    return FireDoorItem(
      id: id,
      doorRef: doorRef ?? this.doorRef,
      level: level ?? this.level,
      location: location ?? this.location,
      inspectionDate: inspectionDate ?? this.inspectionDate,
      result: result ?? this.result,
      issues: issues ?? this.issues,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'doorRef': doorRef,
        'level': level,
        'location': location,
        'inspectionDate': inspectionDate.toIso8601String(),
        'result': result.name,
        'issues': issues.map((e) => e.toMap()).toList(),
      };

  factory FireDoorItem.fromMap(Map<String, dynamic> map) {
    return FireDoorItem(
      id: map['id'] as String? ?? _uuid.v4(),
      doorRef: map['doorRef'] as String? ?? '',
      level: map['level'] as String? ?? '',
      location: map['location'] as String? ?? '',
      inspectionDate:
          DateTime.tryParse(map['inspectionDate'] as String? ?? '') ??
              DateTime.now(),
      result: FireDoorResult.values.firstWhere(
        (e) => e.name == (map['result'] as String? ?? ''),
        orElse: () => FireDoorResult.notInspected,
      ),
      issues: (map['issues'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => FireDoorIssue.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class FireDoorProject {
  final String id;
  final String name;
  final String reference;
  final DateTime date;
  final List<FireDoorItem> items;
  final bool isArchived;
  final DateTime? archivedAt;
  final String archivedBy;

  const FireDoorProject({
    required this.id,
    this.name = '',
    this.reference = '',
    required this.date,
    this.items = const [],
    this.isArchived = false,
    this.archivedAt,
    this.archivedBy = '',
  });

  factory FireDoorProject.create() =>
      FireDoorProject(id: _uuid.v4(), date: DateTime.now());

  FireDoorProject copyWith({
    String? name,
    String? reference,
    DateTime? date,
    List<FireDoorItem>? items,
    bool? isArchived,
    DateTime? archivedAt,
    String? archivedBy,
  }) {
    return FireDoorProject(
      id: id,
      name: name ?? this.name,
      reference: reference ?? this.reference,
      date: date ?? this.date,
      items: items ?? this.items,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'reference': reference,
        'date': date.toIso8601String(),
        'items': items.map((e) => e.toMap()).toList(),
        'isArchived': isArchived,
        'archivedAt': archivedAt?.toIso8601String(),
        'archivedBy': archivedBy,
      };

  factory FireDoorProject.fromMap(Map<String, dynamic> map) {
    return FireDoorProject(
      id: map['id'] as String? ?? _uuid.v4(),
      name: map['name'] as String? ?? '',
      reference: map['reference'] as String? ?? '',
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      items: (map['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => FireDoorItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      isArchived: map['isArchived'] as bool? ?? false,
      archivedAt: DateTime.tryParse(map['archivedAt'] as String? ?? ''),
      archivedBy: map['archivedBy'] as String? ?? '',
    );
  }
}
