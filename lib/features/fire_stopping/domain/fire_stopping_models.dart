import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum FireStoppingStatus { pending, inProgress, completed }

class FireStoppingFinding {
  final String id;
  final String title;
  final String comment;

  const FireStoppingFinding({
    required this.id,
    this.title = '',
    this.comment = '',
  });

  factory FireStoppingFinding.create() => FireStoppingFinding(id: _uuid.v4());

  FireStoppingFinding copyWith({String? title, String? comment}) {
    return FireStoppingFinding(
      id: id,
      title: title ?? this.title,
      comment: comment ?? this.comment,
    );
  }

  Map<String, dynamic> toMap() =>
      {'id': id, 'title': title, 'comment': comment};

  factory FireStoppingFinding.fromMap(Map<String, dynamic> map) {
    return FireStoppingFinding(
      id: map['id'] as String? ?? _uuid.v4(),
      title: map['title'] as String? ?? '',
      comment: map['comment'] as String? ?? '',
    );
  }
}

class FireStoppingItem {
  final String id;
  final String reference;
  final String level;
  final String location;
  final FireStoppingStatus status;
  final List<FireStoppingFinding> findings;

  const FireStoppingItem({
    required this.id,
    this.reference = '',
    this.level = '',
    this.location = '',
    this.status = FireStoppingStatus.pending,
    this.findings = const [],
  });

  factory FireStoppingItem.create() => FireStoppingItem(id: _uuid.v4());

  FireStoppingItem copyWith({
    String? reference,
    String? level,
    String? location,
    FireStoppingStatus? status,
    List<FireStoppingFinding>? findings,
  }) {
    return FireStoppingItem(
      id: id,
      reference: reference ?? this.reference,
      level: level ?? this.level,
      location: location ?? this.location,
      status: status ?? this.status,
      findings: findings ?? this.findings,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'reference': reference,
        'level': level,
        'location': location,
        'status': status.name,
        'findings': findings.map((e) => e.toMap()).toList(),
      };

  factory FireStoppingItem.fromMap(Map<String, dynamic> map) {
    return FireStoppingItem(
      id: map['id'] as String? ?? _uuid.v4(),
      reference: map['reference'] as String? ?? '',
      level: map['level'] as String? ?? '',
      location: map['location'] as String? ?? '',
      status: FireStoppingStatus.values.firstWhere(
        (e) => e.name == (map['status'] as String? ?? ''),
        orElse: () => FireStoppingStatus.pending,
      ),
      findings: (map['findings'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => FireStoppingFinding.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class FireStoppingProject {
  final String id;
  final String name;
  final String reference;
  final DateTime date;
  final List<FireStoppingItem> items;
  final bool isArchived;
  final DateTime? archivedAt;
  final String archivedBy;

  const FireStoppingProject({
    required this.id,
    this.name = '',
    this.reference = '',
    required this.date,
    this.items = const [],
    this.isArchived = false,
    this.archivedAt,
    this.archivedBy = '',
  });

  factory FireStoppingProject.create() =>
      FireStoppingProject(id: _uuid.v4(), date: DateTime.now());

  FireStoppingProject copyWith({
    String? name,
    String? reference,
    DateTime? date,
    List<FireStoppingItem>? items,
    bool? isArchived,
    DateTime? archivedAt,
    String? archivedBy,
  }) {
    return FireStoppingProject(
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

  factory FireStoppingProject.fromMap(Map<String, dynamic> map) {
    return FireStoppingProject(
      id: map['id'] as String? ?? _uuid.v4(),
      name: map['name'] as String? ?? '',
      reference: map['reference'] as String? ?? '',
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      items: (map['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => FireStoppingItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      isArchived: map['isArchived'] as bool? ?? false,
      archivedAt: DateTime.tryParse(map['archivedAt'] as String? ?? ''),
      archivedBy: map['archivedBy'] as String? ?? '',
    );
  }
}
