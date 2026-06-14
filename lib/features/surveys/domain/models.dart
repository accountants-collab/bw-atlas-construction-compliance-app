import 'package:uuid/uuid.dart';

import '../../disclaimer/domain/disclaimer_models.dart';

final _uuid = Uuid();

enum SurveyType {
  survey,
  fireStopping,
  snagging,
  maintenance,
  installation,
  installationSurvey
}

enum InspectionWorkspace { fireDoor, fireStopping, snagging }

String inspectionWorkspaceSlug(InspectionWorkspace workspace) {
  switch (workspace) {
    case InspectionWorkspace.fireDoor:
      return 'fire-door';
    case InspectionWorkspace.fireStopping:
      return 'fire-stopping';
    case InspectionWorkspace.snagging:
      return 'snagging';
  }
}

InspectionWorkspace? parseInspectionWorkspaceKey(String raw) {
  switch (raw) {
    case 'fire-door':
      return InspectionWorkspace.fireDoor;
    case 'fire-stopping':
      return InspectionWorkspace.fireStopping;
    case 'snagging':
      return InspectionWorkspace.snagging;
    default:
      return null;
  }
}

class Survey {
  final String id;
  final String companyId;
  final SurveyType type;
  final InspectionWorkspace workspace;
  final DateTime createdAt;
  final DateTime reportDate;

  // Existing fields (keep for backward compatibility / existing PDF code)
  final String siteName;
  final String siteAddress;
  final String reference;
  final String registerReference;

  // New fields (Report details)
  final String reportName;
  final String addressLine1;
  final String addressLine2;
  final String cityTown;
  final String postCode;
  final String reportCompletedBy;
  final String clientName;
  final String clientEmail;
  final String clientPhone;

  // Disclaimer (per survey)
  final DateTime? disclaimerAcceptedAt;
  final String disclaimerAcceptedBy;
  final DisclaimerAcceptanceRecord? disclaimerAcceptance;

  final List<ProjectDrawing> projectDrawings;
  final List<String> assignedGroupIds; // IDs of groups assigned to this survey
  final bool isArchived;
  final DateTime? archivedAt;
  final String archivedBy;
  final DateTime? restoredAt;
  final String restoredBy;

  final List<Door> doors;
  final List<PreInstallItem> preInstallItems;

  Survey({
    String? id,
    this.companyId = '',
    required this.type,
    this.workspace = InspectionWorkspace.fireDoor,
    DateTime? createdAt,
    DateTime? reportDate,

    // Existing defaults
    this.siteName = '',
    this.siteAddress = '',
    this.reference = '',
    this.registerReference = '',

    // New defaults
    this.reportName = '',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.cityTown = '',
    this.postCode = '',
    this.reportCompletedBy = '',
    this.clientName = '',
    this.clientEmail = '',
    this.clientPhone = '',

    // Disclaimer defaults
    this.disclaimerAcceptedAt,
    this.disclaimerAcceptedBy = '',
    this.disclaimerAcceptance,
    List<ProjectDrawing>? projectDrawings,
    List<String>? assignedGroupIds,
    this.isArchived = false,
    this.archivedAt,
    this.archivedBy = '',
    this.restoredAt,
    this.restoredBy = '',
    List<Door>? doors,
    List<PreInstallItem>? preInstallItems,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        reportDate = reportDate ?? createdAt ?? DateTime.now(),
        projectDrawings = projectDrawings ?? [],
        assignedGroupIds = assignedGroupIds ?? [],
        doors = doors ?? [],
        preInstallItems = preInstallItems ?? [];

  Survey copyWith({
    InspectionWorkspace? workspace,
    String? companyId,
    // Existing
    String? siteName,
    String? siteAddress,
    String? reference,
    String? registerReference,
    DateTime? reportDate,
    List<Door>? doors,
    List<PreInstallItem>? preInstallItems,

    // New
    String? reportName,
    String? addressLine1,
    String? addressLine2,
    String? cityTown,
    String? postCode,
    String? reportCompletedBy,
    String? clientName,
    String? clientEmail,
    String? clientPhone,

    // Disclaimer
    DateTime? disclaimerAcceptedAt,
    String? disclaimerAcceptedBy,
    DisclaimerAcceptanceRecord? disclaimerAcceptance,
    List<ProjectDrawing>? projectDrawings,
    List<String>? assignedGroupIds,
    bool? isArchived,
    DateTime? archivedAt,
    String? archivedBy,
    DateTime? restoredAt,
    String? restoredBy,
  }) {
    return Survey(
      id: id,
      companyId: companyId ?? this.companyId,
      workspace: workspace ?? this.workspace,
      type: type,
      createdAt: createdAt,
      siteName: siteName ?? this.siteName,
      siteAddress: siteAddress ?? this.siteAddress,
      reference: reference ?? this.reference,
      registerReference: registerReference ?? this.registerReference,
      reportDate: reportDate ?? this.reportDate,
      reportName: reportName ?? this.reportName,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      cityTown: cityTown ?? this.cityTown,
      postCode: postCode ?? this.postCode,
      reportCompletedBy: reportCompletedBy ?? this.reportCompletedBy,
      clientName: clientName ?? this.clientName,
      clientEmail: clientEmail ?? this.clientEmail,
      clientPhone: clientPhone ?? this.clientPhone,
      disclaimerAcceptedAt: disclaimerAcceptedAt ?? this.disclaimerAcceptedAt,
      disclaimerAcceptedBy: disclaimerAcceptedBy ?? this.disclaimerAcceptedBy,
      disclaimerAcceptance: disclaimerAcceptance ?? this.disclaimerAcceptance,
      projectDrawings: projectDrawings ?? this.projectDrawings,
      assignedGroupIds: assignedGroupIds ?? this.assignedGroupIds,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      restoredAt: restoredAt ?? this.restoredAt,
      restoredBy: restoredBy ?? this.restoredBy,
      doors: doors ?? this.doors,
      preInstallItems: preInstallItems ?? this.preInstallItems,
    );
  }
}

/// A pin placed by the manager on a floor-plan drawing.
class FloorPlanPin {
  final String id;
  final String drawingId;

  /// 1-based PDF page index. For image drawings this stays 1.
  final int page;

  /// x position normalised to the image width  (0.0 – 1.0).
  final double x;

  /// y position normalised to the image height (0.0 – 1.0).
  final double y;
  final String doorNumber;
  final String label;

  /// Optional: links to the Door.id it represents.
  final String doorId;

  FloorPlanPin({
    String? id,
    required this.drawingId,
    this.page = 1,
    required this.x,
    required this.y,
    required this.doorNumber,
    this.label = '',
    this.doorId = '',
  }) : id = id ?? _uuid.v4();
}

class ProjectDrawing {
  final String id;
  final String name;
  final String fileName;
  final String mimeType;
  final String level;
  final String description;
  final List<int> bytes;
  final String cloudStoragePath;
  final String cloudDownloadUrl;
  final DateTime createdAt;
  final List<FloorPlanPin> pins;

  ProjectDrawing({
    String? id,
    String? name,
    required this.fileName,
    required this.mimeType,
    this.level = '',
    this.description = '',
    required this.bytes,
    this.cloudStoragePath = '',
    this.cloudDownloadUrl = '',
    DateTime? createdAt,
    List<FloorPlanPin>? pins,
  })  : id = id ?? _uuid.v4(),
        name = (name == null || name.trim().isEmpty) ? fileName : name,
        createdAt = createdAt ?? DateTime.now(),
        pins = pins ?? const [];

  ProjectDrawing copyWith({
    String? name,
    String? level,
    String? description,
    String? fileName,
    String? mimeType,
    List<int>? bytes,
    String? cloudStoragePath,
    String? cloudDownloadUrl,
    List<FloorPlanPin>? pins,
  }) {
    return ProjectDrawing(
      id: id,
      name: name ?? this.name,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      level: level ?? this.level,
      description: description ?? this.description,
      bytes: bytes ?? this.bytes,
      cloudStoragePath: cloudStoragePath ?? this.cloudStoragePath,
      cloudDownloadUrl: cloudDownloadUrl ?? this.cloudDownloadUrl,
      createdAt: createdAt,
      pins: pins ?? this.pins,
    );
  }
}

enum InstallationTaskStatus { notCompleted, completed, notApplicable }

enum InstallationStatus {
  pending,
  inProgress,
  completedByWorker,
  forApproval,
  approved,
  rejectedNeedsRework,
}

/// Pre-Installation survey type: whether surveying existing door or new opening
enum PreInstallSurveyType {
  specification_order,
  existing_door,
  new_opening,
  installation_only,
}

bool isSpecificationOrderWorkflowType(PreInstallSurveyType type) {
  switch (type) {
    case PreInstallSurveyType.specification_order:
    case PreInstallSurveyType.existing_door:
    case PreInstallSurveyType.new_opening:
      return true;
    case PreInstallSurveyType.installation_only:
      return false;
  }
}

String preInstallWorkflowTypeLabel(PreInstallSurveyType type) {
  if (isSpecificationOrderWorkflowType(type)) {
    return 'Specification / Order';
  }
  return 'Installation Only';
}

/// Supply responsibility: who will supply the door/doorset
enum PreInstallSupplyResponsibility {
  bw_supply_install,
  client_supplied,
  main_contractor_supplied,
  custom,
}

/// Pre-Installation workflow status (independent of Installation status)
enum PreInstallationWorkflowStatus {
  draft,
  survey_completed,
  approved_for_order, // manager approved – factory/order begins
  ready_for_factory_order,
  ordered,
  delivered_ready,
  available_on_site, // installation_only – doors physically on site
  released_to_installation,
}

class InstallationTask {
  final String id;
  final String title;
  final String category;
  final bool required;
  final InstallationTaskStatus status;
  final String workerNote;

  InstallationTask({
    String? id,
    required this.title,
    required this.category,
    this.required = true,
    this.status = InstallationTaskStatus.notCompleted,
    this.workerNote = '',
  }) : id = id ?? _uuid.v4();

  InstallationTask copyWith({
    String? title,
    String? category,
    bool? required,
    InstallationTaskStatus? status,
    String? workerNote,
  }) {
    return InstallationTask(
      id: id,
      title: title ?? this.title,
      category: category ?? this.category,
      required: required ?? this.required,
      status: status ?? this.status,
      workerNote: workerNote ?? this.workerNote,
    );
  }
}

class PreInstallPhoto {
  final String id;
  final String projectId;
  final String itemId;
  final String type;
  final String fileName;
  final String mimeType;
  final List<int> bytes;
  final String cloudStoragePath;
  final String cloudDownloadUrl;
  final DateTime createdAt;

  PreInstallPhoto({
    String? id,
    required this.projectId,
    required this.itemId,
    this.type = 'preInstall',
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    this.cloudStoragePath = '',
    this.cloudDownloadUrl = '',
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  PreInstallPhoto copyWith({
    String? fileName,
    String? mimeType,
    List<int>? bytes,
    String? cloudStoragePath,
    String? cloudDownloadUrl,
  }) {
    return PreInstallPhoto(
      id: id,
      projectId: projectId,
      itemId: itemId,
      type: type,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      bytes: bytes ?? this.bytes,
      cloudStoragePath: cloudStoragePath ?? this.cloudStoragePath,
      cloudDownloadUrl: cloudDownloadUrl ?? this.cloudDownloadUrl,
      createdAt: createdAt,
    );
  }
}

class InstallationPhoto {
  final String id;
  final String projectId;
  final String itemId;
  final String type;
  final String fileName;
  final String mimeType;
  final List<int> bytes;
  final String cloudStoragePath;
  final String cloudDownloadUrl;
  final DateTime createdAt;

  InstallationPhoto({
    String? id,
    required this.projectId,
    required this.itemId,
    required this.type,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    this.cloudStoragePath = '',
    this.cloudDownloadUrl = '',
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  InstallationPhoto copyWith({
    String? fileName,
    String? mimeType,
    List<int>? bytes,
    String? cloudStoragePath,
    String? cloudDownloadUrl,
  }) {
    return InstallationPhoto(
      id: id,
      projectId: projectId,
      itemId: itemId,
      type: type,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      bytes: bytes ?? this.bytes,
      cloudStoragePath: cloudStoragePath ?? this.cloudStoragePath,
      cloudDownloadUrl: cloudDownloadUrl ?? this.cloudDownloadUrl,
      createdAt: createdAt,
    );
  }
}

class InstallationApproval {
  final String id;
  final String projectId;
  final String itemId;
  final String approvedBy;
  final DateTime approvedDate;
  final String decision;
  final String comment;
  final String signatureMethod;
  final List<int> signatureImageBytes;
  final String approvedMaintainerNumber;
  final String approvedMaintainerName;

  InstallationApproval({
    String? id,
    required this.projectId,
    required this.itemId,
    required this.approvedBy,
    DateTime? approvedDate,
    required this.decision,
    this.comment = '',
    this.signatureMethod = 'none',
    this.signatureImageBytes = const [],
    this.approvedMaintainerNumber = '',
    this.approvedMaintainerName = '',
  })  : id = id ?? _uuid.v4(),
        approvedDate = approvedDate ?? DateTime.now();
}

class DoorFeatureItem {
  final String id;
  final String type;
  final bool selected;
  final String value;
  final String position;
  final String note;

  const DoorFeatureItem({
    required this.id,
    required this.type,
    this.selected = false,
    this.value = '',
    this.position = '',
    this.note = '',
  });

  DoorFeatureItem copyWith({
    String? type,
    bool? selected,
    String? value,
    String? position,
    String? note,
  }) {
    return DoorFeatureItem(
      id: id,
      type: type ?? this.type,
      selected: selected ?? this.selected,
      value: value ?? this.value,
      position: position ?? this.position,
      note: note ?? this.note,
    );
  }
}

class DoorHardwareItem {
  final String id;
  final String category;
  final String type;
  final bool selected;
  final String note;

  const DoorHardwareItem({
    required this.id,
    required this.category,
    required this.type,
    this.selected = false,
    this.note = '',
  });

  DoorHardwareItem copyWith({
    String? category,
    String? type,
    bool? selected,
    String? note,
  }) {
    return DoorHardwareItem(
      id: id,
      category: category ?? this.category,
      type: type ?? this.type,
      selected: selected ?? this.selected,
      note: note ?? this.note,
    );
  }
}

class DoorMeasurementSet {
  final String id;
  final double? openingWidthTop;
  final double? openingWidthMiddle;
  final double? openingWidthBottom;
  final double? openingHeightLeft;
  final double? openingHeightCentre;
  final double? openingHeightRight;
  final double? frameWidth;
  final double? frameHeight;
  final double? frameDepth;
  final double? leafWidth;
  final double? leafHeight;
  final double? leafThickness;

  const DoorMeasurementSet({
    required this.id,
    this.openingWidthTop,
    this.openingWidthMiddle,
    this.openingWidthBottom,
    this.openingHeightLeft,
    this.openingHeightCentre,
    this.openingHeightRight,
    this.frameWidth,
    this.frameHeight,
    this.frameDepth,
    this.leafWidth,
    this.leafHeight,
    this.leafThickness,
  });

  DoorMeasurementSet copyWith({
    double? openingWidthTop,
    double? openingWidthMiddle,
    double? openingWidthBottom,
    double? openingHeightLeft,
    double? openingHeightCentre,
    double? openingHeightRight,
    double? frameWidth,
    double? frameHeight,
    double? frameDepth,
    double? leafWidth,
    double? leafHeight,
    double? leafThickness,
  }) {
    return DoorMeasurementSet(
      id: id,
      openingWidthTop: openingWidthTop ?? this.openingWidthTop,
      openingWidthMiddle: openingWidthMiddle ?? this.openingWidthMiddle,
      openingWidthBottom: openingWidthBottom ?? this.openingWidthBottom,
      openingHeightLeft: openingHeightLeft ?? this.openingHeightLeft,
      openingHeightCentre: openingHeightCentre ?? this.openingHeightCentre,
      openingHeightRight: openingHeightRight ?? this.openingHeightRight,
      frameWidth: frameWidth ?? this.frameWidth,
      frameHeight: frameHeight ?? this.frameHeight,
      frameDepth: frameDepth ?? this.frameDepth,
      leafWidth: leafWidth ?? this.leafWidth,
      leafHeight: leafHeight ?? this.leafHeight,
      leafThickness: leafThickness ?? this.leafThickness,
    );
  }
}

class PreInstallItem {
  final String id;
  final String projectId;
  final String doorRef;
  final String doorDrawingId;
  final String doorPinId;
  final String level;
  final String location;
  final String doorPurpose;
  final String configuration;
  final bool hasFrame;
  final String handingMode;
  final String openingWidth;
  final String openingHeight;
  final String frameDepth;
  final String handing;
  final String fireRating;
  final String doorType;
  final String leafType;
  final String frameType;
  final String threshold;
  final String glazing;
  final String glazingDetails;
  final String seals;
  final String ironmongery;
  final String closer;
  final String lockLatchType;
  final String letterplate;
  final String viewer;
  final String signage;
  final String customSignage;
  final String glazingType;
  final bool ventilationGrilleEnabled;
  final String ventilationGrillePosition;
  final String finish;
  final String doorMaterial;
  final String frameMaterial;
  final String finishType;
  final String colourRal;
  final String specialFinishNotes;
  final String architraves;
  final String specialNotes;
  final String accessNotes;
  final String materialsRequired;
  final String preInstallComments;
  final String manufactureNotes;
  final String revisionVersion;
  final InstallationStatus status;
  final List<PreInstallPhoto> preInstallPhotos;
  final List<DoorFeatureItem> features;
  final List<DoorHardwareItem> hardware;
  final DoorMeasurementSet? measurements;
  final List<InstallationTask> installationTasks;
  final List<InstallationPhoto> installationPhotos;
  final String workerNote;
  final String completedBy;
  final DateTime? completedDate;
  final String submittedBy;
  final DateTime? submittedAt;
  final String approvedBy;
  final DateTime? approvedAt;
  final String rejectedBy;
  final DateTime? rejectedAt;
  final String rejectionNote;
  final InstallationApproval? approval;
  final String rejectionReason;
  final List<InstallationPhoto> managerApprovalPhotos;
  final List<InstallationPhoto> managerRejectionPhotos;
  final String linkedDoorId;
  final bool fullReplacementTask;
  final PreInstallSurveyType surveyType;
  final bool existingDoorRemovalRequired;
  final PreInstallSupplyResponsibility supplyResponsibility;
  final String customSupplyResponsibility;
  final PreInstallationWorkflowStatus preInstallationStatus;
  final DateTime? expectedDeliveryDate;
  final bool deliveryConfirmed;
  final DateTime? deliveryConfirmedAt;
  final String deliveryConfirmedBy;

  /// @deprecated No longer used. Was: If true, item is released to installation (legacy, deprecated, ignored by app)
  @Deprecated('No longer used. Use visibleToWorkers/workerVisibleFrom instead.')
  final bool releasedToInstallation;

  /// @deprecated No longer used. Was: Date/time released to installation (legacy, deprecated, ignored by app)
  @Deprecated('No longer used. Use visibleToWorkers/workerVisibleFrom instead.')
  final DateTime? releasedDate;

  /// @deprecated No longer used. Was: User who released to installation (legacy, deprecated, ignored by app)
  @Deprecated('No longer used. Use visibleToWorkers/workerVisibleFrom instead.')
  final String releasedBy;

  // Worker / subcontractor visibility (separate from installation release)
  final bool visibleToWorkers;
  final DateTime? workerVisibleFrom;

  const PreInstallItem({
    required this.id,
    required this.projectId,
    this.doorRef = '',
    this.doorDrawingId = '',
    this.doorPinId = '',
    this.level = '',
    this.location = '',
    this.doorPurpose = '',
    this.configuration = 'singleLeaf',
    this.hasFrame = true,
    this.handingMode = 'hingesLeftIn',
    this.openingWidth = '',
    this.openingHeight = '',
    this.frameDepth = '',
    this.handing = '',
    this.fireRating = '',
    this.doorType = '',
    this.leafType = '',
    this.frameType = '',
    this.threshold = '',
    this.glazing = '',
    this.glazingDetails = '',
    this.seals = '',
    this.ironmongery = '',
    this.closer = '',
    this.lockLatchType = '',
    this.letterplate = '',
    this.viewer = '',
    this.signage = '',
    this.customSignage = '',
    this.glazingType = 'none',
    this.ventilationGrilleEnabled = false,
    this.ventilationGrillePosition = 'low',
    this.finish = '',
    this.doorMaterial = '',
    this.frameMaterial = '',
    this.finishType = '',
    this.colourRal = '',
    this.specialFinishNotes = '',
    this.architraves = '',
    this.specialNotes = '',
    this.accessNotes = '',
    this.materialsRequired = '',
    this.preInstallComments = '',
    this.manufactureNotes = '',
    this.revisionVersion = 'v1',
    this.status = InstallationStatus.pending,
    this.preInstallPhotos = const [],
    this.features = const [],
    this.hardware = const [],
    this.measurements,
    this.installationTasks = const [],
    this.installationPhotos = const [],
    this.workerNote = '',
    this.completedBy = '',
    this.completedDate,
    this.submittedBy = '',
    this.submittedAt,
    this.approvedBy = '',
    this.approvedAt,
    this.rejectedBy = '',
    this.rejectedAt,
    this.rejectionNote = '',
    this.approval,
    this.rejectionReason = '',
    this.managerApprovalPhotos = const [],
    this.managerRejectionPhotos = const [],
    this.linkedDoorId = '',
    this.fullReplacementTask = false,
    this.surveyType = PreInstallSurveyType.specification_order,
    this.existingDoorRemovalRequired = true,
    this.supplyResponsibility =
        PreInstallSupplyResponsibility.bw_supply_install,
    this.customSupplyResponsibility = '',
    this.preInstallationStatus = PreInstallationWorkflowStatus.draft,
    this.expectedDeliveryDate,
    this.deliveryConfirmed = false,
    this.deliveryConfirmedAt,
    this.deliveryConfirmedBy = '',
    this.releasedToInstallation = false,
    this.releasedDate,
    this.releasedBy = '',
    this.visibleToWorkers = false,
    this.workerVisibleFrom,
  });

  PreInstallItem copyWith({
    String? doorRef,
    String? doorDrawingId,
    String? doorPinId,
    String? level,
    String? location,
    String? doorPurpose,
    String? configuration,
    bool? hasFrame,
    String? handingMode,
    String? openingWidth,
    String? openingHeight,
    String? frameDepth,
    String? handing,
    String? fireRating,
    String? doorType,
    String? leafType,
    String? frameType,
    String? threshold,
    String? glazing,
    String? glazingDetails,
    String? seals,
    String? ironmongery,
    String? closer,
    String? lockLatchType,
    String? letterplate,
    String? viewer,
    String? signage,
    String? customSignage,
    String? glazingType,
    bool? ventilationGrilleEnabled,
    String? ventilationGrillePosition,
    String? finish,
    String? doorMaterial,
    String? frameMaterial,
    String? finishType,
    String? colourRal,
    String? specialFinishNotes,
    String? architraves,
    String? specialNotes,
    String? accessNotes,
    String? materialsRequired,
    String? preInstallComments,
    String? manufactureNotes,
    String? revisionVersion,
    InstallationStatus? status,
    List<PreInstallPhoto>? preInstallPhotos,
    List<DoorFeatureItem>? features,
    List<DoorHardwareItem>? hardware,
    DoorMeasurementSet? measurements,
    bool clearMeasurements = false,
    List<InstallationTask>? installationTasks,
    List<InstallationPhoto>? installationPhotos,
    String? workerNote,
    String? completedBy,
    DateTime? completedDate,
    bool clearCompletedDate = false,
    String? submittedBy,
    DateTime? submittedAt,
    bool clearSubmittedAt = false,
    String? approvedBy,
    DateTime? approvedAt,
    bool clearApprovedAt = false,
    String? rejectedBy,
    DateTime? rejectedAt,
    bool clearRejectedAt = false,
    String? rejectionNote,
    InstallationApproval? approval,
    bool clearApproval = false,
    String? rejectionReason,
    List<InstallationPhoto>? managerApprovalPhotos,
    List<InstallationPhoto>? managerRejectionPhotos,
    String? linkedDoorId,
    bool? fullReplacementTask,
    PreInstallSurveyType? surveyType,
    bool? existingDoorRemovalRequired,
    PreInstallSupplyResponsibility? supplyResponsibility,
    String? customSupplyResponsibility,
    PreInstallationWorkflowStatus? preInstallationStatus,
    DateTime? expectedDeliveryDate,
    bool clearExpectedDeliveryDate = false,
    bool? deliveryConfirmed,
    DateTime? deliveryConfirmedAt,
    bool clearDeliveryConfirmedAt = false,
    String? deliveryConfirmedBy,
    bool? releasedToInstallation,
    DateTime? releasedDate,
    bool clearReleasedDate = false,
    String? releasedBy,
    bool? visibleToWorkers,
    DateTime? workerVisibleFrom,
    bool clearWorkerVisibleFrom = false,
  }) {
    return PreInstallItem(
      id: id,
      projectId: projectId,
      doorRef: doorRef ?? this.doorRef,
      doorDrawingId: doorDrawingId ?? this.doorDrawingId,
      doorPinId: doorPinId ?? this.doorPinId,
      level: level ?? this.level,
      location: location ?? this.location,
      doorPurpose: doorPurpose ?? this.doorPurpose,
      configuration: configuration ?? this.configuration,
      hasFrame: hasFrame ?? this.hasFrame,
      handingMode: handingMode ?? this.handingMode,
      openingWidth: openingWidth ?? this.openingWidth,
      openingHeight: openingHeight ?? this.openingHeight,
      frameDepth: frameDepth ?? this.frameDepth,
      handing: handing ?? this.handing,
      fireRating: fireRating ?? this.fireRating,
      doorType: doorType ?? this.doorType,
      leafType: leafType ?? this.leafType,
      frameType: frameType ?? this.frameType,
      threshold: threshold ?? this.threshold,
      glazing: glazing ?? this.glazing,
      glazingDetails: glazingDetails ?? this.glazingDetails,
      seals: seals ?? this.seals,
      ironmongery: ironmongery ?? this.ironmongery,
      closer: closer ?? this.closer,
      lockLatchType: lockLatchType ?? this.lockLatchType,
      letterplate: letterplate ?? this.letterplate,
      viewer: viewer ?? this.viewer,
      signage: signage ?? this.signage,
      customSignage: customSignage ?? this.customSignage,
      glazingType: glazingType ?? this.glazingType,
      ventilationGrilleEnabled:
          ventilationGrilleEnabled ?? this.ventilationGrilleEnabled,
      ventilationGrillePosition:
          ventilationGrillePosition ?? this.ventilationGrillePosition,
      finish: finish ?? this.finish,
      doorMaterial: doorMaterial ?? this.doorMaterial,
      frameMaterial: frameMaterial ?? this.frameMaterial,
      finishType: finishType ?? this.finishType,
      colourRal: colourRal ?? this.colourRal,
      specialFinishNotes: specialFinishNotes ?? this.specialFinishNotes,
      architraves: architraves ?? this.architraves,
      specialNotes: specialNotes ?? this.specialNotes,
      accessNotes: accessNotes ?? this.accessNotes,
      materialsRequired: materialsRequired ?? this.materialsRequired,
      preInstallComments: preInstallComments ?? this.preInstallComments,
      manufactureNotes: manufactureNotes ?? this.manufactureNotes,
      revisionVersion: revisionVersion ?? this.revisionVersion,
      status: status ?? this.status,
      preInstallPhotos: preInstallPhotos ?? this.preInstallPhotos,
      features: features ?? this.features,
      hardware: hardware ?? this.hardware,
      measurements:
          clearMeasurements ? null : (measurements ?? this.measurements),
      installationTasks: installationTasks ?? this.installationTasks,
      installationPhotos: installationPhotos ?? this.installationPhotos,
      workerNote: workerNote ?? this.workerNote,
      completedBy: completedBy ?? this.completedBy,
      completedDate:
          clearCompletedDate ? null : (completedDate ?? this.completedDate),
      submittedBy: submittedBy ?? this.submittedBy,
      submittedAt: clearSubmittedAt ? null : (submittedAt ?? this.submittedAt),
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: clearApprovedAt ? null : (approvedAt ?? this.approvedAt),
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectedAt: clearRejectedAt ? null : (rejectedAt ?? this.rejectedAt),
      rejectionNote: rejectionNote ?? this.rejectionNote,
      approval: clearApproval ? null : (approval ?? this.approval),
      rejectionReason: rejectionReason ?? this.rejectionReason,
      managerApprovalPhotos:
          managerApprovalPhotos ?? this.managerApprovalPhotos,
      managerRejectionPhotos:
          managerRejectionPhotos ?? this.managerRejectionPhotos,
      linkedDoorId: linkedDoorId ?? this.linkedDoorId,
      fullReplacementTask: fullReplacementTask ?? this.fullReplacementTask,
      surveyType: surveyType ?? this.surveyType,
      existingDoorRemovalRequired:
          existingDoorRemovalRequired ?? this.existingDoorRemovalRequired,
      supplyResponsibility: supplyResponsibility ?? this.supplyResponsibility,
      customSupplyResponsibility:
          customSupplyResponsibility ?? this.customSupplyResponsibility,
      preInstallationStatus:
          preInstallationStatus ?? this.preInstallationStatus,
      expectedDeliveryDate: clearExpectedDeliveryDate
          ? null
          : (expectedDeliveryDate ?? this.expectedDeliveryDate),
      deliveryConfirmed: deliveryConfirmed ?? this.deliveryConfirmed,
      deliveryConfirmedAt: clearDeliveryConfirmedAt
          ? null
          : (deliveryConfirmedAt ?? this.deliveryConfirmedAt),
      deliveryConfirmedBy: deliveryConfirmedBy ?? this.deliveryConfirmedBy,
      releasedToInstallation:
          releasedToInstallation ?? this.releasedToInstallation,
      releasedDate:
          clearReleasedDate ? null : (releasedDate ?? this.releasedDate),
      releasedBy: releasedBy ?? this.releasedBy,
      visibleToWorkers: visibleToWorkers ?? this.visibleToWorkers,
      workerVisibleFrom: clearWorkerVisibleFrom
          ? null
          : (workerVisibleFrom ?? this.workerVisibleFrom),
    );
  }
}

enum DoorType { corridor, storeroom, entrance, kitchen, bedroom, other }

enum FireRating {
  fd30,
  fd30s,
  fd60,
  fd60s,
  fd90,
  fd90s,
  fd120,
  fd120s,
  notAFireDoor,
  unknown,
}

/// Evidence level / Compliance evidence (UK fire door survey style)
enum GradingLevel { level1, level2, level3, level4 }

enum DoorResult { unknown, pass, advisory, fail }

enum DoorFunction {
  apartmentInternal,
  flatEntrance,
  corridor,
  stairwell,
  communal,
  other,
  unknown,
}

enum DoorMaterial {
  timber,
  metalDoor,
  composite,
  aluminium,
  upvc,
  otherCustom,
  unknown,
}

/// Repurposed to "Certification status" (UK wording).
enum DoorClassification {
  /// Third-party certified.
  thirdPartyCertified,

  /// Manufacturer evidence available.
  manufacturerEvidenceAvailable,

  /// No evidence (client states door is fire-rated).
  noEvidenceClientStatedFireRated,

  /// Unknown / not verified.
  unknownNotVerified,
}

enum DoorConfiguration { singleLeaf, doubleLeaf, leafAndAHalf }

enum IssueSeverity { criticalFail, fail, advisory }

class PhotoAttachment {
  final String id;
  final String fileName;
  final String mimeType;
  final List<int> bytes;
  final DateTime capturedAt;
  final String surveyId;
  final String doorId;
  final String issueId;

  PhotoAttachment({
    String? id,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    DateTime? capturedAt,
    this.surveyId = '',
    this.doorId = '',
    this.issueId = '',
  })  : id = id ?? _uuid.v4(),
        capturedAt = capturedAt ?? DateTime.now();
}

enum RemedialStatus {
  pending,
  inProgress,
  completedByWorker,
  forApproval,
  approved,
  rejectedNeedsRework,
}

class RemedialPhoto {
  final String id;
  final String projectId;
  final String doorId;
  final String remedialItemId;
  final String issueId;
  final String type;
  final String fileName;
  final String mimeType;
  final List<int> bytes;
  final DateTime createdAt;

  RemedialPhoto({
    String? id,
    required this.projectId,
    required this.doorId,
    required this.remedialItemId,
    required this.issueId,
    this.type = 'afterRepair',
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();
}

class Approval {
  final String id;
  final String projectId;
  final String doorId;
  final String moduleType;
  final String approvedBy;
  final DateTime approvedDate;
  final String decision;
  final String comment;
  final bool? maintenanceLabelFitted;
  final DateTime? nextMaintenanceDueDate;
  final String finalManagerComments;
  final String signatureAssetPath;
  final String signatureMethod;
  final String signatureInitials;
  final List<int> signatureImageBytes;
  final String approvedMaintainerName;
  final String approvedMaintainerNumber;
  final String certificateJobReferenceOverride;

  Approval({
    String? id,
    required this.projectId,
    required this.doorId,
    this.moduleType = 'remedial',
    required this.approvedBy,
    DateTime? approvedDate,
    required this.decision,
    this.comment = '',
    this.maintenanceLabelFitted,
    this.nextMaintenanceDueDate,
    this.finalManagerComments = '',
    this.signatureAssetPath = '',
    this.signatureMethod = 'asset',
    this.signatureInitials = '',
    this.signatureImageBytes = const [],
    this.approvedMaintainerName = '',
    this.approvedMaintainerNumber = '',
    this.certificateJobReferenceOverride = '',
  })  : id = id ?? _uuid.v4(),
        approvedDate = approvedDate ?? DateTime.now();
}

class RemedialItem {
  final String id;
  final String projectId;
  final String doorId;
  final String issueId;
  final String category;
  final String title;
  final String severity;
  final String originalComment;
  final List<PhotoAttachment> originalInspectionPhotos;
  final String recommendedAction;
  final List<Map<String, String?>> actionMappings;
  final RemedialStatus status;
  final String workerNote;
  final String completedBy;
  final DateTime? completedDate;
  final String submittedBy;
  final DateTime? submittedAt;
  final String approvedBy;
  final DateTime? approvedAt;
  final String rejectedBy;
  final DateTime? rejectedAt;
  final String rejectionNote;
  final List<RemedialPhoto> afterRepairPhotos;
  final List<RemedialPhoto> managerApprovalPhotos;
  final List<RemedialPhoto> managerRejectionPhotos;
  final Approval? approval;
  final String managerRejectionNote;

  const RemedialItem({
    required this.id,
    required this.projectId,
    required this.doorId,
    required this.issueId,
    required this.category,
    required this.title,
    required this.severity,
    required this.originalComment,
    required this.originalInspectionPhotos,
    required this.recommendedAction,
    this.actionMappings = const [],
    this.status = RemedialStatus.pending,
    this.workerNote = '',
    this.completedBy = '',
    this.completedDate,
    this.submittedBy = '',
    this.submittedAt,
    this.approvedBy = '',
    this.approvedAt,
    this.rejectedBy = '',
    this.rejectedAt,
    this.rejectionNote = '',
    this.afterRepairPhotos = const [],
    this.managerApprovalPhotos = const [],
    this.managerRejectionPhotos = const [],
    this.approval,
    this.managerRejectionNote = '',
  });

  RemedialItem copyWith({
    String? category,
    String? title,
    String? severity,
    String? originalComment,
    List<PhotoAttachment>? originalInspectionPhotos,
    String? recommendedAction,
    List<Map<String, String?>>? actionMappings,
    RemedialStatus? status,
    String? workerNote,
    String? completedBy,
    DateTime? completedDate,
    bool clearCompletedDate = false,
    String? submittedBy,
    DateTime? submittedAt,
    bool clearSubmittedAt = false,
    String? approvedBy,
    DateTime? approvedAt,
    bool clearApprovedAt = false,
    String? rejectedBy,
    DateTime? rejectedAt,
    bool clearRejectedAt = false,
    String? rejectionNote,
    List<RemedialPhoto>? afterRepairPhotos,
    List<RemedialPhoto>? managerApprovalPhotos,
    List<RemedialPhoto>? managerRejectionPhotos,
    Approval? approval,
    bool clearApproval = false,
    String? managerRejectionNote,
  }) {
    return RemedialItem(
      id: id,
      projectId: projectId,
      doorId: doorId,
      issueId: issueId,
      category: category ?? this.category,
      title: title ?? this.title,
      severity: severity ?? this.severity,
      originalComment: originalComment ?? this.originalComment,
      originalInspectionPhotos:
          originalInspectionPhotos ?? this.originalInspectionPhotos,
      recommendedAction: recommendedAction ?? this.recommendedAction,
      actionMappings: actionMappings ?? this.actionMappings,
      status: status ?? this.status,
      workerNote: workerNote ?? this.workerNote,
      completedBy: completedBy ?? this.completedBy,
      completedDate:
          clearCompletedDate ? null : (completedDate ?? this.completedDate),
      submittedBy: submittedBy ?? this.submittedBy,
      submittedAt: clearSubmittedAt ? null : (submittedAt ?? this.submittedAt),
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: clearApprovedAt ? null : (approvedAt ?? this.approvedAt),
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectedAt: clearRejectedAt ? null : (rejectedAt ?? this.rejectedAt),
      rejectionNote: rejectionNote ?? this.rejectionNote,
      afterRepairPhotos: afterRepairPhotos ?? this.afterRepairPhotos,
      managerApprovalPhotos:
          managerApprovalPhotos ?? this.managerApprovalPhotos,
      managerRejectionPhotos:
          managerRejectionPhotos ?? this.managerRejectionPhotos,
      approval: clearApproval ? null : (approval ?? this.approval),
      managerRejectionNote: managerRejectionNote ?? this.managerRejectionNote,
    );
  }
}

class Issue {
  final String id;
  final int artCode;
  final String comment;
  final List<Map<String, String?>> actionMappings;

  final IssueSeverity severity;

  final double? gapLeftMm;
  final double? gapRightMm;
  final double? gapTopMm;
  final double? gapBottomMm;
  final double? gapMeetingMm;

  final List<PhotoAttachment> photos;

  /// Link to the inspection check that generated this issue.
  /// Example: "CHECK:doorGapsIncorrect"
  final String? sourceKey;

  Issue({
    String? id,
    required this.artCode,
    required this.comment,
    this.actionMappings = const [],
    this.severity = IssueSeverity.fail,
    this.gapLeftMm,
    this.gapRightMm,
    this.gapTopMm,
    this.gapBottomMm,
    this.gapMeetingMm,
    List<PhotoAttachment>? photos,
    this.sourceKey,
  })  : id = id ?? _uuid.v4(),
        photos = photos ?? [];
}

enum InspectionOutcome {
  notAnswered,
  pass,
  advisory,
  fail,
  criticalFail,
  notApplicable,
}

String inspectionOutcomeLabel(InspectionOutcome o) {
  switch (o) {
    case InspectionOutcome.notAnswered:
      return 'Not answered';
    case InspectionOutcome.pass:
      return 'Pass';
    case InspectionOutcome.advisory:
      return 'Advisory';
    case InspectionOutcome.fail:
      return 'Fail';
    case InspectionOutcome.criticalFail:
      return 'Critical Fail';
    case InspectionOutcome.notApplicable:
      return 'N/A';
  }
}

class InspectionCheckResult {
  final InspectionOutcome outcome;
  final String comment;

  /// The human-readable recommended action text.
  /// Generated by [buildRecommendedActionText] and/or manually edited.
  final String recommendedAction;

  final List<PhotoAttachment> photos;

  // Gap measurements (mm) for ART04
  final double? gapTopMm;
  final double? gapBottomMm;
  final double? gapLeftMm;
  final double? gapRightMm;
  final double? gapMeetingMm;

  // ── Structured action storage (ART multi-select) ──────────
  /// ART sub-codes selected by inspector, e.g. ['ART04a', 'ART04b'].
  final List<String> selectedActionCodes;

  /// Structured selection metadata used for correct ART exports.
  /// Each entry holds: selectedLabel, uiCode, actualArtCode.
  final List<Map<String, String?>> selectedActionMappings;

  /// Custom free-text entered via the "Other (custom)" option.
  final String customActionText;

  /// Optional video path (used for door-closer check).
  final String optionalVideoPath;

  const InspectionCheckResult({
    required this.outcome,
    this.comment = '',
    this.recommendedAction = '',
    this.photos = const [],
    this.gapTopMm,
    this.gapBottomMm,
    this.gapLeftMm,
    this.gapRightMm,
    this.gapMeetingMm,
    this.selectedActionCodes = const [],
    this.selectedActionMappings = const [],
    this.customActionText = '',
    this.optionalVideoPath = '',
  });

  InspectionCheckResult copyWith({
    InspectionOutcome? outcome,
    String? comment,
    String? recommendedAction,
    List<PhotoAttachment>? photos,
    double? gapTopMm,
    double? gapBottomMm,
    double? gapLeftMm,
    double? gapRightMm,
    double? gapMeetingMm,
    bool clearGaps = false,
    List<String>? selectedActionCodes,
    List<Map<String, String?>>? selectedActionMappings,
    String? customActionText,
    String? optionalVideoPath,
  }) {
    return InspectionCheckResult(
      outcome: outcome ?? this.outcome,
      comment: comment ?? this.comment,
      recommendedAction: recommendedAction ?? this.recommendedAction,
      photos: photos ?? this.photos,
      gapTopMm: clearGaps ? null : (gapTopMm ?? this.gapTopMm),
      gapBottomMm: clearGaps ? null : (gapBottomMm ?? this.gapBottomMm),
      gapLeftMm: clearGaps ? null : (gapLeftMm ?? this.gapLeftMm),
      gapRightMm: clearGaps ? null : (gapRightMm ?? this.gapRightMm),
      gapMeetingMm: clearGaps ? null : (gapMeetingMm ?? this.gapMeetingMm),
      selectedActionCodes: selectedActionCodes ?? this.selectedActionCodes,
      selectedActionMappings:
          selectedActionMappings ?? this.selectedActionMappings,
      customActionText: customActionText ?? this.customActionText,
      optionalVideoPath: optionalVideoPath ?? this.optionalVideoPath,
    );
  }
}

class FireStoppingDefect {
  final String id;
  final String template;
  final String fireRating;
  final String serviceType;
  final String description;
  final String recommendedAction;
  final String lengthMm;
  final String widthMm;
  final String drawingId;
  final String pinId;
  final List<PhotoAttachment> photos;

  const FireStoppingDefect({
    required this.id,
    this.template = '',
    this.fireRating = '',
    this.serviceType = '',
    this.description = '',
    this.recommendedAction = '',
    this.lengthMm = '',
    this.widthMm = '',
    this.drawingId = '',
    this.pinId = '',
    this.photos = const [],
  });

  FireStoppingDefect copyWith({
    String? template,
    String? fireRating,
    String? serviceType,
    String? description,
    String? recommendedAction,
    String? lengthMm,
    String? widthMm,
    String? drawingId,
    String? pinId,
    List<PhotoAttachment>? photos,
  }) {
    return FireStoppingDefect(
      id: id,
      template: template ?? this.template,
      fireRating: fireRating ?? this.fireRating,
      serviceType: serviceType ?? this.serviceType,
      description: description ?? this.description,
      recommendedAction: recommendedAction ?? this.recommendedAction,
      lengthMm: lengthMm ?? this.lengthMm,
      widthMm: widthMm ?? this.widthMm,
      drawingId: drawingId ?? this.drawingId,
      pinId: pinId ?? this.pinId,
      photos: photos ?? this.photos,
    );
  }
}

class Door {
  final String id;
  final int number;
  final DateTime inspectionDate;

  final String doorIdTag;
  final String floor;
  final String area;

  final DoorType doorType;
  final DoorFunction doorFunction;
  final DoorMaterial material;
  final String customMaterial;

  /// Certification status
  final DoorClassification classification;
  final String certificationBodyName;

  final FireRating fireRating;

  /// Evidence level / Compliance evidence
  final GradingLevel gradingLevel;

  final DoorConfiguration configuration;

  /// If false, hide glazing section in inspection UI.
  final bool hasGlazing;

  final bool isFireExit;

  final DoorResult result;
  final RemedialStatus remedialStatus;

  final List<PhotoAttachment> doorPhotos;
  final List<Issue> issues;
  final List<RemedialItem> remedialItems;

  /// Key: InspectionCheckId.name
  final Map<String, InspectionCheckResult> inspectionResults;

  // ── Inspection approval ──────────────────────────────────────────────────
  final String approvedMaintainerName;
  final String approvedMaintainerNumber;
  final String approvedBy;
  final DateTime? approvedAt;
  final int maintenanceIntervalMonths;

  // Module-agnostic drawing pin link (used by fire door and snagging, and as
  // fallback for fire stopping where needed).
  final String doorDrawingId;
  final String doorPinId;

  // Fire Stopping item-specific structure (kept separate from fire-door fields).
  final String fireStoppingItemType;
  final String fireStoppingFireRating;
  final String fireStoppingServiceType;
  final String fireStoppingSize;
  final int fireStoppingQuantity;
  final String fireStoppingDefectDescription;
  final String fireStoppingRecommendedAction;
  final String fireStoppingVideoUrl;
  final List<FireStoppingDefect> fireStoppingDefects;

  // ── Door set replacement (Fire Door specific) ────────────────────────────
  /// If true, marks this door for full replacement + auto-fails inspection.
  final bool replacementRequired;
  final String replacementDoor1Width;
  final String replacementDoor1Height;
  final String replacementDoor2Width;
  final String replacementDoor2Height;

  Door({
    String? id,
    required this.number,
    DateTime? inspectionDate,
    this.doorIdTag = '',
    this.floor = '',
    this.area = '',
    this.doorType = DoorType.other,
    this.doorFunction = DoorFunction.unknown,
    this.material = DoorMaterial.unknown,
    this.customMaterial = '',
    this.classification = DoorClassification.unknownNotVerified,
    this.certificationBodyName = '',
    this.fireRating = FireRating.unknown,
    this.gradingLevel = GradingLevel.level4,
    this.configuration = DoorConfiguration.singleLeaf,
    this.hasGlazing = false,
    this.isFireExit = false,
    this.result = DoorResult.unknown,
    this.remedialStatus = RemedialStatus.pending,
    this.approvedMaintainerName = '',
    this.approvedMaintainerNumber = '',
    this.approvedBy = '',
    this.approvedAt,
    int? maintenanceIntervalMonths,
    this.doorDrawingId = '',
    this.doorPinId = '',
    this.fireStoppingItemType = '',
    this.fireStoppingFireRating = '',
    this.fireStoppingServiceType = '',
    this.fireStoppingSize = '',
    this.fireStoppingQuantity = 1,
    this.fireStoppingDefectDescription = '',
    this.fireStoppingRecommendedAction = '',
    this.fireStoppingVideoUrl = '',
    this.fireStoppingDefects = const [],
    this.replacementRequired = false,
    this.replacementDoor1Width = '',
    this.replacementDoor1Height = '',
    this.replacementDoor2Width = '',
    this.replacementDoor2Height = '',
    List<PhotoAttachment>? doorPhotos,
    List<Issue>? issues,
    List<RemedialItem>? remedialItems,
    Map<String, InspectionCheckResult>? inspectionResults,
  })  : id = id ?? _uuid.v4(),
        inspectionDate = inspectionDate ?? DateTime.now(),
        maintenanceIntervalMonths = (maintenanceIntervalMonths == null ||
                maintenanceIntervalMonths <= 0)
            ? 12
            : maintenanceIntervalMonths,
        doorPhotos = doorPhotos ?? [],
        issues = issues ?? [],
        remedialItems = remedialItems ?? [],
        inspectionResults = inspectionResults ?? const {};

  Door copyWith({
    DateTime? inspectionDate,
    String? doorIdTag,
    String? floor,
    String? area,
    DoorType? doorType,
    DoorFunction? doorFunction,
    DoorMaterial? material,
    String? customMaterial,
    DoorClassification? classification,
    String? certificationBodyName,
    FireRating? fireRating,
    GradingLevel? gradingLevel,
    DoorConfiguration? configuration,
    bool? hasGlazing,
    bool? isFireExit,
    DoorResult? result,
    RemedialStatus? remedialStatus,
    String? approvedMaintainerName,
    String? approvedMaintainerNumber,
    String? approvedBy,
    DateTime? approvedAt,
    int? maintenanceIntervalMonths,
    String? doorDrawingId,
    String? doorPinId,
    String? fireStoppingItemType,
    String? fireStoppingFireRating,
    String? fireStoppingServiceType,
    String? fireStoppingSize,
    int? fireStoppingQuantity,
    String? fireStoppingDefectDescription,
    String? fireStoppingRecommendedAction,
    String? fireStoppingVideoUrl,
    List<FireStoppingDefect>? fireStoppingDefects,
    bool? replacementRequired,
    String? replacementDoor1Width,
    String? replacementDoor1Height,
    String? replacementDoor2Width,
    String? replacementDoor2Height,
    bool clearApprovedAt = false,
    List<PhotoAttachment>? doorPhotos,
    List<Issue>? issues,
    List<RemedialItem>? remedialItems,
    Map<String, InspectionCheckResult>? inspectionResults,
  }) {
    return Door(
      id: id,
      number: number,
      inspectionDate: inspectionDate ?? this.inspectionDate,
      doorIdTag: doorIdTag ?? this.doorIdTag,
      floor: floor ?? this.floor,
      area: area ?? this.area,
      doorType: doorType ?? this.doorType,
      doorFunction: doorFunction ?? this.doorFunction,
      material: material ?? this.material,
      customMaterial: customMaterial ?? this.customMaterial,
      classification: classification ?? this.classification,
      certificationBodyName:
          certificationBodyName ?? this.certificationBodyName,
      fireRating: fireRating ?? this.fireRating,
      gradingLevel: gradingLevel ?? this.gradingLevel,
      configuration: configuration ?? this.configuration,
      hasGlazing: hasGlazing ?? this.hasGlazing,
      isFireExit: isFireExit ?? this.isFireExit,
      result: result ?? this.result,
      remedialStatus: remedialStatus ?? this.remedialStatus,
      approvedMaintainerName:
          approvedMaintainerName ?? this.approvedMaintainerName,
      approvedMaintainerNumber:
          approvedMaintainerNumber ?? this.approvedMaintainerNumber,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: clearApprovedAt ? null : (approvedAt ?? this.approvedAt),
      maintenanceIntervalMonths:
          maintenanceIntervalMonths ?? this.maintenanceIntervalMonths,
      doorDrawingId: doorDrawingId ?? this.doorDrawingId,
      doorPinId: doorPinId ?? this.doorPinId,
      fireStoppingItemType: fireStoppingItemType ?? this.fireStoppingItemType,
      fireStoppingFireRating:
          fireStoppingFireRating ?? this.fireStoppingFireRating,
      fireStoppingServiceType:
          fireStoppingServiceType ?? this.fireStoppingServiceType,
      fireStoppingSize: fireStoppingSize ?? this.fireStoppingSize,
      fireStoppingQuantity: fireStoppingQuantity ?? this.fireStoppingQuantity,
      fireStoppingDefectDescription:
          fireStoppingDefectDescription ?? this.fireStoppingDefectDescription,
      fireStoppingRecommendedAction:
          fireStoppingRecommendedAction ?? this.fireStoppingRecommendedAction,
      fireStoppingVideoUrl: fireStoppingVideoUrl ?? this.fireStoppingVideoUrl,
      fireStoppingDefects: fireStoppingDefects ?? this.fireStoppingDefects,
      replacementRequired: replacementRequired ?? this.replacementRequired,
      replacementDoor1Width:
          replacementDoor1Width ?? this.replacementDoor1Width,
      replacementDoor1Height:
          replacementDoor1Height ?? this.replacementDoor1Height,
      replacementDoor2Width:
          replacementDoor2Width ?? this.replacementDoor2Width,
      replacementDoor2Height:
          replacementDoor2Height ?? this.replacementDoor2Height,
      doorPhotos: doorPhotos ?? this.doorPhotos,
      issues: issues ?? this.issues,
      remedialItems: remedialItems ?? this.remedialItems,
      inspectionResults: inspectionResults ?? this.inspectionResults,
    );
  }
}
