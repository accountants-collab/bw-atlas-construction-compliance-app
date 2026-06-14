import '../../features/settings/domain/app_settings.dart';

const String kDefaultSystemLogoAssetPath = 'assets/branding/bw_atlas_logo.png';
const String kDefaultSystemCompanyName = 'BW Atlas';

class ActiveLogoSource {
  final List<int> companyLogoBytes;
  final String fallbackAssetPath;

  const ActiveLogoSource({
    required this.companyLogoBytes,
    required this.fallbackAssetPath,
  });

  bool get hasCompanyLogo => companyLogoBytes.isNotEmpty;
}

class ResolvedPdfBranding {
  final List<int> logoBytes;
  final String companyName;
  final String reportHeaderText;
  final String reportFooterText;

  const ResolvedPdfBranding({
    required this.logoBytes,
    required this.companyName,
    required this.reportHeaderText,
    required this.reportFooterText,
  });
}

String resolveCompanyDisplayName(CompanyProfile profile) {
  final trading = profile.tradingName.trim();
  if (trading.isNotEmpty) return trading;
  final company = profile.companyName.trim();
  if (company.isNotEmpty) return company;
  return kDefaultSystemCompanyName;
}

ActiveLogoSource getActiveLogo(CompanyProfile profile) {
  return ActiveLogoSource(
    companyLogoBytes: profile.logoBytes,
    fallbackAssetPath: kDefaultSystemLogoAssetPath,
  );
}

String getActiveCompanyName(CompanyProfile profile) {
  return resolveCompanyDisplayName(profile);
}

ResolvedPdfBranding resolvePdfBranding(AppSettings settings) {
  final activeLogo = getActiveLogo(settings.companyProfile);
  final headerText = settings.reportBranding.reportHeader.trim();
  final footerText = settings.reportBranding.reportFooter.trim();

  return ResolvedPdfBranding(
    logoBytes: activeLogo.companyLogoBytes,
    companyName: getActiveCompanyName(settings.companyProfile),
    reportHeaderText: headerText.isEmpty
        ? 'BW Atlas - Construction Compliance Platform'
        : headerText,
    reportFooterText:
        footerText.isEmpty ? 'Generated with BW Atlas' : footerText,
  );
}
