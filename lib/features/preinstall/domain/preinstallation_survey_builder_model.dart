import '../../surveys/domain/models.dart';

enum BuilderDoorType { single, doubleLeaf }

enum BuilderFrameMode { doorOnly, doorAndFrame }

enum BuilderVisionPanel {
  none,
  top,
  narrowVertical,
  halfHeight,
  fullHeight,
  lowGrille,
  highGrille,
  glazingLowGrille,
  fullGlazed,
  custom,
}

enum BuilderFinishType { primer, painted, veneer, laminate }

class PreInstallationSurveyBuilderData {
  final String doorRef;
  final String level;
  final String location;
  final String doorDrawingId;
  final String doorPinId;

  final BuilderDoorType doorType;
  final BuilderFrameMode frameMode;
  final bool isExternal;

  final BuilderVisionPanel visionPanel;
  final String customGlazingNote;
  final bool sidePanelLeft;
  final bool sidePanelRight;
  final bool overPanel;
  final double? sidePanelOpeningWidth;
  final double? overPanelOpeningHeight;

  final String fireRating;

  final double? openingWidth;
  final double? openingHeight;
  final double? leafWidth;
  final double? leafHeight;
  final double? leafThickness;
  final double? frameWidth;
  final double? frameHeight;

  final bool closer;
  final String lockType;
  final String customLockType;
  final List<String> handles;
  final String hingesSide;

  final bool letterPlate;
  final bool spyhole;
  final bool ventilationGrille;
  final bool dropDownSeal;
  final bool signage;
  final String signageText;
  final bool doorNumberPlaque;
  final String plaqueText;

  final String colour;
  final BuilderFinishType finishType;
  final String notes;
  final List<PreInstallPhoto> photos;
  final String sealType; // 'none' | 'intumescent' | 'smoke' | 'combined'
  final String sealPosition; // 'inFrame' | 'onDoor' | 'other'
  final String sealNote;
  final PreInstallSupplyResponsibility supplyResponsibility;
  final String customSupplyResponsibility;

  const PreInstallationSurveyBuilderData({
    this.doorRef = '',
    this.level = '',
    this.location = '',
    this.doorDrawingId = '',
    this.doorPinId = '',
    this.doorType = BuilderDoorType.single,
    this.frameMode = BuilderFrameMode.doorAndFrame,
    this.isExternal = false,
    this.visionPanel = BuilderVisionPanel.none,
    this.customGlazingNote = '',
    this.sidePanelLeft = false,
    this.sidePanelRight = false,
    this.overPanel = false,
    this.sidePanelOpeningWidth,
    this.overPanelOpeningHeight,
    this.fireRating = 'FD30',
    this.openingWidth,
    this.openingHeight,
    this.leafWidth,
    this.leafHeight,
    this.leafThickness,
    this.frameWidth,
    this.frameHeight,
    this.closer = false,
    this.lockType = 'none',
    this.customLockType = '',
    this.handles = const [],
    this.hingesSide = 'left',
    this.letterPlate = false,
    this.spyhole = false,
    this.ventilationGrille = false,
    this.dropDownSeal = false,
    this.signage = false,
    this.signageText = '',
    this.doorNumberPlaque = false,
    this.plaqueText = '',
    this.colour = '',
    this.finishType = BuilderFinishType.primer,
    this.notes = '',
    this.photos = const [],
    this.sealType = 'none',
    this.sealPosition = 'inFrame',
    this.sealNote = '',
    this.supplyResponsibility =
        PreInstallSupplyResponsibility.bw_supply_install,
    this.customSupplyResponsibility = '',
  });

  PreInstallationSurveyBuilderData copyWith({
    String? doorRef,
    String? level,
    String? location,
    String? doorDrawingId,
    String? doorPinId,
    BuilderDoorType? doorType,
    BuilderFrameMode? frameMode,
    bool? isExternal,
    BuilderVisionPanel? visionPanel,
    String? customGlazingNote,
    bool? sidePanelLeft,
    bool? sidePanelRight,
    bool? overPanel,
    double? sidePanelOpeningWidth,
    bool clearSidePanelOpeningWidth = false,
    double? overPanelOpeningHeight,
    bool clearOverPanelOpeningHeight = false,
    String? fireRating,
    double? openingWidth,
    double? openingHeight,
    double? leafWidth,
    double? leafHeight,
    double? leafThickness,
    double? frameWidth,
    bool clearFrameWidth = false,
    double? frameHeight,
    bool clearFrameHeight = false,
    bool? closer,
    String? lockType,
    String? customLockType,
    List<String>? handles,
    String? hingesSide,
    bool? letterPlate,
    bool? spyhole,
    bool? ventilationGrille,
    bool? dropDownSeal,
    bool? signage,
    String? signageText,
    bool? doorNumberPlaque,
    String? plaqueText,
    String? colour,
    BuilderFinishType? finishType,
    String? notes,
    List<PreInstallPhoto>? photos,
    String? sealType,
    String? sealPosition,
    String? sealNote,
    PreInstallSupplyResponsibility? supplyResponsibility,
    String? customSupplyResponsibility,
  }) {
    return PreInstallationSurveyBuilderData(
      doorRef: doorRef ?? this.doorRef,
      level: level ?? this.level,
      location: location ?? this.location,
      doorDrawingId: doorDrawingId ?? this.doorDrawingId,
      doorPinId: doorPinId ?? this.doorPinId,
      doorType: doorType ?? this.doorType,
      frameMode: frameMode ?? this.frameMode,
      isExternal: isExternal ?? this.isExternal,
      visionPanel: visionPanel ?? this.visionPanel,
      customGlazingNote: customGlazingNote ?? this.customGlazingNote,
      sidePanelLeft: sidePanelLeft ?? this.sidePanelLeft,
      sidePanelRight: sidePanelRight ?? this.sidePanelRight,
      overPanel: overPanel ?? this.overPanel,
      sidePanelOpeningWidth: clearSidePanelOpeningWidth
          ? null
          : (sidePanelOpeningWidth ?? this.sidePanelOpeningWidth),
      overPanelOpeningHeight: clearOverPanelOpeningHeight
          ? null
          : (overPanelOpeningHeight ?? this.overPanelOpeningHeight),
      fireRating: fireRating ?? this.fireRating,
      openingWidth: openingWidth ?? this.openingWidth,
      openingHeight: openingHeight ?? this.openingHeight,
      leafWidth: leafWidth ?? this.leafWidth,
      leafHeight: leafHeight ?? this.leafHeight,
      leafThickness: leafThickness ?? this.leafThickness,
      frameWidth: clearFrameWidth ? null : (frameWidth ?? this.frameWidth),
      frameHeight: clearFrameHeight ? null : (frameHeight ?? this.frameHeight),
      closer: closer ?? this.closer,
      lockType: lockType ?? this.lockType,
      customLockType: customLockType ?? this.customLockType,
      handles: handles ?? this.handles,
      hingesSide: hingesSide ?? this.hingesSide,
      letterPlate: letterPlate ?? this.letterPlate,
      spyhole: spyhole ?? this.spyhole,
      ventilationGrille: ventilationGrille ?? this.ventilationGrille,
      dropDownSeal: dropDownSeal ?? this.dropDownSeal,
      signage: signage ?? this.signage,
      signageText: signageText ?? this.signageText,
      doorNumberPlaque: doorNumberPlaque ?? this.doorNumberPlaque,
      plaqueText: plaqueText ?? this.plaqueText,
      colour: colour ?? this.colour,
      finishType: finishType ?? this.finishType,
      notes: notes ?? this.notes,
      photos: photos ?? this.photos,
      sealType: sealType ?? this.sealType,
      sealPosition: sealPosition ?? this.sealPosition,
      sealNote: sealNote ?? this.sealNote,
      supplyResponsibility: supplyResponsibility ?? this.supplyResponsibility,
      customSupplyResponsibility:
          customSupplyResponsibility ?? this.customSupplyResponsibility,
    );
  }
}
