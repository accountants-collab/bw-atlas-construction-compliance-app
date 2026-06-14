import 'inspection_definitions.dart';

// ============================================================
// ART-based recommended action configuration
// ============================================================
//
// Each [ArtActionGroup] maps a check to its parent ART
// and provides selectable sub-actions (ART##a, ART##b …).
//
// Add a new group here to extend the system to a new check
// without touching UI widgets.
// ============================================================

class ArtActionOption {
  /// Internal storage/matching key (e.g. 'ART04d'). Never changes.
  final String code;

  /// Code shown in UI before the action text.
  /// When null, falls back to [code].
  /// Use this when the correct display code differs from the internal key,
  /// e.g. ART22b for an item stored internally as ART04d.
  final String? displayCode;

  /// Optional real ART family code used for exports/PDF/remedials.
  /// When null, the ART## prefix is extracted from [displayCode] ?? [code].
  final String? actualArtCode;

  final String text;

  const ArtActionOption({
    required this.code,
    required this.text,
    this.displayCode,
    this.actualArtCode,
  });

  /// Code displayed before the text in UI and PDF.
  String get resolvedDisplayCode => displayCode ?? code;

  /// Full display string.
  String get full => '$resolvedDisplayCode $text';

  String get uiCode => code;

  String get resolvedArtCode =>
      getCorrectArtCode(actualArtCode: actualArtCode, uiCode: resolvedDisplayCode);
}

class ArtActionGroup {
  /// The inspection check this group belongs to.
  final InspectionCheckId checkId;

  /// Parent ART number (e.g. 4 → "ART04").
  final int parentArtNumber;

  /// Human-readable section title shown above the selector.
  final String selectorTitle;

  /// The individual selectable options.
  final List<ArtActionOption> options;

  /// Whether an optional video upload/record field should be shown.
  final bool supportsVideo;

  const ArtActionGroup({
    required this.checkId,
    required this.parentArtNumber,
    required this.selectorTitle,
    required this.options,
    this.supportsVideo = false,
  });

  String get parentCode => 'ART${parentArtNumber.toString().padLeft(2, '0')}';

  /// Custom-action code suffix (e.g. "ART04x").
  String get customCode => '${parentCode}x';
}

// ============================================================
// Central action group registry
// ============================================================

const artActionRegistry = <InspectionCheckId, ArtActionGroup>{
  // ── A. Hold-open device ──────────────────────────────────
  InspectionCheckId.holdOpenDevice: ArtActionGroup(
    checkId: InspectionCheckId.holdOpenDevice,
    parentArtNumber: 10,
    selectorTitle: 'Hold-Open Device – ART10',
    options: [
      ArtActionOption(code: 'ART10a', text: 'Test hold-open device release function.'),
      ArtActionOption(code: 'ART10b', text: 'Adjust hold-open device settings (release sensitivity / timing).'),
      ArtActionOption(code: 'ART10c', text: 'Install fire alarm connection to hold-open device.'),
      ArtActionOption(code: 'ART10d', text: 'Replace hold-open device with compliant unit.'),
    ],
  ),

  // ── B. Door closer ───────────────────────────────────────
  InspectionCheckId.doorCloserNotOperating: ArtActionGroup(
    checkId: InspectionCheckId.doorCloserNotOperating,
    parentArtNumber: 5,
    selectorTitle: 'Door Closer – ART05',
    options: [
      ArtActionOption(code: 'ART05a', text: 'Adjust closing speed.'),
      ArtActionOption(code: 'ART05b', text: 'Adjust door closer.'),
      ArtActionOption(code: 'ART05c', text: 'Repair door closer.'),
      ArtActionOption(code: 'ART05d', text: 'Replace door closer.'),
    ],
    supportsVideo: true,
  ),

  // ── C. Door leaf out of alignment ────────────────────────
  InspectionCheckId.doorLeafOutOfAlignment: ArtActionGroup(
    checkId: InspectionCheckId.doorLeafOutOfAlignment,
    parentArtNumber: 6,
    selectorTitle: 'Door Leaf Alignment – ART06',
    options: [
      ArtActionOption(code: 'ART06a', text: 'Adjust door and/or frame to achieve compliant alignment.'),
      ArtActionOption(code: 'ART06b', text: 'Repair distorted door leaf.'),
      ArtActionOption(code: 'ART06c', text: 'Adjust hinges to achieve compliant alignment.'),
    ],
  ),

  // ── D. Lipping damage ────────────────────────────────────
  InspectionCheckId.lippingDamage: ArtActionGroup(
    checkId: InspectionCheckId.lippingDamage,
    parentArtNumber: 1,
    selectorTitle: 'Lipping Damage – ART01',
    options: [
      ArtActionOption(code: 'ART01a', text: 'Repair damaged lipping.'),
      ArtActionOption(code: 'ART01b', text: 'Replace lipping (specify location).'),
      ArtActionOption(code: 'ART01c', text: 'Replace full lipping.'),
    ],
  ),

  // ── E. Over-recessed hardware ────────────────────────────
  InspectionCheckId.overRecessedHardware: ArtActionGroup(
    checkId: InspectionCheckId.overRecessedHardware,
    parentArtNumber: 2,
    selectorTitle: 'Over-Recessed Hardware – ART02',
    options: [
      ArtActionOption(code: 'ART02a', text: 'Repair voids around hardware in door leaf/frame.'),
      ArtActionOption(code: 'ART02b', text: 'Install packed hardware to correct recess depth.'),
      ArtActionOption(code: 'ART02c', text: 'Refit hardware to correct recess depth.'),
    ],
  ),

  // ── F. Hinges dropped or damaged ────────────────────────
  InspectionCheckId.hingesDroppedOrDamaged: ArtActionGroup(
    checkId: InspectionCheckId.hingesDroppedOrDamaged,
    parentArtNumber: 8,
    selectorTitle: 'Hinges Dropped or Damaged – ART08',
    options: [
      ArtActionOption(code: 'ART08a', text: 'Replace hinges with compliant fire-rated hinges.'),
      ArtActionOption(code: 'ART08b', text: 'Adjust hinges to correct alignment.'),
      ArtActionOption(code: 'ART08c', text: 'Repair hinge fixings or reinstate secure fixing.'),
      ArtActionOption(code: 'ART08d', text: 'Add additional hinges to achieve compliance.'),
    ],
  ),

  // ── G. Hinge fixings loose or missing ───────────────────
  InspectionCheckId.hingeFixingsLooseOrMissing: ArtActionGroup(
    checkId: InspectionCheckId.hingeFixingsLooseOrMissing,
    parentArtNumber: 13,
    selectorTitle: 'Hinge Fixings Loose or Missing – ART13',
    options: [
      ArtActionOption(code: 'ART13a', text: 'Tighten loose fixings.'),
      ArtActionOption(code: 'ART13b', text: 'Replace fixings.'),
      ArtActionOption(code: 'ART13c', text: 'Replace with correct screw type.'),
      ArtActionOption(code: 'ART13d', text: 'Install missing fixings.'),
    ],
  ),

  // ── H. Misaligned matching hardware / latch issue ────────
  InspectionCheckId.misalignedMatchingHardwareLatchIssue: ArtActionGroup(
    checkId: InspectionCheckId.misalignedMatchingHardwareLatchIssue,
    parentArtNumber: 12,
    selectorTitle: 'Misaligned Hardware / Latch Issue – ART12',
    options: [
      ArtActionOption(code: 'ART12a', text: 'Adjust latch alignment.'),
      ArtActionOption(code: 'ART12b', text: 'Adjust keep/strike plate alignment.'),
      ArtActionOption(code: 'ART12c', text: 'Repair latch mechanism.'),
      ArtActionOption(code: 'ART12d', text: 'Replace lock/latch.'),
      ArtActionOption(code: 'ART12e', text: 'Adjust latch engagement depth.'),
    ],
  ),

  // ── I. Door frame joints issue ───────────────────────────
  InspectionCheckId.doorFrameJointsIssue: ArtActionGroup(
    checkId: InspectionCheckId.doorFrameJointsIssue,
    parentArtNumber: 3,
    selectorTitle: 'Door Frame Joints – ART03',
    options: [
      ArtActionOption(code: 'ART03a', text: 'Tighten or refix frame joints.'),
      ArtActionOption(code: 'ART03b', text: 'Reinforce frame joints.'),
      ArtActionOption(code: 'ART03c', text: 'Seal frame joints with appropriate fire-rated material.'),
      ArtActionOption(code: 'ART03d', text: 'Replace damaged frame section.'),
    ],
  ),

  // ── J. Door leaf replacement needed ─────────────────────
  InspectionCheckId.doorLeafReplacementNeeded: ArtActionGroup(
    checkId: InspectionCheckId.doorLeafReplacementNeeded,
    parentArtNumber: 17,
    selectorTitle: 'Door Leaf Replacement – ART17',
    options: [
      ArtActionOption(
        code: 'ART17a',
        text: 'Replace door leaf with compliant fire-rated unit.',
      ),
    ],
  ),

  // ── K. Damaged perimeter seals ───────────────────────────
  InspectionCheckId.damagedPerimeterSeals: ArtActionGroup(
    checkId: InspectionCheckId.damagedPerimeterSeals,
    parentArtNumber: 11,
    selectorTitle: 'Damaged Perimeter Seals – ART11',
    options: [
      ArtActionOption(code: 'ART11a', text: 'Install missing perimeter seal.'),
      ArtActionOption(code: 'ART11b', text: 'Repair minor perimeter seal damage.'),
      ArtActionOption(code: 'ART11c', text: 'Replace intumescent strip (correct size/specification).'),
      ArtActionOption(code: 'ART11d', text: 'Replace combined intumescent/smoke seal.'),
      ArtActionOption(code: 'ART11e', text: 'Replace perimeter seal with correct specification.'),
    ],
  ),

  // ── L. Glazing / glass / beading ─────────────────────────
  InspectionCheckId.damagedGlazingSystem: ArtActionGroup(
    checkId: InspectionCheckId.damagedGlazingSystem,
    parentArtNumber: 14,
    selectorTitle: 'Glazing / Glass / Beading – ART14',
    options: [
      ArtActionOption(code: 'ART14a', text: 'Install or replace glazing gaskets (intumescent where required).'),
      ArtActionOption(code: 'ART14b', text: 'Repair glazing components (minor defects).'),
      ArtActionOption(code: 'ART14c', text: 'Replace non-compliant or unmarked glass with certified fire-rated glass.'),
      ArtActionOption(code: 'ART14d', text: 'Replace glazing beads with compliant fire-rated beads.'),
      ArtActionOption(code: 'ART14e', text: 'Replace non-compliant glazing system with tested and certified system.'),
    ],
  ),

  // ── M. Architrave / sealing ──────────────────────────────
  InspectionCheckId.architraveSealingRefitOrReplace: ArtActionGroup(
    checkId: InspectionCheckId.architraveSealingRefitOrReplace,
    parentArtNumber: 16,
    selectorTitle: 'Architrave / Sealing – ART16',
    options: [
      ArtActionOption(code: 'ART16a', text: 'Repair or refix architrave.'),
      ArtActionOption(code: 'ART16b', text: 'Replace damaged architrave.'),
      ArtActionOption(code: 'ART16c', text: 'Seal gaps around frame with appropriate fire-rated materials.'),
      ArtActionOption(code: 'ART16d', text: 'Remove non-compliant materials from frame gap.'),
      ArtActionOption(code: 'ART16e', text: 'Install tested and compliant fire stopping system to frame.'),
    ],
  ),

  // ── N. Fire door signage ─────────────────────────────────
  InspectionCheckId.signage: ArtActionGroup(
    checkId: InspectionCheckId.signage,
    parentArtNumber: 19,
    selectorTitle: 'Fire Door Signage – ART19',
    options: [
      ArtActionOption(code: 'ART19a', text: 'Install required fire door signage.'),
      ArtActionOption(code: 'ART19b', text: 'Replace incorrect or non-compliant signage.'),
      ArtActionOption(code: 'ART19c', text: 'Install "Fire Door Keep Shut" sign.'),
      ArtActionOption(code: 'ART19d', text: 'Install "Fire Door Keep Locked" sign.'),
      ArtActionOption(code: 'ART19e', text: 'Install "Automatic Fire Door Keep Clear" sign.'),
      ArtActionOption(code: 'ART19f', text: 'Adjust signage position to comply with regulations.'),
    ],
  ),

  // ── ART04 Gaps (keeps existing entry, updated sub-codes) ─
  InspectionCheckId.doorGapsIncorrect: ArtActionGroup(
    checkId: InspectionCheckId.doorGapsIncorrect,
    parentArtNumber: 4,
    selectorTitle: 'Door Gaps – ART04',
    options: [
      ArtActionOption(
        code: 'ART04a',
        text: 'Adjust door/frame to compliant gaps.',
        actualArtCode: 'ART04',
      ),
      ArtActionOption(code: 'ART06a', text: 'Adjust door alignment to reduce gaps.', actualArtCode: 'ART06'),
      ArtActionOption(code: 'ART21a', text: 'Adjust frame alignment to reduce gaps.', actualArtCode: 'ART21'),
      ArtActionOption(
        code: 'ART22b',
        text: 'Adjust drop-down seal threshold.',
        actualArtCode: 'ART22',
      ),
      ArtActionOption(
        code: 'ART22a',
        text: 'Install drop-down seal.',
        actualArtCode: 'ART22',
      ),
    ],
  ),

};

const _actualArtCodeOverridesByUiCode = <String, String>{
  // Door gaps section keeps UI grouping but exports with real ART category.
  'ART04a': 'ART04',
  'ART06A': 'ART06',
  'ART21A': 'ART21',
  'ART22A': 'ART22',
  'ART22B': 'ART22',
};

/// Look up the action group for a given check.
/// Returns null if no structured options are defined.
ArtActionGroup? artGroupForCheck(InspectionCheckId id) {
  return artActionRegistry[id];
}

String getCorrectArtCode({String? actualArtCode, String? uiCode}) {
  final explicit = (actualArtCode ?? '').trim();
  if (explicit.isNotEmpty) {
    return explicit;
  }

  final ui = (uiCode ?? '').trim().toUpperCase();
  final override = _actualArtCodeOverridesByUiCode[ui];
  if (override != null) {
    return override;
  }

  final m = RegExp(r'^(ART\d{2})').firstMatch(ui);
  return m?.group(1) ?? ui;
}

List<Map<String, String?>> buildSelectedActionMappings({
  required List<String> selectedCodes,
  required String customText,
  required ArtActionGroup group,
}) {
  final mappings = <Map<String, String?>>[];

  for (final code in selectedCodes) {
    final option = group.options.where((o) => o.code == code).toList();
    if (option.isEmpty) {
      continue;
    }
    final o = option.first;
    mappings.add({
      'sectionArtCode': group.parentCode,
      'visibleLabel': o.full,
      'selectedLabel': o.full,
      'uiCode': o.uiCode,
      'displayCode': o.resolvedDisplayCode,
      'actualArtCode': getCorrectArtCode(actualArtCode: o.actualArtCode, uiCode: o.resolvedDisplayCode),
      'actionText': o.text,
      'customText': null,
    });
  }

  final custom = customText.trim();
  if (custom.isNotEmpty) {
    final customArtCode = '${group.parentCode}-custom';
    mappings.add({
      'sectionArtCode': group.parentCode,
      'visibleLabel': custom,
      'selectedLabel': custom,
      'uiCode': null,
      'actualArtCode': customArtCode,
      'actionText': custom,
      'customText': custom,
    });
  }

  return mappings;
}

/// Build the recommended action text from selected codes + custom.
String buildRecommendedActionText({
  required List<String> selectedCodes,
  required String customText,
  required ArtActionGroup group,
}) {
  final lines = <String>[];

  for (final code in selectedCodes) {
    final option = group.options.where((o) => o.code == code).toList();
    if (option.isNotEmpty) {
      lines.add(option.first.full);
    }
  }

  final custom = customText.trim();
  if (custom.isNotEmpty) {
    lines.add('${group.customCode} $custom');
  }

  return lines.join('\n');
}

/// Parse selected codes from the existing recommendedAction text,
/// so the multi-select picker re-checks previously applied selections.
List<String> parseSelectedCodesFromText({
  required String recommendedActionText,
  required ArtActionGroup group,
}) {
  final knownCodes = group.options.map((o) => o.code).toSet();
  final selected = <String>[];

  for (final line in recommendedActionText.split('\n')) {
    final trimmed = line.trim();
    for (final code in knownCodes) {
      if (trimmed.startsWith(code)) {
        selected.add(code);
        break;
      }
    }
  }

  return selected;
}
