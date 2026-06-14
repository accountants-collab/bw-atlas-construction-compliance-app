import 'models.dart';

enum InspectionSection {
  certification,
  gaps,
  hardware,
  signage,
  glazingSeals,
}

String inspectionSectionTitle(InspectionSection s) {
  switch (s) {
    case InspectionSection.certification:
      return 'Certification';
    case InspectionSection.gaps:
      return 'Gaps';
    case InspectionSection.hardware:
      return 'Hardware';
    case InspectionSection.signage:
      return 'Signage';
    case InspectionSection.glazingSeals:
      return 'Glazing / seals';
  }
}

String inspectionSectionHelper(InspectionSection s) {
  switch (s) {
    case InspectionSection.certification:
      return 'Confirm evidence of certification, correct classification, and required labels/markings.';
    case InspectionSection.gaps:
      return 'Check frame/leaf gaps meet specification and are consistent around the door.';
    case InspectionSection.hardware:
      return 'Check hinges, fixings, closer, latch, and hardware fitment.';
    case InspectionSection.signage:
      return 'Check correct fire door signage is installed and visible.';
    case InspectionSection.glazingSeals:
      return 'Check glazing system, beads, and seals are present, continuous, and undamaged.';
  }
}

/// Check IDs for the new professional workflow.
/// (These are the checks that map to your ART table.)
enum InspectionCheckId {
  doorGapsIncorrect,
  doorCloserNotOperating,
  doorFrameJointsIssue,
  lippingDamage,
  overRecessedHardware,
  doorLeafOutOfAlignment,
  hingesDroppedOrDamaged,
  hingeFixingsLooseOrMissing,
  damagedPerimeterSeals,
  misalignedMatchingHardwareLatchIssue,
  damagedGlazingSystem,
  architraveSealingRefitOrReplace,
  doorLeafReplacementNeeded,
  holdOpenDevice, // special: can be N/A and can be critical fail
  signage, // pass/advisory/fail (no ART per your rule for advisory; ART only for fail/critical)
}

class InspectionCheckDefinition {
  final InspectionCheckId id;
  final InspectionSection section;
  final String title;
  final String helperText;

  /// Allowed outcomes for this check.
  final List<InspectionOutcome> allowedOutcomes;

  /// ART mapping for Fail/CriticalFail.
  /// Null means: no ART mapping.
  final int? artCodeOnFail;

  /// Recommended action suggested by the system (user can edit per Q2).
  final String recommendedAction;

  const InspectionCheckDefinition({
    required this.id,
    required this.section,
    required this.title,
    required this.helperText,
    required this.allowedOutcomes,
    required this.artCodeOnFail,
    required this.recommendedAction,
  });
}

/// Central definitions table (scalable).
/// UI + logic will be driven from this list.
const inspectionChecks = <InspectionCheckDefinition>[
  // -----------------------
  // Operation / Gaps
  // -----------------------
  InspectionCheckDefinition(
    id: InspectionCheckId.doorGapsIncorrect,
    section: InspectionSection.gaps,
    title: 'Door gaps incorrect / frame gaps too large',
    helperText: 'Measure/assess clearances around leaf and frame. Confirm within spec.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail],
    artCodeOnFail: 4, // ART 04
    recommendedAction: 'Adjust/repair door to achieve correct gap specification.',
  ),
  // -----------------------
  // Hardware
  // -----------------------
  InspectionCheckDefinition(
    id: InspectionCheckId.doorCloserNotOperating,
    section: InspectionSection.hardware,
    title: 'Door closer damaged, altered, leaking, not operating',
    helperText: 'Check closer for leaks, damage, missing fixings, and correct closing action.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail],
    artCodeOnFail: 5, // ART 05
    recommendedAction: 'Repair/replace closer and set correct closing speed and latch action.',
  ),
  InspectionCheckDefinition(
    id: InspectionCheckId.doorFrameJointsIssue,
    section: InspectionSection.certification,
    title: 'Door frame joints issue',
    helperText: 'Check frame joints integrity and fit; confirm no movement/splitting.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail],
    artCodeOnFail: 3, // ART 03
    recommendedAction: 'Repair frame joints and ensure frame integrity is restored.',
  ),
  InspectionCheckDefinition(
    id: InspectionCheckId.lippingDamage,
    section: InspectionSection.hardware,
    title: 'Lipping damage',
    helperText: 'Check lipping edges for damage, delamination, or missing sections.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail],
    artCodeOnFail: 1, // ART 01
    recommendedAction: 'Repair/replace lipping to restore fire performance.',
  ),
  InspectionCheckDefinition(
    id: InspectionCheckId.overRecessedHardware,
    section: InspectionSection.hardware,
    title: 'Over recessed hardware',
    helperText: 'Check hardware recessing is within manufacturer specification.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail],
    artCodeOnFail: 2, // ART 02
    recommendedAction: 'Correct over-recessing and re-fit hardware to specification.',
  ),
  InspectionCheckDefinition(
    id: InspectionCheckId.doorLeafOutOfAlignment,
    section: InspectionSection.gaps,
    title: 'Door leaf out of alignment / distortion',
    helperText: 'Check leaf alignment, distortion/warping and correct closing into frame.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail],
    artCodeOnFail: 6, // ART 06
    recommendedAction: 'Correct alignment or replace leaf if necessary.',
  ),
  InspectionCheckDefinition(
    id: InspectionCheckId.hingesDroppedOrDamaged,
    section: InspectionSection.hardware,
    title: 'Hinges dropped or damaged',
    helperText: 'Check hinges for wear, bending, damaged knuckles or missing components.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail],
    artCodeOnFail: 8, // ART 08
    recommendedAction: 'Repair/replace hinges and confirm correct door operation.',
  ),
  InspectionCheckDefinition(
    id: InspectionCheckId.hingeFixingsLooseOrMissing,
    section: InspectionSection.hardware,
    title: 'Hinge fixings loose or missing',
    helperText: 'Check hinge screws/fixings are present, tight, and correct type.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail],
    artCodeOnFail: 13, // ART 13
    recommendedAction: 'Replace/secure hinge fixings and re-test door alignment.',
  ),
  InspectionCheckDefinition(
    id: InspectionCheckId.misalignedMatchingHardwareLatchIssue,
    section: InspectionSection.hardware,
    title: 'Misaligned matching hardware / latch issue',
    helperText: 'Check latch/keep alignment and that the door latches reliably.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail, InspectionOutcome.criticalFail],
    artCodeOnFail: 12, // ART 12
    recommendedAction: 'Adjust/repair latch and matching hardware to ensure secure latching.',
  ),

  // Hold-open (special)
  InspectionCheckDefinition(
    id: InspectionCheckId.holdOpenDevice,
    section: InspectionSection.hardware,
    title: 'Hold-open device',
    helperText: 'If fitted: confirm release on alarm activation and correct operation.',
    allowedOutcomes: [
      InspectionOutcome.pass,
      InspectionOutcome.notApplicable,
      InspectionOutcome.fail,
      InspectionOutcome.criticalFail,
    ],
    artCodeOnFail: 10,
    recommendedAction: 'Service hold-open device and confirm correct release operation.',
  ),

  // -----------------------
  // Glazing / seals
  // -----------------------
  InspectionCheckDefinition(
    id: InspectionCheckId.damagedPerimeterSeals,
    section: InspectionSection.glazingSeals,
    title: 'Damaged perimeter seals',
    helperText: 'Check smoke/intumescent seals are continuous, correct size, and undamaged.',
    // Added N/A
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail, InspectionOutcome.notApplicable],
    artCodeOnFail: 11, // ART 11
    recommendedAction: 'Replace damaged perimeter seals with correct specification.',
  ),
  InspectionCheckDefinition(
    id: InspectionCheckId.damagedGlazingSystem,
    section: InspectionSection.glazingSeals,
    title: 'Damaged glazing / glass / beading / intumescent glazing system',
    helperText: 'Check glazing, beads, gaskets, and intumescent glazing system are intact and correct.',
    // Added N/A
    allowedOutcomes: [
      InspectionOutcome.pass,
      InspectionOutcome.fail,
      InspectionOutcome.criticalFail,
      InspectionOutcome.notApplicable,
    ],
    artCodeOnFail: 14, // ART 14
    recommendedAction: 'Repair/replace glazing system to restore fire performance.',
  ),
  InspectionCheckDefinition(
    id: InspectionCheckId.architraveSealingRefitOrReplace,
    section: InspectionSection.glazingSeals,
    title: 'Architrave / sealing needs replacement or refitting',
    helperText: 'Check architrave and perimeter sealing are secure and effective.',
    // Added N/A
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail, InspectionOutcome.notApplicable],
    artCodeOnFail: 16, // ART 16
    recommendedAction: 'Refit/replace architrave and sealing as required.',
  ),

  // -----------------------
  // Leaf replacement
  // -----------------------
  InspectionCheckDefinition(
    id: InspectionCheckId.doorLeafReplacementNeeded,
    section: InspectionSection.certification,
    title: 'Door leaf replacement needed',
    helperText: 'If leaf is beyond repair or not suitable for fire performance.',
    allowedOutcomes: [InspectionOutcome.pass, InspectionOutcome.fail, InspectionOutcome.criticalFail],
    artCodeOnFail: 17, // ART 17
    recommendedAction: 'Replace door leaf with certified fire door leaf and install to specification.',
  ),

  // -----------------------
  // Signage
  // -----------------------
  InspectionCheckDefinition(
    id: InspectionCheckId.signage,
    section: InspectionSection.signage,
    title: 'Fire door signage',
    helperText: 'Check correct signage is installed and visible (e.g. Fire Door Keep Shut/Locked).',
    allowedOutcomes: [
      InspectionOutcome.pass,
      InspectionOutcome.advisory,
      InspectionOutcome.fail,
      InspectionOutcome.notApplicable,
    ],
    artCodeOnFail: 19, // ART 19
    recommendedAction: 'Install/replace correct fire door signage.',
  ),
];

InspectionCheckDefinition checkDef(InspectionCheckId id) {
  return inspectionChecks.firstWhere((c) => c.id == id);
}

/// For PDF/report display.
String checkTitle(InspectionCheckId id) => checkDef(id).title;

/// For PDF/report display.
String checkHelper(InspectionCheckId id) => checkDef(id).helperText;

/// For UI grouping.
Map<InspectionSection, List<InspectionCheckDefinition>> checksBySection() {
  final map = <InspectionSection, List<InspectionCheckDefinition>>{};
  for (final c in inspectionChecks) {
    map.putIfAbsent(c.section, () => <InspectionCheckDefinition>[]).add(c);
  }
  return map;
}

/// Helper: which checks are glazing-related (for hide/show section logic in UI).
bool isGlazingCheck(InspectionCheckId id) {
  final s = checkDef(id).section;
  return s == InspectionSection.glazingSeals;
}

/// ART code shown for outcome.
/// Advisory => null (per your requirement).
int? autoArtCodeForOutcome({
  required InspectionCheckId checkId,
  required InspectionOutcome outcome,
}) {
  if (outcome == InspectionOutcome.fail || outcome == InspectionOutcome.criticalFail) {
    return checkDef(checkId).artCodeOnFail;
  }
  return null;
}

/// Controls which checks are applicable for the current door setup.
/// Non-applicable checks are auto-set to N/A by door detail UIs.
bool isCheckApplicable({
  required InspectionCheckId checkId,
  required bool hasDoorCloser,
  required bool hasSeals,
  required bool hasGlazing,
  required bool hasSignage,
}) {
  switch (checkId) {
    case InspectionCheckId.doorCloserNotOperating:
    case InspectionCheckId.holdOpenDevice:
      return hasDoorCloser;
    case InspectionCheckId.damagedPerimeterSeals:
      return hasSeals;
    case InspectionCheckId.damagedGlazingSystem:
    case InspectionCheckId.architraveSealingRefitOrReplace:
      return hasGlazing;
    case InspectionCheckId.signage:
      return hasSignage;
    default:
      return true;
  }
}