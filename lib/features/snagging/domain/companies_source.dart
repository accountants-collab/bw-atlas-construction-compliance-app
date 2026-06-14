/// Company data structures and utilities for Snagging assignment system
///
/// This module manages the retrieval and representation of companies
/// (main company + subcontractors) available in a project context.
library;

class CompanyOption {
  final String id;
  final String name;
  final String role; // 'Main Contractor', 'Subcontractor', etc.

  const CompanyOption({
    required this.id,
    required this.name,
    required this.role,
  });

  /// Display label: "Company Name (Role)"
  String get displayLabel => '$name ($role)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyOption &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          role == other.role;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ role.hashCode;
}

/// Container for all available companies in a project context
class AvailableCompanies {
  final List<CompanyOption> mainContractors;
  final List<CompanyOption> subcontractors;

  const AvailableCompanies({
    this.mainContractors = const [],
    this.subcontractors = const [],
  });

  /// All companies combined (main first, then subs)
  List<CompanyOption> get all => [...mainContractors, ...subcontractors];

  /// True if any companies are available
  bool get isEmpty => mainContractors.isEmpty && subcontractors.isEmpty;

  bool get isNotEmpty => !isEmpty;
}
