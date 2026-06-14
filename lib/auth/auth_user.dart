enum UserRole { owner, admin, manager, worker, superAdmin }

enum UserAccountStatus { active, inactive, suspended }

class AppUser {
  final String id;
  final String name;
  final String email;
  final String passwordHash;
  final String passwordSalt;
  final UserRole role;
  final String companyId;
  final UserAccountStatus status;
  final bool isInternalAdmin;
  final DateTime createdAt;

  bool get isActive => status == UserAccountStatus.active;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.passwordSalt,
    required this.role,
    required this.companyId,
    required this.status,
    required this.isInternalAdmin,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'passwordHash': passwordHash,
      'passwordSalt': passwordSalt,
      'role': role.name,
      'companyId': companyId,
      'status': status.name,
      'isActive': isActive,
      'isInternalAdmin': isInternalAdmin,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    final rawRole = (map['role'] as String? ?? '').trim();
    final normalizedRole = rawRole == 'super_admin' ? 'superAdmin' : rawRole;
    return AppUser(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      passwordHash: map['passwordHash'] as String? ?? '',
      passwordSalt: map['passwordSalt'] as String? ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.name == normalizedRole,
        orElse: () => UserRole.worker,
      ),
      companyId: map['companyId'] as String? ?? '',
      status: UserAccountStatus.values.firstWhere(
        (s) => s.name == (map['status'] as String? ?? ''),
        orElse: () => (map['isActive'] as bool? ?? true)
            ? UserAccountStatus.active
            : UserAccountStatus.inactive,
      ),
      isInternalAdmin: map['isInternalAdmin'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
