/// Provider for available companies in the snagging context.
///
/// This provider builds a list of companies from workspace settings.
/// It supports the main company plus any configured subcontractors.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/state/settings_controller.dart';
import '../domain/companies_source.dart';

/// Returns all available companies (main + subcontractors) for the current workspace.
///
/// The structure depends on what's configured in settings.
/// Currently: Main company from companyProfile + any subcontractors from workspaceCompanyProfiles
final availableCompaniesProvider = Provider<AvailableCompanies>((ref) {
  final settings = ref.watch(settingsControllerProvider);

  final mainCompanies = <CompanyOption>[];
  final subcontractors = <CompanyOption>[];

  // Add main company
  if (settings.companyProfile.companyName.isNotEmpty) {
    mainCompanies.add(
      CompanyOption(
        id: settings.companyProfile.companyId,
        name: settings.companyProfile.companyName,
        role: 'Main Contractor',
      ),
    );
  }

  // Add subcontractors from workspace company profiles
  // These are additional companies configured for the workspace
  for (final entry in settings.workspaceCompanyProfiles.entries) {
    final profile = entry.value;
    if (profile.companyName.isNotEmpty &&
        profile.companyId != settings.companyProfile.companyId) {
      subcontractors.add(
        CompanyOption(
          id: profile.companyId,
          name: profile.companyName,
          role: 'Subcontractor',
        ),
      );
    }
  }

  return AvailableCompanies(
    mainContractors: mainCompanies,
    subcontractors: subcontractors,
  );
});
