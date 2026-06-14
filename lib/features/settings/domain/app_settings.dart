enum TeamUserRole { owner, admin, manager, inspector, worker }

enum InviteStatus { pending, active, disabled }

String inviteStatusLabel(InviteStatus s) {
  switch (s) {
    case InviteStatus.pending:
      return 'Pending';
    case InviteStatus.active:
      return 'Active';
    case InviteStatus.disabled:
      return 'Disabled';
  }
}

enum SubscriptionPlan {
  users5,
  users10,
  users20,
  users50,
  users100,
}

int planUserLimit(SubscriptionPlan plan) {
  switch (plan) {
    case SubscriptionPlan.users5:
      return 5;
    case SubscriptionPlan.users10:
      return 10;
    case SubscriptionPlan.users20:
      return 20;
    case SubscriptionPlan.users50:
      return 50;
    case SubscriptionPlan.users100:
      return 100;
  }
}

String planLabel(SubscriptionPlan plan) {
  return '${planUserLimit(plan)} users';
}

String roleLabel(TeamUserRole role) {
  switch (role) {
    case TeamUserRole.owner:
      return 'Owner';
    case TeamUserRole.admin:
      return 'Admin';
    case TeamUserRole.manager:
      return 'Manager';
    case TeamUserRole.inspector:
      return 'Inspector';
    case TeamUserRole.worker:
      return 'Worker';
  }
}

class CompanyProfile {
  final String companyId;
  final String companyName;
  final String tradingName;
  final String address;
  final String addressLine1;
  final String addressLine2;
  final String cityTown;
  final String postCode;
  final String email;
  final String phone;
  final List<int> logoBytes;

  const CompanyProfile({
    this.companyId = '',
    this.companyName = '',
    this.tradingName = '',
    this.address = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.cityTown = '',
    this.postCode = '',
    this.email = '',
    this.phone = '',
    this.logoBytes = const [],
  });

  CompanyProfile copyWith({
    String? companyId,
    String? companyName,
    String? tradingName,
    String? address,
    String? addressLine1,
    String? addressLine2,
    String? cityTown,
    String? postCode,
    String? email,
    String? phone,
    List<int>? logoBytes,
  }) {
    return CompanyProfile(
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      tradingName: tradingName ?? this.tradingName,
      address: address ?? this.address,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      cityTown: cityTown ?? this.cityTown,
      postCode: postCode ?? this.postCode,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      logoBytes: logoBytes ?? this.logoBytes,
    );
  }
}

class TeamUser {
  final String id;
  final String companyId;
  final String name;
  final String email;
  final TeamUserRole role;
  final bool isActive;
  final InviteStatus inviteStatus;

  const TeamUser({
    required this.id,
    required this.companyId,
    required this.name,
    required this.email,
    required this.role,
    this.isActive = true,
    this.inviteStatus = InviteStatus.active,
  });

  TeamUser copyWith({
    String? id,
    String? companyId,
    String? name,
    String? email,
    TeamUserRole? role,
    bool? isActive,
    InviteStatus? inviteStatus,
  }) {
    return TeamUser(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      inviteStatus: inviteStatus ?? this.inviteStatus,
    );
  }
}

class BillingSettings {
  final String stripeCustomerId;
  final String stripeSubscriptionId;
  final String stripePriceId;

  const BillingSettings({
    this.stripeCustomerId = '',
    this.stripeSubscriptionId = '',
    this.stripePriceId = '',
  });

  BillingSettings copyWith({
    String? stripeCustomerId,
    String? stripeSubscriptionId,
    String? stripePriceId,
  }) {
    return BillingSettings(
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
      stripeSubscriptionId: stripeSubscriptionId ?? this.stripeSubscriptionId,
      stripePriceId: stripePriceId ?? this.stripePriceId,
    );
  }
}

class ReportBrandingSettings {
  final String reportHeader;
  final String reportFooter;
  final String pdfFileNameFormat;
  final bool useCompanyBrandingOnPdf;
  final List<int> reportLogoBytes;

  const ReportBrandingSettings({
    this.reportHeader = '',
    this.reportFooter = '',
    this.pdfFileNameFormat = '{company}_{type}_{report}_{date}',
    this.useCompanyBrandingOnPdf = true,
    this.reportLogoBytes = const [],
  });

  ReportBrandingSettings copyWith({
    String? reportHeader,
    String? reportFooter,
    String? pdfFileNameFormat,
    bool? useCompanyBrandingOnPdf,
    List<int>? reportLogoBytes,
  }) {
    return ReportBrandingSettings(
      reportHeader: reportHeader ?? this.reportHeader,
      reportFooter: reportFooter ?? this.reportFooter,
      pdfFileNameFormat: pdfFileNameFormat ?? this.pdfFileNameFormat,
      useCompanyBrandingOnPdf: useCompanyBrandingOnPdf ?? this.useCompanyBrandingOnPdf,
      reportLogoBytes: reportLogoBytes ?? this.reportLogoBytes,
    );
  }
}

class WorkspaceWorkerGroup {
  final String id;
  final String name;
  final DateTime createdAt;

  const WorkspaceWorkerGroup({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  WorkspaceWorkerGroup copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
  }) {
    return WorkspaceWorkerGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class AppSettings {
  final String activeCompanyId;
  final String activeWorkspaceKey;
  final Map<String, CompanyProfile> workspaceCompanyProfiles;
  final Map<String, ReportBrandingSettings> workspaceReportBranding;
  final Map<String, bool> workspaceOnboardingCompleted;
  final Map<String, List<WorkspaceWorkerGroup>> workspaceGroups;
  final Map<String, Map<String, String>> workspaceWorkerGroupAssignments;
  final CompanyProfile companyProfile;
  final List<TeamUser> teamUsers;
  final SubscriptionPlan subscriptionPlan;
  /// When > 0 this overrides the plan-based seat limit.
  final int customSeatCount;
  final BillingSettings billing;
  final ReportBrandingSettings reportBranding;
  final bool onboardingCompleted;

  const AppSettings({
    this.activeCompanyId = '',
    this.activeWorkspaceKey = 'fire-door',
    this.workspaceCompanyProfiles = const {},
    this.workspaceReportBranding = const {},
    this.workspaceOnboardingCompleted = const {},
    this.workspaceGroups = const {},
    this.workspaceWorkerGroupAssignments = const {},
    this.companyProfile = const CompanyProfile(),
    this.teamUsers = const [],
    this.subscriptionPlan = SubscriptionPlan.users5,
    this.customSeatCount = 0,
    this.billing = const BillingSettings(),
    this.reportBranding = const ReportBrandingSettings(),
    this.onboardingCompleted = false,
  });

  int get activeSeatsUsed => teamUsers.where((u) => u.isActive).length;

  int get seatLimit => customSeatCount < 1 ? 1 : customSeatCount;

  bool get isAtSeatLimit => activeSeatsUsed >= seatLimit;

  AppSettings copyWith({
    String? activeCompanyId,
    String? activeWorkspaceKey,
    Map<String, CompanyProfile>? workspaceCompanyProfiles,
    Map<String, ReportBrandingSettings>? workspaceReportBranding,
    Map<String, bool>? workspaceOnboardingCompleted,
    Map<String, List<WorkspaceWorkerGroup>>? workspaceGroups,
    Map<String, Map<String, String>>? workspaceWorkerGroupAssignments,
    CompanyProfile? companyProfile,
    List<TeamUser>? teamUsers,
    SubscriptionPlan? subscriptionPlan,
    int? customSeatCount,
    BillingSettings? billing,
    ReportBrandingSettings? reportBranding,
    bool? onboardingCompleted,
  }) {
    return AppSettings(
      activeCompanyId: activeCompanyId ?? this.activeCompanyId,
      activeWorkspaceKey: activeWorkspaceKey ?? this.activeWorkspaceKey,
      workspaceCompanyProfiles: workspaceCompanyProfiles ?? this.workspaceCompanyProfiles,
      workspaceReportBranding: workspaceReportBranding ?? this.workspaceReportBranding,
      workspaceOnboardingCompleted: workspaceOnboardingCompleted ?? this.workspaceOnboardingCompleted,
        workspaceGroups: workspaceGroups ?? this.workspaceGroups,
        workspaceWorkerGroupAssignments:
          workspaceWorkerGroupAssignments ?? this.workspaceWorkerGroupAssignments,
      companyProfile: companyProfile ?? this.companyProfile,
      teamUsers: teamUsers ?? this.teamUsers,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
      customSeatCount: customSeatCount ?? this.customSeatCount,
      billing: billing ?? this.billing,
      reportBranding: reportBranding ?? this.reportBranding,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }
}
