enum PlatformUserRole { owner, admin, manager, inspector, worker }

enum ProjectModuleType { inspection, remedial, preInstallation, installation }

class CompanyEntity {
  final String id;
  final String name;
  final String tradingName;
  final String email;
  final String phone;
  final String address;
  final String logoStoragePath;
  final DateTime createdAt;

  const CompanyEntity({
    required this.id,
    required this.name,
    required this.tradingName,
    required this.email,
    required this.phone,
    required this.address,
    required this.logoStoragePath,
    required this.createdAt,
  });
}

class CompanyBrandingEntity {
  final String companyId;
  final bool useCompanyBrandingOnPdf;
  final String reportHeader;
  final String reportFooter;
  final String reportLogoStoragePath;
  final String pdfFileNameFormat;

  const CompanyBrandingEntity({
    required this.companyId,
    required this.useCompanyBrandingOnPdf,
    required this.reportHeader,
    required this.reportFooter,
    required this.reportLogoStoragePath,
    required this.pdfFileNameFormat,
  });
}

class PlatformUserEntity {
  final String id;
  final String companyId;
  final String name;
  final String email;
  final PlatformUserRole role;
  final bool isActive;

  const PlatformUserEntity({
    required this.id,
    required this.companyId,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
  });
}

class ProjectEntity {
  final String id;
  final String companyId;
  final String title;
  final String siteAddress;
  final ProjectModuleType moduleType;
  final DateTime createdAt;

  const ProjectEntity({
    required this.id,
    required this.companyId,
    required this.title,
    required this.siteAddress,
    required this.moduleType,
    required this.createdAt,
  });
}

class DoorEntity {
  final String id;
  final String companyId;
  final String projectId;
  final String doorRef;
  final String location;
  final String fireRating;

  const DoorEntity({
    required this.id,
    required this.companyId,
    required this.projectId,
    required this.doorRef,
    required this.location,
    required this.fireRating,
  });
}

class InspectionEntity {
  final String id;
  final String companyId;
  final String projectId;
  final String doorId;
  final String inspectorUserId;
  final DateTime inspectedAt;

  const InspectionEntity({
    required this.id,
    required this.companyId,
    required this.projectId,
    required this.doorId,
    required this.inspectorUserId,
    required this.inspectedAt,
  });
}

class RemedialEntity {
  final String id;
  final String companyId;
  final String projectId;
  final String doorId;
  final String workerUserId;
  final String managerUserId;
  final String status;

  const RemedialEntity({
    required this.id,
    required this.companyId,
    required this.projectId,
    required this.doorId,
    required this.workerUserId,
    required this.managerUserId,
    required this.status,
  });
}

class PreInstallationEntity {
  final String id;
  final String companyId;
  final String projectId;
  final String openingRef;
  final String specificationJson;

  const PreInstallationEntity({
    required this.id,
    required this.companyId,
    required this.projectId,
    required this.openingRef,
    required this.specificationJson,
  });
}

class InstallationEntity {
  final String id;
  final String companyId;
  final String projectId;
  final String openingId;
  final String status;
  final DateTime? approvedAt;

  const InstallationEntity({
    required this.id,
    required this.companyId,
    required this.projectId,
    required this.openingId,
    required this.status,
    required this.approvedAt,
  });
}

class SubscriptionEntity {
  final String id;
  final String companyId;
  final int seatLimit;
  final int seatsUsed;
  final String stripeCustomerId;
  final String stripeSubscriptionId;
  final String stripePriceId;

  const SubscriptionEntity({
    required this.id,
    required this.companyId,
    required this.seatLimit,
    required this.seatsUsed,
    required this.stripeCustomerId,
    required this.stripeSubscriptionId,
    required this.stripePriceId,
  });
}

class InvoiceEntity {
  final String id;
  final String companyId;
  final String subscriptionId;
  final String invoiceNumber;
  final int amountMinor;
  final String currency;
  final DateTime issuedAt;

  const InvoiceEntity({
    required this.id,
    required this.companyId,
    required this.subscriptionId,
    required this.invoiceNumber,
    required this.amountMinor,
    required this.currency,
    required this.issuedAt,
  });
}

class MultiCompanyCollections {
  static const companies = 'companies';
  static const companyUsers = 'company_users';
  static const projects = 'projects';
  static const doors = 'doors';
  static const inspections = 'inspections';
  static const remedials = 'remedials';
  static const preInstallations = 'pre_installations';
  static const installations = 'installations';
  static const subscriptions = 'subscriptions';
  static const invoices = 'invoices';
  static const branding = 'branding_settings';
}
