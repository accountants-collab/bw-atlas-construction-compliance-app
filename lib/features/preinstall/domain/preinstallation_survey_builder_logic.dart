import '../../surveys/domain/models.dart';
import 'preinstallation_survey_builder_model.dart';

class PreInstallationSurveyBuilderLogic {
  static const supportedFireRatings = ['FD30', 'FD60', 'FD90', 'FD120'];
  static const lockTypeOptions = [
    'none',
    'mortice',
    'sashlock',
    'deadlock',
    'multipoint',
    'custom'
  ];
  static const handleOptions = ['lever', 'pull', 'knob'];
  static const signageOptions = ['fireKeepShut', 'fireKeepLocked', 'custom'];

  static PreInstallationSurveyBuilderData fromItem(PreInstallItem item) {
    final featureMap = {for (final f in item.features) f.type: f};
    final measurements = item.measurements;
    return PreInstallationSurveyBuilderData(
      doorRef: item.doorRef,
      level: item.level,
      location: item.location,
      doorDrawingId: item.doorDrawingId,
      doorPinId: item.doorPinId,
      doorType: item.configuration.contains('double')
          ? BuilderDoorType.doubleLeaf
          : BuilderDoorType.single,
      frameMode: item.hasFrame
          ? BuilderFrameMode.doorAndFrame
          : BuilderFrameMode.doorOnly,
      isExternal: item.doorPurpose.toLowerCase().contains('external'),
      visionPanel: _visionFromStored(item.glazingType),
      customGlazingNote: item.glazingDetails,
      sidePanelLeft: item.configuration.contains('side'),
      sidePanelRight: false,
      overPanel: item.configuration.contains('over'),
      sidePanelOpeningWidth: _toDoubleOrNull(item.openingWidth),
      overPanelOpeningHeight: _toDoubleOrNull(item.openingHeight),
      fireRating: supportedFireRatings.contains(item.fireRating)
          ? item.fireRating
          : 'FD30',
      openingWidth: measurements?.openingWidthMiddle,
      openingHeight: measurements?.openingHeightCentre,
      leafWidth: measurements?.leafWidth,
      leafHeight: measurements?.leafHeight,
      leafThickness: measurements?.leafThickness,
      frameWidth: measurements?.frameWidth,
      frameHeight: measurements?.frameHeight,
      closer: item.closer.trim().isNotEmpty && item.closer != 'none',
      lockType: lockTypeOptions.contains(item.lockLatchType)
          ? item.lockLatchType
          : (item.lockLatchType.isEmpty ? 'none' : 'custom'),
      customLockType: lockTypeOptions.contains(item.lockLatchType)
          ? ''
          : item.lockLatchType,
      handles: [
        if (featureMap['leverHandle']?.selected ?? false) 'lever',
        if (featureMap['pullHandle']?.selected ?? false) 'pull',
        if (featureMap['knob']?.selected ?? false) 'knob',
      ],
      hingesSide: item.handingMode.contains('right') ? 'right' : 'left',
      letterPlate: featureMap['letterPlate']?.selected ?? false,
      spyhole: featureMap['spyhole']?.selected ?? false,
      ventilationGrille: featureMap['ventilationGrille']?.selected ??
          item.ventilationGrilleEnabled,
      dropDownSeal: featureMap['dropSeal']?.selected ?? false,
      signage: (featureMap['signage']?.selected ?? false) ||
          (item.signage.isNotEmpty && item.signage != 'none'),
      signageText:
          item.signage == 'Custom signage' ? item.customSignage : item.signage,
      doorNumberPlaque: featureMap['doorNumber']?.selected ?? false,
      plaqueText: featureMap['doorNumber']?.value ?? '',
      colour: item.colourRal,
      finishType: _finishFromStored(item.finishType),
      notes: item.manufactureNotes.isNotEmpty
          ? item.manufactureNotes
          : item.preInstallComments,
      photos: item.preInstallPhotos,
      sealType: _sealTypeFromStored(item.seals),
      sealPosition: _sealPositionFromStored(item.seals),
      sealNote: _sealNoteFromStored(item.seals),
      supplyResponsibility: item.supplyResponsibility,
      customSupplyResponsibility: item.customSupplyResponsibility,
    );
  }

  static PreInstallItem toItem({
    required PreInstallItem current,
    required PreInstallationSurveyBuilderData data,
  }) {
    final updatedFeatures = _applyFeatures(current.features, data);
    final updatedMeasurements =
        (current.measurements ?? DoorMeasurementSet(id: current.id)).copyWith(
      openingWidthTop: data.openingWidth,
      openingWidthMiddle: data.openingWidth,
      openingWidthBottom: data.openingWidth,
      openingHeightLeft: data.openingHeight,
      openingHeightCentre: data.openingHeight,
      openingHeightRight: data.openingHeight,
      leafWidth:
          data.frameMode == BuilderFrameMode.doorOnly ? data.leafWidth : null,
      leafHeight:
          data.frameMode == BuilderFrameMode.doorOnly ? data.leafHeight : null,
      leafThickness: data.leafThickness,
      frameWidth: data.frameMode == BuilderFrameMode.doorAndFrame
          ? data.frameWidth
          : null,
      frameHeight: data.frameMode == BuilderFrameMode.doorAndFrame
          ? data.frameHeight
          : null,
    );

    final lockValue =
        data.lockType == 'custom' ? data.customLockType.trim() : data.lockType;

    return current.copyWith(
      doorRef: data.doorRef,
      level: data.level,
      location: data.location,
      doorDrawingId: data.doorDrawingId,
      doorPinId: data.doorPinId,
      doorPurpose: data.isExternal ? 'external' : 'internal',
      hasFrame: data.frameMode == BuilderFrameMode.doorAndFrame,
      configuration: _configurationFromBuilder(data),
      doorType: data.doorType == BuilderDoorType.doubleLeaf
          ? 'doubleLeaf'
          : 'singleLeaf',
      handingMode:
          data.hingesSide == 'right' ? 'hingesRightIn' : 'hingesLeftIn',
      fireRating: data.fireRating,
      glazingType: _visionToStored(data.visionPanel),
      glazing: _visionToStored(data.visionPanel),
      glazingDetails: data.customGlazingNote,
      openingWidth: data.openingWidth?.toString() ?? '',
      openingHeight: data.openingHeight?.toString() ?? '',
      lockLatchType: lockValue,
      closer: data.closer ? 'doorCloser' : 'none',
      signage: data.signage
          ? (data.signageText.trim().isEmpty
              ? 'Fire Door Keep Shut'
              : data.signageText.trim())
          : 'none',
      customSignage: data.signage ? data.signageText.trim() : '',
      finishType: _finishToStored(data.finishType),
      colourRal: data.colour,
      manufactureNotes: data.notes,
      preInstallComments: data.notes,
      features: updatedFeatures,
      hardware: _hardwareFromBuilder(data),
      measurements: updatedMeasurements,
      preInstallPhotos: data.photos,
      ventilationGrilleEnabled: data.ventilationGrille,
      seals: _sealString(data),
      supplyResponsibility: data.supplyResponsibility,
      customSupplyResponsibility: data.customSupplyResponsibility,
    );
  }

  static List<String> validate(
    PreInstallationSurveyBuilderData data, {
    required PreInstallSurveyType surveyType,
  }) {
    final errors = <String>[];
    final isInstallationOnly =
        surveyType == PreInstallSurveyType.installation_only;
    if (!isInstallationOnly && data.fireRating.trim().isEmpty) {
      errors.add('Fire rating is required.');
    }
    if (!isInstallationOnly) {
      if (data.frameMode == BuilderFrameMode.doorOnly) {
        if (data.leafWidth == null || data.leafWidth! <= 0) {
          errors.add('Door leaf width is mandatory for Door Only.');
        }
        if (data.leafHeight == null || data.leafHeight! <= 0) {
          errors.add('Door leaf height is mandatory for Door Only.');
        }
      }
      if (data.frameMode == BuilderFrameMode.doorAndFrame) {
        if (data.frameWidth == null || data.frameWidth! <= 0) {
          errors.add(
              'Overall frame width is mandatory when Door + Frame is selected.');
        }
        if (data.frameHeight == null || data.frameHeight! <= 0) {
          errors.add(
              'Overall frame height is mandatory when Door + Frame is selected.');
        }
      }
      if ((data.sidePanelLeft || data.sidePanelRight) &&
          (data.sidePanelOpeningWidth == null ||
              data.sidePanelOpeningWidth! <= 0)) {
        errors.add('Opening width for side panel is required.');
      }
      if (data.overPanel &&
          (data.overPanelOpeningHeight == null ||
              data.overPanelOpeningHeight! <= 0)) {
        errors.add('Opening height for over panel is required.');
      }
    }
    if (data.lockType == 'custom' && data.customLockType.trim().isEmpty) {
      errors.add('Custom lock type is required.');
    }
    return errors;
  }

  static List<DoorFeatureItem> _applyFeatures(
      List<DoorFeatureItem> existing, PreInstallationSurveyBuilderData data) {
    var out = [...existing];
    out = _setFeature(out, 'letterPlate', data.letterPlate);
    out = _setFeature(out, 'spyhole', data.spyhole);
    out = _setFeature(out, 'ventilationGrille', data.ventilationGrille);
    out = _setFeature(out, 'dropSeal', data.dropDownSeal);
    out = _setFeature(out, 'signage', data.signage, value: data.signageText);
    out = _setFeature(out, 'doorNumber', data.doorNumberPlaque,
        value: data.plaqueText);
    out = _setFeature(out, 'leverHandle', data.handles.contains('lever'));
    out = _setFeature(out, 'pullHandle', data.handles.contains('pull'));
    out = _setFeature(out, 'knob', data.handles.contains('knob'));
    return out;
  }

  static List<DoorFeatureItem> _setFeature(
      List<DoorFeatureItem> source, String type, bool selected,
      {String? value}) {
    var found = false;
    final next = source.map((f) {
      if (f.type != type) return f;
      found = true;
      return f.copyWith(selected: selected, value: value);
    }).toList();
    if (!found) {
      next.add(
        DoorFeatureItem(
          id: '${type}_${DateTime.now().millisecondsSinceEpoch}',
          type: type,
          selected: selected,
          value: value ?? '',
        ),
      );
    }
    return next;
  }

  static BuilderVisionPanel _visionFromStored(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'none':
      case 'blank':
        return BuilderVisionPanel.none;
      case 'top':
      case 'smalltop':
      case 'small_top':
      case 'small_top_vision_panel':
        return BuilderVisionPanel.top;
      case 'left':
      case 'right':
      case 'narrow_vertical':
      case 'narrowvertical':
        return BuilderVisionPanel.narrowVertical;
      case 'half_height':
      case 'halfheight':
        return BuilderVisionPanel.halfHeight;
      case 'full':
      case 'full_height':
      case 'fullheight':
        return BuilderVisionPanel.fullHeight;
      case 'low_grille':
      case 'lowgrille':
        return BuilderVisionPanel.lowGrille;
      case 'high_grille':
      case 'highgrille':
        return BuilderVisionPanel.highGrille;
      case 'glazing_low_grille':
      case 'glazinglowgrille':
        return BuilderVisionPanel.glazingLowGrille;
      case 'fullglazedleaf':
      case 'full_glazed':
        return BuilderVisionPanel.fullGlazed;
      case 'custom':
        return BuilderVisionPanel.custom;
      default:
        return BuilderVisionPanel.none;
    }
  }

  static String _visionToStored(BuilderVisionPanel value) {
    switch (value) {
      case BuilderVisionPanel.none:
        return 'none';
      case BuilderVisionPanel.top:
        return 'small_top_vision_panel';
      case BuilderVisionPanel.narrowVertical:
        return 'narrow_vertical';
      case BuilderVisionPanel.halfHeight:
        return 'half_height';
      case BuilderVisionPanel.fullHeight:
        return 'full_height';
      case BuilderVisionPanel.lowGrille:
        return 'low_grille';
      case BuilderVisionPanel.highGrille:
        return 'high_grille';
      case BuilderVisionPanel.glazingLowGrille:
        return 'glazing_low_grille';
      case BuilderVisionPanel.fullGlazed:
        return 'full_glazed';
      case BuilderVisionPanel.custom:
        return 'custom';
    }
  }

  static BuilderFinishType _finishFromStored(String value) {
    switch (value.toLowerCase()) {
      case 'painted':
      case 'paint':
        return BuilderFinishType.painted;
      case 'veneer':
        return BuilderFinishType.veneer;
      case 'laminate':
        return BuilderFinishType.laminate;
      default:
        return BuilderFinishType.primer;
    }
  }

  static String _finishToStored(BuilderFinishType value) {
    switch (value) {
      case BuilderFinishType.primer:
        return 'primer';
      case BuilderFinishType.painted:
        return 'painted';
      case BuilderFinishType.veneer:
        return 'veneer';
      case BuilderFinishType.laminate:
        return 'laminate';
    }
  }

  static String _configurationFromBuilder(
      PreInstallationSurveyBuilderData data) {
    if (data.sidePanelLeft || data.sidePanelRight) {
      if (data.overPanel) return 'sideOverCombo';
      return data.doorType == BuilderDoorType.doubleLeaf
          ? 'doubleSidePanel'
          : 'singleSidePanel';
    }
    if (data.overPanel) {
      return data.doorType == BuilderDoorType.doubleLeaf
          ? 'doubleOverPanel'
          : 'singleOverPanel';
    }
    return data.doorType == BuilderDoorType.doubleLeaf
        ? 'doubleLeaf'
        : 'singleLeaf';
  }

  static List<DoorHardwareItem> _hardwareFromBuilder(
      PreInstallationSurveyBuilderData data) {
    final rows = <DoorHardwareItem>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;

    if (data.closer) {
      rows.add(
        DoorHardwareItem(
          id: 'closer_$stamp',
          category: 'closing',
          type: 'doorCloser',
          selected: true,
        ),
      );
    }

    if (data.lockType != 'none') {
      rows.add(
        DoorHardwareItem(
          id: 'lock_${stamp + 1}',
          category: 'locking',
          type: data.lockType == 'custom'
              ? data.customLockType.trim()
              : data.lockType,
          selected: true,
        ),
      );
    }

    for (var i = 0; i < data.handles.length; i++) {
      rows.add(
        DoorHardwareItem(
          id: 'handle_${stamp + 10 + i}',
          category: 'handle',
          type: data.handles[i],
          selected: true,
        ),
      );
    }

    return rows;
  }

  // ── Seal helpers ──────────────────────────────────────────────────────────

  static String _sealString(PreInstallationSurveyBuilderData data) {
    if (data.sealType == 'none') return '';
    final parts = [data.sealType, data.sealPosition];
    if (data.sealNote.trim().isNotEmpty) parts.add(data.sealNote.trim());
    return parts.join('|');
  }

  static String _sealTypeFromStored(String stored) {
    if (stored.trim().isEmpty) return 'none';
    final parts = stored.split('|');
    const valid = ['intumescent', 'smoke', 'combined'];
    return valid.contains(parts[0]) ? parts[0] : 'none';
  }

  static String _sealPositionFromStored(String stored) {
    if (stored.trim().isEmpty) return 'inFrame';
    final parts = stored.split('|');
    if (parts.length < 2) return 'inFrame';
    const valid = ['inFrame', 'onDoor', 'other'];
    return valid.contains(parts[1]) ? parts[1] : 'inFrame';
  }

  static String _sealNoteFromStored(String stored) {
    if (stored.trim().isEmpty) return '';
    final parts = stored.split('|');
    return parts.length >= 3 ? parts.sublist(2).join('|') : '';
  }

  static double? _toDoubleOrNull(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }
}
