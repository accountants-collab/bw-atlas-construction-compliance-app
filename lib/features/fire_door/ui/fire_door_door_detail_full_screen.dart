// DEPRECATED: Legacy shared survey inspection flow.
// Active runtime flow uses workspace module routes under /workspace/*/inspection/*.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../../app/ui/photo_viewer.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../../core/files/pdf_download_saver.dart';
import '../../../core/media/camera_capture_helper.dart';
import '../../disclaimer/domain/disclaimer_models.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/state/settings_controller.dart';
import '../../storage/data/company_file_providers.dart';
import '../../storage/domain/company_file_record.dart';
import '../inspection/domain/art_recommended_actions.dart';
import '../inspection/domain/inspection_definitions.dart';
import '../inspection/domain/models.dart';
import '../inspection/pdf/survey_pdf.dart';
import '../inspection/pdf/web_download_stub.dart'
    if (dart.library.html) '../inspection/pdf/web_download.dart';
import '../inspection/state/survey_controller.dart';
import '../inspection/ui/project_drawing_viewer.dart';
import 'fire_door_web_shell_scaffold.dart';

enum DoorDetailMode { edit }

enum _IdentificationMode { manual, drawingPin }

enum InspectionProgressStatus { notStarted, inProgress, complete }

enum _SectionGateOutcome { pass, fail, notApplicable }

enum _MaintenancePreset {
  communal3,
  flatEntrance12,
  general6,
  general12,
  custom,
}

const _fireStoppingRatings = <String>[
  '30',
  '60',
  '90',
  '120',
  'Other (custom)',
];

const _fireStoppingDefectTemplates = <String>[
  'Cable',
  'Pipe',
  'Single Socket',
  'Double Socket',
  'Single Switch',
  'Double Switch',
  'Other (custom)',
];

const _fireStoppingRecommendedActionOptions = <String>[
  'Install fire stopping system to penetration',
  'Apply intumescent mastic',
  'Install fire putty pad (single socket)',
  'Install fire putty pad (double socket)',
  'Seal with fire batt & mastic',
  'Other (custom)',
];

class DoorDetailScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final DoorDetailMode mode;
  final String existingDoorId;
  final bool isTempDraft;
  final String moduleKey;
  final String routePrefix;
  final String workspaceKey;

  const DoorDetailScreen({
    super.key,
    required this.surveyId,
    required this.mode,
    required this.existingDoorId,
    this.isTempDraft = false,
    this.moduleKey = 'inspection',
    this.routePrefix = '/surveys',
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<DoorDetailScreen> createState() => _DoorDetailScreenState();
}

class _DoorDetailScreenState extends ConsumerState<DoorDetailScreen> {
  final _doorIdTag = TextEditingController();
  _IdentificationMode _identificationMode = _IdentificationMode.manual;

  String _doorLocation = '';
  String _floorLevel = '';
  String _customMaterial = '';
  String _frameMaterial = 'Unknown';
  String _certificationBodyName = '';

  DoorMaterial _material = DoorMaterial.unknown;
  DoorClassification _classification = DoorClassification.unknownNotVerified;
  FireRating _fireRating = FireRating.unknown;
  GradingLevel _gradingLevel = GradingLevel.level4;
  DoorConfiguration _configuration = DoorConfiguration.singleLeaf;

  List<PhotoAttachment> _doorPhotos = [];
  DateTime _inspectionDate = DateTime.now();
  int _maintenanceIntervalMonths = 12;
  bool _useCustomMaintenanceInterval = false;
  final _customMaintenanceInterval = TextEditingController(text: '12');
  bool _loaded = false;

  bool _savedOnce = false;

  final _approvedMaintainerName = TextEditingController();
  final _approvedMaintainerNumber = TextEditingController();
  final _customMaterialCtrl = TextEditingController();
  final _replacementDoor1WidthCtrl = TextEditingController();
  final _replacementDoor1HeightCtrl = TextEditingController();
  final _replacementDoor2WidthCtrl = TextEditingController();
  final _replacementDoor2HeightCtrl = TextEditingController();
  final _customCertificationBodyCtrl = TextEditingController();
  final _reportPreparedByCtrl = TextEditingController();
  final _designationSourceCustomCtrl = TextEditingController();
  final _plugOuterColourCtrl = TextEditingController();
  final _plugInnerCoreColourCtrl = TextEditingController();
  final _traceabilityNumberCtrl = TextEditingController();
  final _fireStoppingQuantityCtrl = TextEditingController(text: '1');
  final _fireStoppingDefectDescriptionCtrl = TextEditingController();
  final _fireStoppingRecommendedActionCtrl = TextEditingController();
  final _fireStoppingDiameterCtrl = TextEditingController();
  final _fireStoppingLengthCtrl = TextEditingController();
  final _fireStoppingWidthCtrl = TextEditingController();
  final List<FireStoppingDefect> _fireStoppingDefects = <FireStoppingDefect>[];

  String _doorDrawingId = '';
  String _doorPinId = '';
  String _fireDoorDesignationSource = 'Unknown';
  bool _hasDoorCloser = true;
  bool _hasPerimeterSeals = true;
  bool _hasGlazing = true;
  bool _hasSignage = true;
  bool _plugPresent = false;
  bool _installerLabelPresent = false;
  bool _traceabilityExpanded = false;
  bool _replacementRequired = false;
  final Set<String> _plugPhotoIds = <String>{};
  final Set<String> _labelPhotoIds = <String>{};
  final Set<String> _certPhotoIds = <String>{};
  final Set<InspectionSection> _forceExpandedFailSections =
      <InspectionSection>{};
  String _fireStoppingFireRating = '';
  String _fireStoppingDrawingId = '';
  String _fireStoppingPinId = '';

  bool _isVideoFileName(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.wmv') ||
        lower.endsWith('.flv');
  }

  bool _isVideoAttachment(PhotoAttachment media) {
    if (media.mimeType.startsWith('video/')) return true;
    return _isVideoFileName(media.fileName);
  }

  String _defaultFireStoppingActionForTemplate(String template) {
    switch (template) {
      case 'Cable':
      case 'Pipe':
        return 'Install fire stopping system to penetration';
      case 'Single Socket':
        return 'Install fire putty pad (single socket)';
      case 'Double Socket':
        return 'Install fire putty pad (double socket)';
      case 'Single Switch':
      case 'Double Switch':
        return 'Apply intumescent mastic';
      default:
        return '';
    }
  }

  FireStoppingDefect _createBlankFireStoppingDefect() {
    return FireStoppingDefect(
      id: 'defect_${DateTime.now().millisecondsSinceEpoch}',
      fireRating: _fireStoppingFireRating,
      drawingId: _fireStoppingDrawingId,
      pinId: _fireStoppingPinId,
    );
  }

  void _assignFireStoppingPin({
    required ProjectDrawing drawing,
    required FloorPlanPin pin,
    bool addDefect = false,
  }) {
    setState(() {
      _doorDrawingId = drawing.id;
      _doorPinId = pin.id;
      _fireStoppingDrawingId = drawing.id;
      _fireStoppingPinId = pin.id;
      _doorIdTag.text = pin.label.trim().isNotEmpty
          ? pin.label.trim()
          : pin.doorNumber.trim();
      _fireStoppingDefects.replaceRange(
        0,
        _fireStoppingDefects.length,
        [
          for (final defect in _fireStoppingDefects)
            defect.copyWith(drawingId: drawing.id, pinId: pin.id),
        ],
      );
      if (addDefect && _fireStoppingDefects.isEmpty) {
        _fireStoppingDefects.add(_createBlankFireStoppingDefect());
      }
    });
  }

  void _assignDoorPlanPin({
    required ProjectDrawing drawing,
    required FloorPlanPin pin,
  }) {
    setState(() {
      _doorDrawingId = drawing.id;
      _doorPinId = pin.id;
      final label = pin.label.trim().isNotEmpty
          ? pin.label.trim()
          : pin.doorNumber.trim();
      if (label.isNotEmpty) {
        _doorIdTag.text = label;
      }
    });
  }

  Future<void> _openDoorPlanPinSelector({
    required Survey survey,
    bool allowExistingSelection = true,
  }) async {
    final result = await ProjectDrawingAccess.showDrawingPicker(
      context: context,
      survey: survey,
      preferredLevel: _floorLevel,
      selectionConfig: DrawingViewerSelectionConfig(
        enablePinPlacement: true,
        allowExistingPinSelection: allowExistingSelection,
        autoAssignPinNumbers: false,
        highlightedPinId: _doorPinId,
        hideOtherPins: true,
      ),
    );
    if (!mounted || result == null) return;
    _assignDoorPlanPin(drawing: result.drawing, pin: result.pin);
  }

  Future<void> _openFireStoppingPinSelector({
    required Survey survey,
    bool allowExistingSelection = true,
  }) async {
    final result = await ProjectDrawingAccess.showDrawingPicker(
      context: context,
      survey: survey,
      preferredLevel: _floorLevel,
      selectionConfig: DrawingViewerSelectionConfig(
        enablePinPlacement: true,
        allowExistingPinSelection: allowExistingSelection,
        autoAssignPinNumbers: false,
        highlightedPinId: _fireStoppingPinId,
        hideOtherPins: true,
      ),
    );
    if (!mounted || result == null) return;
    _assignFireStoppingPin(
      drawing: result.drawing,
      pin: result.pin,
      addDefect: result.addDefect,
    );
  }

  Future<Uint8List?> _buildFireStoppingPinPreview({
    required ProjectDrawing drawing,
    required FloorPlanPin pin,
  }) async {
    Uint8List? sourceBytes;
    final isPdf = drawing.mimeType.toLowerCase().contains('pdf') ||
        drawing.fileName.toLowerCase().endsWith('.pdf');
    if (isPdf) {
      try {
        await for (final raster in Printing.raster(
            Uint8List.fromList(drawing.bytes),
            pages: [pin.page - 1],
            dpi: 240)) {
          sourceBytes = await raster.toPng();
          break;
        }
      } catch (_) {
        return null;
      }
    } else {
      sourceBytes = Uint8List.fromList(drawing.bytes);
    }
    if (sourceBytes == null || sourceBytes.isEmpty) return null;
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return null;
    final full = img.copyResize(
      decoded,
      width: decoded.width > 2200 ? 2200 : decoded.width,
    );
    final markerX =
        (pin.x.clamp(0.0, 1.0) * full.width).round().clamp(0, full.width - 1);
    final markerY =
        (pin.y.clamp(0.0, 1.0) * full.height).round().clamp(0, full.height - 1);
    img.fillCircle(full,
        x: markerX, y: markerY, radius: 11, color: img.ColorRgb8(198, 40, 40));
    img.drawCircle(full,
        x: markerX,
        y: markerY,
        radius: 18,
        color: img.ColorRgb8(255, 255, 255));
    img.drawCircle(full,
        x: markerX,
        y: markerY,
        radius: 19,
        color: img.ColorRgb8(255, 255, 255));
    return Uint8List.fromList(img.encodeJpg(full, quality: 92));
  }

  Future<Uint8List?> _buildPinPreview({
    required ProjectDrawing drawing,
    required FloorPlanPin pin,
  }) {
    return _buildFireStoppingPinPreview(drawing: drawing, pin: pin);
  }

  void _hydrateFireStoppingSize(String raw) {
    _fireStoppingDiameterCtrl.clear();
    _fireStoppingLengthCtrl.clear();
    _fireStoppingWidthCtrl.clear();

    final value = raw.trim();
    if (value.isEmpty) return;
    if (!value.contains('=')) {
      _fireStoppingDiameterCtrl.text = value;
      return;
    }

    final parts = value.split(';');
    for (final part in parts) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final key = part.substring(0, eq).trim().toLowerCase();
      final val = part.substring(eq + 1).trim();
      if (key == 'diameter') _fireStoppingDiameterCtrl.text = val;
      if (key == 'length') _fireStoppingLengthCtrl.text = val;
      if (key == 'width') _fireStoppingWidthCtrl.text = val;
    }
  }

  Future<String?> _askCustomValue(
    BuildContext context, {
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Use')),
        ],
      ),
    );
    final value = (result ?? '').trim();
    return value.isEmpty ? null : value;
  }

  void _syncFireStoppingDoorPhotosFromDefects() {
    final combined = <PhotoAttachment>[];
    for (final defect in _fireStoppingDefects) {
      combined.addAll(defect.photos);
    }
    _doorPhotos = combined;
  }

  String _legacyFireStoppingRating(FireRating rating) {
    switch (rating) {
      case FireRating.fd30:
      case FireRating.fd30s:
        return '30';
      case FireRating.fd60:
      case FireRating.fd60s:
        return '60';
      case FireRating.fd90:
      case FireRating.fd90s:
        return '90';
      case FireRating.fd120:
      case FireRating.fd120s:
        return '120';
      case FireRating.notAFireDoor:
      case FireRating.unknown:
        return '';
    }
  }

  FireRating _legacyFireRatingFromFireStopping(String value) {
    switch (value.trim()) {
      case '30':
        return FireRating.fd30;
      case '60':
        return FireRating.fd60;
      case '90':
        return FireRating.fd90;
      case '120':
        return FireRating.fd120;
      default:
        return FireRating.unknown;
    }
  }

  String _mimeForVideoName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.m4v')) return 'video/x-m4v';
    return 'video/mp4';
  }

  String _mimeForDrawingName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  String _displayNameFromFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot <= 0 ? fileName : fileName.substring(0, dot);
    return base.trim().isEmpty ? fileName : base.trim();
  }

  String _videoLabelFromPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) {
          final candidate = Uri.decodeComponent(segments.last);
          if (candidate.isNotEmpty) return candidate;
        }
      }
      return trimmed.length > 64 ? '${trimmed.substring(0, 61)}...' : trimmed;
    }

    final slash = trimmed.lastIndexOf('/');
    final backslash = trimmed.lastIndexOf('\\');
    final splitAt = slash > backslash ? slash : backslash;
    if (splitAt >= 0 && splitAt < trimmed.length - 1) {
      return trimmed.substring(splitAt + 1);
    }
    return trimmed;
  }

  static const _certificationBodyOptions = <String>[
    'BM TRADA',
    'Certifire',
    'IFC Certification',
    'Other (custom)',
  ];

  String _fmtDateCompact(DateTime d) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = d.day.toString().padLeft(2, '0');
    final month = months[d.month - 1];
    return '$day $month ${d.year}';
  }

  String _fmtTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _sanitizeFileName(String input) {
    var s = input
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    s = s.replaceAll(RegExp(r'[ .]+$'), '');
    if (s.length > 80) s = s.substring(0, 80);
    return s;
  }

  String _singleDoorPdfFileName(Survey survey, Door door) {
    final day = survey.reportDate.day.toString().padLeft(2, '0');
    final month = survey.reportDate.month.toString().padLeft(2, '0');
    final year = survey.reportDate.year.toString();
    final dateTag = '$day-$month-$year';
    final doorRef = door.doorIdTag.trim().isNotEmpty
        ? door.doorIdTag.trim()
        : 'Door-${door.number}';
    return _sanitizeFileName('FireDoor_${dateTag}_$doorRef.pdf');
  }

  Future<void> _exportDoorPdf({
    required BuildContext context,
    required Survey survey,
    required Door door,
    required AppSettings settings,
  }) async {
    final branding = resolvePdfBranding(settings);
    final bytes = await SurveyPdfBuilder.buildSingleDoorPdf(
      survey,
      door,
      companyLogoBytes: branding.logoBytes,
      companyName: branding.companyName,
      companyAddress: settings.companyProfile.address,
      companyEmail: settings.companyProfile.email,
      companyPhone: settings.companyProfile.phone,
      reportHeaderText: branding.reportHeaderText,
      reportFooterText: branding.reportFooterText,
      generatedBy: survey.reportCompletedBy.trim().isNotEmpty
          ? survey.reportCompletedBy.trim()
          : 'System User',
    );
    final fileName = _singleDoorPdfFileName(survey, door);

    if (kIsWeb) {
      downloadBytesWeb(
          bytes: bytes, fileName: fileName, mimeType: 'application/pdf');
      return;
    }

    if (!context.mounted) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Download PDF'),
              onTap: () => Navigator.pop(ctx, 'download'),
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Share by email'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;
    if (action == 'download') {
      try {
        final saved =
            await PdfDownloadSaver.savePdf(bytes: bytes, fileName: fileName);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF saved: ${saved.fileName}')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save PDF to device storage: $e')),
        );
      }
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static const _standardDoorLocations = <String>[
    'Bedroom',
    'Bathroom',
    'WC',
    'Kitchen',
    'Living room',
    'Dining room',
    'Hallway',
    'Corridor',
    'Lobby',
    'Stairwell',
    'Landing',
    'Lift lobby',
    'Bin store',
    'Bicycle store',
    'Cleaner cupboard',
    'Electrical cupboard',
    'Gas meter cupboard',
    'Riser cupboard',
    'Service riser',
    'Plant room',
    'Boiler room',
    'Comms / IT cupboard',
    'Sprinkler / fire control room',
    'Refuse chute room',
    'Service corridor',
    'Basement corridor',
    'Car park',
    'External front door',
    'Main entrance door',
    'Communal entrance',
    'Rear exit door',
    'Escape route',
    'Final exit',
    'Fire escape door',
    'Flat entrance door',
    'Apartment internal door',
    'Communal cupboard',
    'Store room',
    'Office door',
    'Meeting room door',
  ];

  static const _doorLocationGroups = <String, List<String>>{
    'Residential': [
      'Flat entrance door',
      'Apartment internal door',
      'Bedroom',
      'Bathroom',
      'WC',
      'Kitchen',
      'Living room',
      'Dining room',
    ],
    'Communal': [
      'Main entrance door',
      'Communal entrance',
      'Lobby',
      'Lift lobby',
      'Stairwell',
      'Landing',
      'Bin store',
      'Bicycle store',
      'Communal cupboard',
    ],
    'Circulation': [
      'Hallway',
      'Corridor',
      'Service corridor',
      'Basement corridor',
      'Escape route',
      'Final exit',
      'Fire escape door',
      'Rear exit door',
      'External front door',
    ],
    'Service / Plant': [
      'Plant room',
      'Boiler room',
      'Electrical cupboard',
      'Gas meter cupboard',
      'Riser cupboard',
      'Service riser',
      'Cleaner cupboard',
      'Comms / IT cupboard',
      'Sprinkler / fire control room',
      'Refuse chute room',
      'Store room',
      'Car park',
    ],
  };

  static const _designationSourceOptions = <String>[
    'Floor plan',
    'Fire risk assessment',
    'Client / Responsible Person',
    'Label / plug',
    'Test / certification document',
    'Previous survey',
    'Unknown',
  ];

  static const _maintenancePresetMonths = <_MaintenancePreset, int>{
    _MaintenancePreset.communal3: 3,
    _MaintenancePreset.flatEntrance12: 12,
    _MaintenancePreset.general6: 6,
    _MaintenancePreset.general12: 12,
  };

  static const _maintenancePresetLabels = <_MaintenancePreset, String>{
    _MaintenancePreset.communal3: 'Communal door - 3 months',
    _MaintenancePreset.flatEntrance12: 'Flat entrance door - 12 months',
    _MaintenancePreset.general6: 'General use - 6 months',
    _MaintenancePreset.general12: 'General use - 12 months',
    _MaintenancePreset.custom: 'Custom interval',
  };

  static const _materialOptions = <DoorMaterial>[
    DoorMaterial.timber,
    DoorMaterial.metalDoor,
    DoorMaterial.composite,
    DoorMaterial.aluminium,
    DoorMaterial.upvc,
    DoorMaterial.otherCustom,
    DoorMaterial.unknown,
  ];

  static const _frameMaterialOptions = <String>[
    'Hardwood',
    'MDF',
    'Timber',
    'PVC',
    'Metal',
    'Unknown',
  ];

  static const _classificationOptions = <DoorClassification>[
    DoorClassification.thirdPartyCertified,
    DoorClassification.manufacturerEvidenceAvailable,
    DoorClassification.noEvidenceClientStatedFireRated,
    DoorClassification.unknownNotVerified,
  ];

  static const _fireRatingOptions = <FireRating>[
    FireRating.notAFireDoor,
    FireRating.fd30,
    FireRating.fd30s,
    FireRating.fd60,
    FireRating.fd60s,
    FireRating.fd90,
    FireRating.fd90s,
    FireRating.fd120,
    FireRating.fd120s,
    FireRating.unknown,
  ];

  static const _gradingOptions = <GradingLevel>[
    GradingLevel.level1,
    GradingLevel.level2,
    GradingLevel.level3,
    GradingLevel.level4,
  ];

  static const _configurationOptions = <DoorConfiguration>[
    DoorConfiguration.singleLeaf,
    DoorConfiguration.doubleLeaf,
    DoorConfiguration.leafAndAHalf,
  ];

  static const _maintenanceIntervalPresets = <int>[3, 6, 12, 24];

  @override
  void dispose() {
    _doorIdTag.dispose();
    _approvedMaintainerName.dispose();
    _approvedMaintainerNumber.dispose();
    _customMaintenanceInterval.dispose();
    _customMaterialCtrl.dispose();
    _replacementDoor1WidthCtrl.dispose();
    _replacementDoor1HeightCtrl.dispose();
    _replacementDoor2WidthCtrl.dispose();
    _replacementDoor2HeightCtrl.dispose();
    _customCertificationBodyCtrl.dispose();
    _designationSourceCustomCtrl.dispose();
    _plugOuterColourCtrl.dispose();
    _plugInnerCoreColourCtrl.dispose();
    _traceabilityNumberCtrl.dispose();
    _reportPreparedByCtrl.dispose();
    _fireStoppingQuantityCtrl.dispose();
    _fireStoppingDefectDescriptionCtrl.dispose();
    _fireStoppingRecommendedActionCtrl.dispose();
    _fireStoppingDiameterCtrl.dispose();
    _fireStoppingLengthCtrl.dispose();
    _fireStoppingWidthCtrl.dispose();
    super.dispose();
  }

  _MaintenancePreset _presetFromMonths(int months, {required bool custom}) {
    if (custom) return _MaintenancePreset.custom;
    if (months == 3) return _MaintenancePreset.communal3;
    if (months == 6) return _MaintenancePreset.general6;
    if (months == 12) return _MaintenancePreset.general12;
    return _MaintenancePreset.custom;
  }

  int _monthsForPreset(_MaintenancePreset preset) {
    return _maintenancePresetMonths[preset] ?? _maintenanceIntervalMonths;
  }

  String _encodeFireDoorMeta() {
    final plugPhotoIds = _plugPhotoIds
        .where((id) => _doorPhotos.any((p) => p.id == id))
        .join(',');
    final labelPhotoIds = _labelPhotoIds
        .where((id) => _doorPhotos.any((p) => p.id == id))
        .join(',');
    final certPhotoIds = _certPhotoIds
        .where((id) => _doorPhotos.any((p) => p.id == id))
        .join(',');
    final map = <String, String>{
      'src': _fireDoorDesignationSource.trim(),
      'frameMaterial': _frameMaterial.trim(),
      'plugPresent': _plugPresent ? '1' : '0',
      'plugOuter': _plugOuterColourCtrl.text.trim(),
      'plugInner': _plugInnerCoreColourCtrl.text.trim(),
      'trace': _traceabilityNumberCtrl.text.trim(),
      'installer': _installerLabelPresent ? '1' : '0',
      'hasCloser': _hasDoorCloser ? '1' : '0',
      'hasSeals': _hasPerimeterSeals ? '1' : '0',
      'hasGlazing': _hasGlazing ? '1' : '0',
      'hasSignage': _hasSignage ? '1' : '0',
      'plugPhotoIds': plugPhotoIds,
      'labelPhotoIds': labelPhotoIds,
      'certPhotoIds': certPhotoIds,
    };
    return map.entries
        .where((e) => e.value.trim().isNotEmpty)
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  void _decodeFireDoorMeta(String raw) {
    final value = raw.trim();
    if (value.isEmpty || !value.contains('=')) return;
    final map = <String, String>{};
    for (final pair in value.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = Uri.decodeComponent(pair.substring(0, eq));
      final val = Uri.decodeComponent(pair.substring(eq + 1));
      map[key] = val;
    }
    _fireDoorDesignationSource =
        map['src']?.trim().isNotEmpty == true ? map['src']!.trim() : 'Unknown';
    _frameMaterial = map['frameMaterial']?.trim().isNotEmpty == true
        ? map['frameMaterial']!.trim()
        : 'Unknown';
    _plugPresent = map['plugPresent'] == '1';
    _installerLabelPresent = map['installer'] == '1';
    _hasDoorCloser =
        map.containsKey('hasCloser') ? map['hasCloser'] == '1' : _hasDoorCloser;
    _hasPerimeterSeals = map.containsKey('hasSeals')
        ? map['hasSeals'] == '1'
        : _hasPerimeterSeals;
    _hasGlazing =
        map.containsKey('hasGlazing') ? map['hasGlazing'] == '1' : _hasGlazing;
    _hasSignage =
        map.containsKey('hasSignage') ? map['hasSignage'] == '1' : _hasSignage;
    _plugOuterColourCtrl.text = map['plugOuter'] ?? '';
    _plugInnerCoreColourCtrl.text = map['plugInner'] ?? '';
    _traceabilityNumberCtrl.text = map['trace'] ?? '';
    _plugPhotoIds
      ..clear()
      ..addAll((map['plugPhotoIds'] ?? '')
          .split(',')
          .where((e) => e.trim().isNotEmpty));
    _labelPhotoIds
      ..clear()
      ..addAll((map['labelPhotoIds'] ?? '')
          .split(',')
          .where((e) => e.trim().isNotEmpty));
    _certPhotoIds
      ..clear()
      ..addAll((map['certPhotoIds'] ?? '')
          .split(',')
          .where((e) => e.trim().isNotEmpty));
  }

  Future<List<PhotoAttachment>> _pickPhotos() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (res == null) return [];

    final photos = <PhotoAttachment>[];
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;

      photos.add(
        PhotoAttachment(
          fileName: f.name,
          mimeType: 'image/*',
          bytes: bytes,
          surveyId: widget.surveyId,
          doorId: widget.existingDoorId,
        ),
      );
    }
    return photos;
  }

  Future<void> _uploadDrawingsForLocationFlow({
    required Survey survey,
    required SurveyController controller,
  }) async {
    final auth = ref.read(authControllerProvider);
    final companyId = auth.companyId;
    if (companyId == null || companyId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company is not loaded yet. Try again.')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;

    final repo = ref.read(companyFileRepositoryProvider);
    final drawings = <ProjectDrawing>[];

    for (final f in result.files) {
      if (f.bytes == null || f.bytes!.isEmpty) continue;
      final mime = _mimeForDrawingName(f.name);
      try {
        final record = await repo.uploadBytes(
          companyId: companyId,
          entityType: 'surveyDrawing',
          entityId: survey.id,
          createdByUid: auth.uid,
          fileName: f.name,
          bytes: f.bytes!,
          mimeType: mime,
          kind: CompanyFileKind.drawing,
          tags: [_floorLevel.trim()],
        );

        drawings.add(
          ProjectDrawing(
            id: record.fileId,
            name: _displayNameFromFile(f.name),
            fileName: f.name,
            mimeType: mime,
            level: _floorLevel.trim(),
            bytes: f.bytes!,
            cloudStoragePath: record.storagePath,
            cloudDownloadUrl: record.downloadUrl,
          ),
        );
      } catch (_) {
        // Keep flow resilient if one file fails.
      }
    }

    if (drawings.isEmpty || !mounted) return;
    controller.addProjectDrawings(surveyId: survey.id, drawings: drawings);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${drawings.length} drawing(s) uploaded.')),
    );
  }

  Future<PhotoAttachment?> _takePhoto() async {
    final shot = await CameraCaptureHelper.pickImage(context, imageQuality: 85);
    if (shot == null) return null;

    final bytes = await shot.readAsBytes();
    return PhotoAttachment(
      fileName: shot.name.isEmpty
          ? 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : shot.name,
      mimeType: 'image/jpeg',
      bytes: bytes,
      surveyId: widget.surveyId,
      doorId: widget.existingDoorId,
    );
  }

  /// Config-driven multi-select recommended action picker.
  /// Works for every ART group defined in [artActionRegistry].
  Future<void> _pickRecommendedActionsForCheck({
    required SurveyController controller,
    required InspectionCheckDefinition definition,
    required InspectionCheckResult result,
  }) async {
    final group = artGroupForCheck(definition.id);
    if (group == null) return; // No ART options defined for this check.

    // Pre-select codes already stored in structured field;
    // fall back to parsing the text field for older records.
    final preCodes = result.selectedActionCodes.isNotEmpty
        ? result.selectedActionCodes.toSet()
        : parseSelectedCodesFromText(
            recommendedActionText: result.recommendedAction,
            group: group,
          ).toSet();

    const art01LocationOptions = <String>[
      'Top',
      'Bottom',
      'Hinge side',
      'Lock side',
    ];
    final isArt01LippingMenu = group.parentCode == 'ART01';

    String? extractArt01Location(String text) {
      final lower = text.toLowerCase();
      if (lower.contains('top')) return 'Top';
      if (lower.contains('bottom')) return 'Bottom';
      if (lower.contains('hinge side')) return 'Hinge side';
      if (lower.contains('lock side')) return 'Lock side';
      return null;
    }

    final selected = <String>{...preCodes};
    final selectedArt01Locations = <String>{
      if (isArt01LippingMenu)
        for (final mapping in result.selectedActionMappings)
          if ((mapping['uiCode'] ?? '').trim() == 'ART01b') ...[
            if (extractArt01Location(mapping['actionText'] ?? '')
                case final location?)
              location,
          ],
    };
    final customCtrl = TextEditingController(text: result.customActionText);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF5FB),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFCCDBEE)),
                          ),
                          child: Text(
                            group.parentCode,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1565C0),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            group.selectorTitle,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Select all applicable actions, then save the selection.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    if (group.parentCode == 'ART01')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Replace lipping of appropriate thickness and fire rating to restore integrity.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    if (group.parentCode == 'ART04')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Gaps must meet specification around door perimeter. Multiple adjustments may be required.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    if (group.parentCode == 'ART05')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Closer must comply with fire safety standards and close door to frame fully.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    if (group.parentCode == 'ART06')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Door leaf must align correctly with frame and close securely.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    if (group.parentCode == 'ART11')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Select based on condition. Exact seal specification will be confirmed during remedial works.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    if (group.parentCode == 'ART14')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Glazing must be fire-rated, correctly installed and part of a tested doorset system.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    if (group.parentCode == 'ART16')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Architrave is decorative. Fire stopping behind must be compliant to maintain compartmentation.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    if (group.parentCode == 'ART19')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Fire door signage must be present, correct type, and clearly visible.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final option in group.options)
                            CheckboxListTile(
                              value: selected.contains(option.code),
                              title: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${option.resolvedDisplayCode}  ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF1565C0),
                                        fontSize: 12,
                                      ),
                                    ),
                                    TextSpan(
                                      text: option.text,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              onChanged: (v) {
                                setSheetState(() {
                                  if (v == true) {
                                    selected.add(option.code);
                                  } else {
                                    selected.remove(option.code);
                                    if (isArt01LippingMenu &&
                                        option.code == 'ART01b') {
                                      selectedArt01Locations.clear();
                                    }
                                  }
                                });
                              },
                            ),
                          if (isArt01LippingMenu &&
                              selected.contains('ART01b')) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
                              child: Text(
                                'Specify location(s) for ART01b:',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final location in art01LocationOptions)
                                    FilterChip(
                                      label: Text(location),
                                      selected: selectedArt01Locations
                                          .contains(location),
                                      onSelected: (picked) {
                                        setSheetState(() {
                                          if (picked) {
                                            selectedArt01Locations
                                                .add(location);
                                          } else {
                                            selectedArt01Locations
                                                .remove(location);
                                          }
                                        });
                                      },
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            child: TextField(
                              controller: customCtrl,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText:
                                    '${group.parentCode == 'ART11' ? 'Add custom action (if required)' : 'Additional action (optional)'} - ${group.customCode}',
                                helperText: group.parentCode == 'ART05' ||
                                        group.parentCode == 'ART01' ||
                                        group.parentCode == 'ART08' ||
                                        group.parentCode == 'ART13' ||
                                        group.parentCode == 'ART10' ||
                                        group.parentCode == 'ART03' ||
                                        group.parentCode == 'ART17' ||
                                        group.parentCode == 'ART11' ||
                                        group.parentCode == 'ART12'
                                    ? 'Use only if none of the standard actions apply.'
                                    : 'Will be saved as: ${group.customCode} <your text>',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.check),
                      label: const Text('Save ART actions'),
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) {
      customCtrl.dispose();
      return;
    }

    final customText = customCtrl.text.trim();
    customCtrl.dispose();

    final orderedSelectedCodes = [
      for (final option in group.options)
        if (selected.contains(option.code)) option.code,
    ];

    var generatedText = buildRecommendedActionText(
      selectedCodes: orderedSelectedCodes,
      customText: customText,
      group: group,
    );

    final selectedMappings = buildSelectedActionMappings(
      selectedCodes: orderedSelectedCodes,
      customText: customText,
      group: group,
    );

    if (isArt01LippingMenu && orderedSelectedCodes.contains('ART01b')) {
      selectedMappings
          .removeWhere((m) => (m['uiCode'] ?? '').trim() == 'ART01b');

      final selectedLocationsInOrder = [
        for (final location in art01LocationOptions)
          if (selectedArt01Locations.contains(location)) location,
      ];

      if (selectedLocationsInOrder.isEmpty) {
        selectedMappings.add({
          'sectionArtCode': group.parentCode,
          'visibleLabel': 'ART01b Replace lipping (specify location).',
          'selectedLabel': 'ART01b Replace lipping (specify location).',
          'uiCode': 'ART01b',
          'displayCode': 'ART01b',
          'actualArtCode': 'ART01',
          'actionText': 'Replace lipping (specify location).',
          'customText': null,
        });
      } else {
        for (final location in selectedLocationsInOrder) {
          selectedMappings.add({
            'sectionArtCode': group.parentCode,
            'visibleLabel': 'ART01b Replace lipping ($location).',
            'selectedLabel': 'ART01b Replace lipping ($location).',
            'uiCode': 'ART01b',
            'displayCode': 'ART01b',
            'actualArtCode': 'ART01',
            'actionText': 'Replace lipping ($location).',
            'customText': null,
          });
        }
      }

      final lines = <String>[];
      for (final mapping in selectedMappings) {
        final uiCode = (mapping['uiCode'] ?? '').trim();
        if (uiCode.isEmpty) continue;
        final label =
            (mapping['selectedLabel'] ?? mapping['visibleLabel'] ?? '').trim();
        if (label.isNotEmpty) {
          lines.add(label);
        }
      }
      if (customText.isNotEmpty) {
        lines.add('${group.customCode} $customText');
      }
      generatedText = lines.join('\n');
    }

    if (generatedText.isEmpty && customText.isEmpty) return;

    controller.setInspectionStructuredActions(
      surveyId: widget.surveyId,
      doorId: widget.existingDoorId,
      checkId: definition.id,
      selectedActionCodes: orderedSelectedCodes,
      selectedActionMappings: selectedMappings,
      customActionText: customText,
      generatedRecommendedAction: generatedText,
    );

    // Critical-system actions must always remain failed checks so the
    // per-check photo requirement and remedial urgency flow are enforced.
    final hasCriticalGlazingSelection =
        group.parentCode == 'ART14' && orderedSelectedCodes.contains('ART14e');
    final hasCriticalFireStoppingSelection = group.parentCode == 'ART16' &&
        (orderedSelectedCodes.contains('ART16d') ||
            orderedSelectedCodes.contains('ART16e'));
    final hasCriticalSignageSelection = group.parentCode == 'ART19' &&
        (orderedSelectedCodes.contains('ART19a') ||
            orderedSelectedCodes.contains('ART19b'));
    if (hasCriticalGlazingSelection ||
        hasCriticalFireStoppingSelection ||
        hasCriticalSignageSelection) {
      controller.setInspectionOutcome(
        surveyId: widget.surveyId,
        doorId: widget.existingDoorId,
        checkId: definition.id,
        outcome: InspectionOutcome.fail,
      );
    }
  }

  Future<String?> _pickDoorLocation(BuildContext context,
      {required String currentValue}) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _DoorLocationPickerSheet(
          title: 'Door location',
          options: _standardDoorLocations,
          groupedOptions: _doorLocationGroups,
          initialValue: currentValue,
        );
      },
    );
  }

  Future<String?> _pickFloorLevel(BuildContext context,
      {required String currentValue}) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _FloorLevelPickerSheet(
          title: 'Floor / Level',
          initialValue: currentValue,
        );
      },
    );
  }

  Future<DoorMaterial?> _pickMaterial(BuildContext context,
      {required DoorMaterial currentValue}) async {
    return showModalBottomSheet<DoorMaterial>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _EnumPickerSheet<DoorMaterial>(
          title: 'Material',
          options: _materialOptions,
          initialValue: currentValue,
          labelFor: _materialLabel,
        );
      },
    );
  }

  Future<String?> _pickFrameMaterial(BuildContext context,
      {required String currentValue}) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _SimplePickerSheet(
          title: 'Frame material',
          options: _frameMaterialOptions,
          initialValue: currentValue,
          allowCustom: false,
          confirmLabel: 'Select',
        );
      },
    );
  }

  Future<DoorClassification?> _pickClassification(BuildContext context,
      {required DoorClassification currentValue}) async {
    return showModalBottomSheet<DoorClassification>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _EnumPickerSheet<DoorClassification>(
          title: 'Certification status',
          options: _classificationOptions,
          initialValue: currentValue,
          labelFor: _classificationLabel,
        );
      },
    );
  }

  Future<String?> _pickCertificationBody(BuildContext context,
      {required String currentValue}) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _SimplePickerSheet(
          title: 'Certification scheme',
          options: _certificationBodyOptions,
          initialValue: currentValue,
          allowCustom: true,
          confirmLabel: 'Select',
        );
      },
    );
    if (picked == null) return null;
    if (picked == 'Other (custom)') {
      if (!context.mounted) return null;
      final custom = await _askCustomCertificationBody(context);
      if (!context.mounted) return null;
      return custom;
    }
    return picked;
  }

  Future<String?> _askCustomCertificationBody(BuildContext context) async {
    _customCertificationBodyCtrl.text = _certificationBodyName;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom certification body'),
        content: TextField(
          controller: _customCertificationBodyCtrl,
          decoration: const InputDecoration(
            labelText: 'Certification body',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, _customCertificationBodyCtrl.text.trim()),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    final value = (res ?? '').trim();
    return value.isEmpty ? null : value;
  }

  Future<FireRating?> _pickFireRating(BuildContext context,
      {required FireRating currentValue}) async {
    return showModalBottomSheet<FireRating>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _EnumPickerSheet<FireRating>(
          title: 'Fire rating',
          options: _fireRatingOptions,
          initialValue: currentValue,
          labelFor: _fireRatingLabel,
        );
      },
    );
  }

  Future<GradingLevel?> _pickGrading(BuildContext context,
      {required GradingLevel currentValue}) async {
    return showModalBottomSheet<GradingLevel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _EnumPickerSheet<GradingLevel>(
          title: 'Evidence available',
          options: _gradingOptions,
          initialValue: currentValue,
          labelFor: _gradingLabel,
        );
      },
    );
  }

  Future<DoorConfiguration?> _pickConfiguration(BuildContext context,
      {required DoorConfiguration currentValue}) async {
    return showModalBottomSheet<DoorConfiguration>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _EnumPickerSheet<DoorConfiguration>(
          title: 'Door configuration',
          options: _configurationOptions,
          initialValue: currentValue,
          labelFor: _configurationLabel,
        );
      },
    );
  }

  String _titleForDoor(Door door) {
    final t = door.doorIdTag.trim();
    return t.isEmpty ? 'New Door' : t;
  }

  bool _isNotAFireDoor(FireRating r) => r == FireRating.notAFireDoor;

  bool _smokeSealsRequired(FireRating r) {
    return r == FireRating.fd30s ||
        r == FireRating.fd60s ||
        r == FireRating.fd90s ||
        r == FireRating.fd120s;
  }

  @override
  Widget build(BuildContext context) {
    final workspace = parseInspectionWorkspaceKey(widget.workspaceKey) ??
        InspectionWorkspace.fireDoor;
    final controller =
        ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final survey = ref.watch(
      surveyControllerFamilyProvider(workspace).select((state) {
        for (final item in state.surveys) {
          if (item.id == widget.surveyId) {
            return item;
          }
        }
        return null;
      }),
    );
    final settings = ref.watch(settingsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    if (survey == null) {
      return const Scaffold(body: Center(child: Text('Project not found')));
    }
    final hasCurrentDisclaimer = isDisclaimerAcceptanceCurrent(
      record: survey.disclaimerAcceptance,
      moduleType: inspectionWorkspaceSlug(survey.workspace),
      userId: auth.uid.trim(),
    );

    void syncAutoNotApplicableOutcomes({
      required SurveyController controller,
      bool resetWhenApplicable = false,
    }) {
      final survey = controller.getById(widget.surveyId);
      if (survey == null || survey.type == SurveyType.fireStopping) {
        return;
      }

      final liveDoor = controller.getDoorById(
        surveyId: widget.surveyId,
        doorId: widget.existingDoorId,
      );
      if (liveDoor == null) return;

      for (final check in inspectionChecks) {
        final allowsNotApplicable =
            check.allowedOutcomes.contains(InspectionOutcome.notApplicable);
        if (!allowsNotApplicable) continue;

        final applicable = isCheckApplicable(
          checkId: check.id,
          hasDoorCloser: _hasDoorCloser,
          hasSeals: _hasPerimeterSeals,
          hasGlazing: _hasGlazing,
          hasSignage: _hasSignage,
        );

        final currentOutcome =
            liveDoor.inspectionResults[check.id.name]?.outcome ??
                InspectionOutcome.notAnswered;

        if (!applicable && currentOutcome != InspectionOutcome.notApplicable) {
          controller.setInspectionOutcome(
            surveyId: widget.surveyId,
            doorId: widget.existingDoorId,
            checkId: check.id,
            outcome: InspectionOutcome.notApplicable,
          );
        }

        if (applicable &&
            resetWhenApplicable &&
            currentOutcome == InspectionOutcome.notApplicable) {
          controller.setInspectionOutcome(
            surveyId: widget.surveyId,
            doorId: widget.existingDoorId,
            checkId: check.id,
            outcome: InspectionOutcome.notAnswered,
          );
        }
      }
    }

    final door = survey.doors
        .where((d) => d.id == widget.existingDoorId)
        .toList()
        .firstOrNull;
    if (door == null) {
      return const Scaffold(body: Center(child: Text('Door not found')));
    }
    final isFireStopping = survey.type == SurveyType.fireStopping;

    if (!_loaded) {
      _doorIdTag.text = door.doorIdTag;
      _inspectionDate = door.inspectionDate;

      _floorLevel = door.floor;
      _doorLocation = door.area;

      _material = door.material;
      _customMaterial = door.customMaterial;
      _customMaterialCtrl.text = door.customMaterial;
      _classification = door.classification;
      _certificationBodyName = door.certificationBodyName;
      _fireRating = door.fireRating;
      _gradingLevel = door.gradingLevel;
      _configuration = door.configuration;
      _maintenanceIntervalMonths = door.maintenanceIntervalMonths > 0
          ? door.maintenanceIntervalMonths
          : 12;
      _useCustomMaintenanceInterval =
          !_maintenanceIntervalPresets.contains(_maintenanceIntervalMonths);
      _customMaintenanceInterval.text = _maintenanceIntervalMonths.toString();

      _doorPhotos = door.doorPhotos;
      _approvedMaintainerName.text = door.approvedMaintainerName;
      _approvedMaintainerNumber.text = door.approvedMaintainerNumber;
      _replacementRequired = door.replacementRequired;
      _replacementDoor1WidthCtrl.text = door.replacementDoor1Width;
      _replacementDoor1HeightCtrl.text = door.replacementDoor1Height;
      _replacementDoor2WidthCtrl.text = door.replacementDoor2Width;
      _replacementDoor2HeightCtrl.text = door.replacementDoor2Height;
      _traceabilityNumberCtrl.text = door.approvedMaintainerNumber;
      _reportPreparedByCtrl.text = survey.reportCompletedBy;

      _fireStoppingFireRating = door.fireStoppingFireRating.trim().isNotEmpty
          ? door.fireStoppingFireRating.trim()
          : _legacyFireStoppingRating(door.fireRating);
      _doorDrawingId = door.doorDrawingId.trim();
      _doorPinId = door.doorPinId.trim();
      _hydrateFireStoppingSize(door.fireStoppingSize.trim());
      final fireStoppingQty = door.fireStoppingQuantity > 0
          ? door.fireStoppingQuantity
          : (door.maintenanceIntervalMonths > 0
              ? door.maintenanceIntervalMonths
              : 1);
      _fireStoppingQuantityCtrl.text = fireStoppingQty.toString();
      _fireStoppingDefectDescriptionCtrl.text =
          door.fireStoppingDefectDescription;
      _fireStoppingRecommendedActionCtrl.text =
          door.fireStoppingRecommendedAction;
      _fireStoppingDefects
        ..clear()
        ..addAll(door.fireStoppingDefects);
      if (_fireStoppingDefects.isEmpty) {
        final legacyDescription = door.fireStoppingDefectDescription.trim();
        final legacyAction = door.fireStoppingRecommendedAction.trim();
        if (legacyDescription.isNotEmpty ||
            legacyAction.isNotEmpty ||
            door.doorPhotos.isNotEmpty) {
          _fireStoppingDefects.add(
            FireStoppingDefect(
              id: 'legacy_${DateTime.now().millisecondsSinceEpoch}',
              template: _fireStoppingDefectTemplates.contains(legacyDescription)
                  ? legacyDescription
                  : '',
              fireRating: _fireStoppingFireRating,
              description: legacyDescription,
              recommendedAction: legacyAction,
              lengthMm: _fireStoppingLengthCtrl.text.trim(),
              widthMm: _fireStoppingWidthCtrl.text.trim(),
              drawingId: _fireStoppingDrawingId,
              pinId: _fireStoppingPinId,
              photos:
                  door.doorPhotos.where((m) => !_isVideoAttachment(m)).toList(),
            ),
          );
        }
      }
      final fsMeta = door.fireStoppingItemType.trim();
      if (fsMeta.contains('drawing=')) {
        final parts = fsMeta.split(';');
        for (final part in parts) {
          final eq = part.indexOf('=');
          if (eq <= 0) continue;
          final key = part.substring(0, eq).trim().toLowerCase();
          final val = part.substring(eq + 1).trim();
          if (key == 'drawing') _fireStoppingDrawingId = val;
          if (key == 'pin') _fireStoppingPinId = val;
        }
      }
      if (_doorDrawingId.isEmpty && _fireStoppingDrawingId.isNotEmpty) {
        _doorDrawingId = _fireStoppingDrawingId;
      }
      if (_doorPinId.isEmpty && _fireStoppingPinId.isNotEmpty) {
        _doorPinId = _fireStoppingPinId;
      }
      if (isFireStopping) {
        if (_fireStoppingDrawingId.isEmpty && _doorDrawingId.isNotEmpty) {
          _fireStoppingDrawingId = _doorDrawingId;
        }
        if (_fireStoppingPinId.isEmpty && _doorPinId.isNotEmpty) {
          _fireStoppingPinId = _doorPinId;
        }
      } else {
        _hasGlazing = door.hasGlazing;
        _decodeFireDoorMeta(door.fireStoppingItemType);
      }
      _identificationMode = isFireStopping
          ? (_fireStoppingPinId.trim().isNotEmpty
              ? _IdentificationMode.drawingPin
              : _IdentificationMode.manual)
          : (_doorPinId.trim().isNotEmpty
              ? _IdentificationMode.drawingPin
              : _IdentificationMode.manual);
      _syncFireStoppingDoorPhotosFromDefects();

      _loaded = true;
      // IMPORTANT: Defer provider updates until after widget tree is built
      // to avoid "Tried to modify a provider while the widget tree was building" error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          syncAutoNotApplicableOutcomes(controller: controller);
        }
      });
    }

    final bySection = checksBySection();
    InspectionCheckResult resultFor(InspectionCheckId id) {
      final existing = door.inspectionResults[id.name];
      if (existing != null) return existing;

      final def = checkDef(id);
      return InspectionCheckResult(
        outcome: InspectionOutcome.notAnswered,
        recommendedAction: def.recommendedAction,
        comment: '',
        photos: const [],
      );
    }

    bool hasFailDetails(InspectionCheckResult result) {
      return result.comment.trim().isNotEmpty ||
          result.recommendedAction.trim().isNotEmpty ||
          result.photos.isNotEmpty ||
          result.gapTopMm != null ||
          result.gapBottomMm != null ||
          result.gapLeftMm != null ||
          result.gapRightMm != null ||
          result.gapMeetingMm != null ||
          result.selectedActionCodes.isNotEmpty ||
          result.selectedActionMappings.isNotEmpty ||
          result.customActionText.trim().isNotEmpty ||
          result.optionalVideoPath.trim().isNotEmpty;
    }

    bool configurationHasMeetingGap(DoorConfiguration configuration) {
      return configuration == DoorConfiguration.doubleLeaf ||
          configuration == DoorConfiguration.leafAndAHalf;
    }

    void applyDoorConfiguration(DoorConfiguration configuration) {
      final previousConfiguration = _configuration;
      if (previousConfiguration == configuration) {
        return;
      }

      setState(() {
        _configuration = configuration;
      });

      final shouldClearMeetingGap =
          configuration == DoorConfiguration.singleLeaf &&
              configurationHasMeetingGap(previousConfiguration);
      if (!shouldClearMeetingGap) {
        return;
      }

      final gapResult = resultFor(InspectionCheckId.doorGapsIncorrect);
      if (gapResult.gapMeetingMm == null) {
        return;
      }

      controller.setInspectionGaps(
        surveyId: widget.surveyId,
        doorId: widget.existingDoorId,
        checkId: InspectionCheckId.doorGapsIncorrect,
        topMm: gapResult.gapTopMm,
        bottomMm: gapResult.gapBottomMm,
        leftMm: gapResult.gapLeftMm,
        rightMm: gapResult.gapRightMm,
        meetingMm: null,
      );
    }

    Future<bool> confirmPassClearsFailDetails() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change to PASS?'),
          content: const Text(
              'Changing to PASS will remove fail details. Continue?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      return confirmed == true;
    }

    Future<void> handleInspectionOutcomeChange({
      required InspectionCheckDefinition definition,
      required InspectionCheckResult result,
      required InspectionOutcome nextOutcome,
    }) async {
      if (result.outcome == nextOutcome) {
        return;
      }

      final switchingToPass = nextOutcome == InspectionOutcome.pass;
      final leavingFailState = result.outcome == InspectionOutcome.fail ||
          result.outcome == InspectionOutcome.criticalFail ||
          result.outcome == InspectionOutcome.advisory;
      final shouldClearDetails =
          switchingToPass && leavingFailState && hasFailDetails(result);

      if (shouldClearDetails) {
        final confirmed = await confirmPassClearsFailDetails();
        if (!confirmed) {
          return;
        }
      }

      controller.setInspectionOutcome(
        surveyId: widget.surveyId,
        doorId: widget.existingDoorId,
        checkId: definition.id,
        outcome: nextOutcome,
        clearFailDetails: shouldClearDetails,
      );
    }

    bool sectionAllowsNotApplicable(InspectionSection section) {
      return section == InspectionSection.glazingSeals;
    }

    _SectionGateOutcome? sectionGateOutcome(
      InspectionSection section,
      List<InspectionCheckDefinition> checks,
    ) {
      if (checks.isEmpty) return null;

      if (_forceExpandedFailSections.contains(section)) {
        return _SectionGateOutcome.fail;
      }

      final outcomes = checks.map((c) => resultFor(c.id).outcome).toList();
      final hasFail = outcomes.any(
        (o) =>
            o == InspectionOutcome.fail ||
            o == InspectionOutcome.criticalFail ||
            o == InspectionOutcome.advisory,
      );
      if (hasFail) return _SectionGateOutcome.fail;

      final allPass = outcomes.every((o) => o == InspectionOutcome.pass);
      if (allPass) return _SectionGateOutcome.pass;

      if (sectionAllowsNotApplicable(section) &&
          outcomes.every((o) => o == InspectionOutcome.notApplicable)) {
        return _SectionGateOutcome.notApplicable;
      }

      return null;
    }

    bool sectionExpandedOnFail(
      InspectionSection section,
      List<InspectionCheckDefinition> checks,
    ) {
      return sectionGateOutcome(section, checks) == _SectionGateOutcome.fail;
    }

    Future<void> setSectionGateOutcome({
      required InspectionSection section,
      required List<InspectionCheckDefinition> checks,
      required _SectionGateOutcome choice,
    }) async {
      if (choice == _SectionGateOutcome.fail) {
        setState(() {
          _forceExpandedFailSections.add(section);
        });
        return;
      }

      final targetOutcome = choice == _SectionGateOutcome.notApplicable
          ? InspectionOutcome.notApplicable
          : InspectionOutcome.pass;

      final shouldClearDetails = targetOutcome == InspectionOutcome.pass &&
          checks.any((check) {
            final result = resultFor(check.id);
            final isFailState = result.outcome == InspectionOutcome.fail ||
                result.outcome == InspectionOutcome.criticalFail ||
                result.outcome == InspectionOutcome.advisory;
            return isFailState && hasFailDetails(result);
          });

      if (shouldClearDetails) {
        final confirmed = await confirmPassClearsFailDetails();
        if (!confirmed) {
          return;
        }
      }

      for (final check in checks) {
        if (!check.allowedOutcomes.contains(targetOutcome)) continue;
        controller.setInspectionOutcome(
          surveyId: widget.surveyId,
          doorId: widget.existingDoorId,
          checkId: check.id,
          outcome: targetOutcome,
          clearFailDetails: shouldClearDetails,
        );
      }

      if (mounted) {
        setState(() {
          _forceExpandedFailSections.remove(section);
        });
      }
    }

    int unansweredCount() => inspectionChecks.where((c) {
          return resultFor(c.id).outcome == InspectionOutcome.notAnswered;
        }).length;

    int startedCount() => inspectionChecks.where((c) {
          return resultFor(c.id).outcome != InspectionOutcome.notAnswered;
        }).length;

    int defectCount() => inspectionChecks.where((c) {
          final o = resultFor(c.id).outcome;
          return o == InspectionOutcome.fail ||
              o == InspectionOutcome.criticalFail;
        }).length;

    int failedChecksMissingPhotoCount() => inspectionChecks.where((c) {
          final result = resultFor(c.id);
          final outcome = result.outcome;
          final isFail = outcome == InspectionOutcome.fail ||
              outcome == InspectionOutcome.criticalFail;
          return isFail && result.photos.isEmpty;
        }).length;

    Color outcomeColor(InspectionOutcome o) {
      switch (o) {
        case InspectionOutcome.pass:
          return Colors.green;
        case InspectionOutcome.advisory:
          return Colors.amber;
        case InspectionOutcome.fail:
          return Colors.red;
        case InspectionOutcome.criticalFail:
          return const Color(0xFF8B0000);
        case InspectionOutcome.notApplicable:
          return Colors.grey;
        case InspectionOutcome.notAnswered:
          return Colors.black45;
      }
    }

    String artPreview(InspectionCheckId id, InspectionOutcome o) {
      final art = autoArtCodeForOutcome(checkId: id, outcome: o);
      if (art == null) return '-';
      return 'ART${art.toString().padLeft(2, '0')}';
    }

    String resultBadgeText() {
      if (isFireStopping) {
        if (door.approvedAt != null) return 'Completed';
        return 'Action Required';
      }
      if (_isNotAFireDoor(_fireRating)) return 'N/A';
      if (_replacementRequired) return 'FAIL';
      if (startedCount() == 0) return 'Not inspected';
      if (defectCount() > 0) return 'FAIL';
      if (unansweredCount() > 0) return 'In progress';
      return 'PASS';
    }

    bool needsPhotoEvidence() {
      if (_isNotAFireDoor(_fireRating)) return false;
      return defectCount() > 0;
    }

    final imageAttachments =
        _doorPhotos.where((m) => !_isVideoAttachment(m)).toList();
    final videoAttachments = isFireStopping
        ? const <PhotoAttachment>[]
        : _doorPhotos.where((m) => _isVideoAttachment(m)).toList();
    final allPinCandidates = controller.getDrawingPinCandidates(survey.id);
    final fireStoppingPinCandidates = isFireStopping
        ? allPinCandidates
        : const <({ProjectDrawing drawing, FloorPlanPin pin})>[];
    final doorPlanPinCandidates = isFireStopping
        ? const <({ProjectDrawing drawing, FloorPlanPin pin})>[]
        : allPinCandidates;
    final selectedFireStoppingPin = isFireStopping
        ? fireStoppingPinCandidates
            .cast<({ProjectDrawing drawing, FloorPlanPin pin})?>()
            .firstWhere(
              (entry) => entry != null && entry.pin.id == _fireStoppingPinId,
              orElse: () => null,
            )
        : null;
    final selectedDoorPlanPin = !isFireStopping
        ? doorPlanPinCandidates
            .cast<({ProjectDrawing drawing, FloorPlanPin pin})?>()
            .firstWhere(
              (entry) => entry != null && entry.pin.id == _doorPinId,
              orElse: () => null,
            )
        : null;
    final isSnagging = survey.type == SurveyType.snagging;
    final useDrawingPin = _identificationMode == _IdentificationMode.drawingPin;
    final identificationTitle = isFireStopping
        ? 'Item Identification'
        : (isSnagging ? 'Snag Identification' : 'Door Identification');
    final idLabel = isFireStopping
        ? 'Item ID / Ref (required)'
        : (isSnagging
            ? 'Snag ID / Ref (required)'
            : 'Door ID / Ref (required)');

    Future<String?> askAfterSaveChoice() async {
      return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isFireStopping ? 'Item saved' : 'Door saved'),
          content: const Text('Choose what to do next.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'back'),
              child: Text(
                  isFireStopping ? 'Back to Report' : 'Back to doors list'),
            ),
            if (isFireStopping)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'new_pin'),
                child: const Text('Add New PIN'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'next'),
              child:
                  Text(isFireStopping ? 'Add Another Item' : 'Add next door'),
            ),
          ],
        ),
      );
    }

    Future<bool> saveDoor({bool popAfterSave = true}) async {
      DoorResult derivePersistedDoorResult(Door currentDoor) {
        if (_replacementRequired) return DoorResult.fail;
        if (currentDoor.inspectionResults.isEmpty) return DoorResult.pass;

        var hasAnswered = false;
        var hasAdvisory = false;
        var hasFail = false;

        for (final result in currentDoor.inspectionResults.values) {
          if (result.outcome == InspectionOutcome.notAnswered ||
              result.outcome == InspectionOutcome.notApplicable) {
            continue;
          }
          hasAnswered = true;

          if (result.outcome == InspectionOutcome.fail ||
              result.outcome == InspectionOutcome.criticalFail) {
            hasFail = true;
          } else if (result.outcome == InspectionOutcome.advisory) {
            hasAdvisory = true;
          }
        }

        if (hasFail) return DoorResult.fail;
        if (hasAdvisory) return DoorResult.advisory;
        if (hasAnswered) return DoorResult.pass;
        return DoorResult.pass;
      }

      final isPinMode = _identificationMode == _IdentificationMode.drawingPin;
      final selectedPinLabel = isFireStopping
          ? (selectedFireStoppingPin == null
              ? ''
              : (selectedFireStoppingPin.pin.label.trim().isNotEmpty
                  ? selectedFireStoppingPin.pin.label.trim()
                  : selectedFireStoppingPin.pin.doorNumber.trim()))
          : (selectedDoorPlanPin == null
              ? ''
              : (selectedDoorPlanPin.pin.label.trim().isNotEmpty
                  ? selectedDoorPlanPin.pin.label.trim()
                  : selectedDoorPlanPin.pin.doorNumber.trim()));
      final tag = isFireStopping
          ? (isPinMode ? selectedPinLabel : _doorIdTag.text.trim())
          : (isPinMode && selectedPinLabel.isNotEmpty
              ? selectedPinLabel
              : _doorIdTag.text.trim());
      if (tag.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPinMode
                  ? 'Select Pin before saving.'
                  : (survey.type == SurveyType.snagging
                      ? 'Snag ID / Ref is required.'
                      : (isFireStopping
                          ? 'Item ID / Ref is required.'
                          : 'Door ID / Ref is required.')),
            ),
          ),
        );
        return false;
      }

      final disclaimerRecord = survey.disclaimerAcceptance;
      final disclaimerInspectorName =
          disclaimerRecord?.inspectorName.trim() ?? '';
      final disclaimerAcceptedAt = disclaimerRecord?.disclaimerAcceptedAt;
      final requireEvidence = needsPhotoEvidence();
      final missingFailPhotos = failedChecksMissingPhotoCount();
      final replacementOpeningWidth = _replacementDoor1WidthCtrl.text.trim();
      final replacementOpeningHeight = _replacementDoor1HeightCtrl.text.trim();
      final replacementEvidencePhotoCount = _certPhotoIds
          .where((id) => _doorPhotos.any((photo) => photo.id == id))
          .length;

      if (!isFireStopping &&
          !_isNotAFireDoor(_fireRating) &&
          disclaimerInspectorName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Complete the disclaimer form before saving this door.')),
        );
        return false;
      }
      if (!isFireStopping && missingFailPhotos > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Add at least 1 photo to each failed item before saving ($missingFailPhotos missing).',
            ),
          ),
        );
        return false;
      }
      if (!isFireStopping && _replacementRequired) {
        if (replacementOpeningWidth.isEmpty ||
            replacementOpeningHeight.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Enter opening width and opening height for full doorset replacement.',
              ),
            ),
          );
          return false;
        }
        if (replacementEvidencePhotoCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Add at least 1 replacement evidence photo before saving.',
              ),
            ),
          );
          return false;
        }
      }
      // When defects exist, per-check photos are the required evidence.
      // The general door photo section is optional in that case.
      // Block only when ALL checks pass and no door photo is provided.
      if (!requireEvidence && _doorPhotos.isEmpty) {
        // Allow save; general photo is encouraged but not blocking when all pass
        // (Removed hard block — the warning banner handles guidance)
      }

      try {
        final hasDefects = _fireStoppingDefects.isNotEmpty;
        final firstDefect = hasDefects ? _fireStoppingDefects.first : null;
        final normalizedFireStoppingDefects = isFireStopping
            ? [
                for (final defect in _fireStoppingDefects)
                  defect.copyWith(serviceType: '')
              ]
            : const <FireStoppingDefect>[];
        if (isFireStopping) {
          _syncFireStoppingDoorPhotosFromDefects();
          controller.updateSurveyMeta(
            surveyId: widget.surveyId,
            reportCompletedBy: _reportPreparedByCtrl.text.trim(),
          );
        }
        final fsDrawingId = _fireStoppingDrawingId.trim().isNotEmpty
            ? _fireStoppingDrawingId.trim()
            : _doorDrawingId.trim();
        final fsPinId = _fireStoppingPinId.trim().isNotEmpty
            ? _fireStoppingPinId.trim()
            : _doorPinId.trim();
        final fireDoorMeta = _encodeFireDoorMeta();
        final fireStoppingMeta = (fsDrawingId.isNotEmpty || fsPinId.isNotEmpty)
            ? 'drawing=$fsDrawingId;pin=$fsPinId'
            : '';
        controller.updateDoor(
          surveyId: widget.surveyId,
          doorId: widget.existingDoorId,
          update: (d) => d.copyWith(
            inspectionDate: _inspectionDate,
            doorIdTag: tag,
            floor: _floorLevel.trim(),
            area: _doorLocation.trim(),
            material: isFireStopping ? DoorMaterial.otherCustom : _material,
            customMaterial: isFireStopping
                ? ''
                : (_material == DoorMaterial.otherCustom
                    ? _customMaterial.trim()
                    : ''),
            classification: isFireStopping
                ? DoorClassification.unknownNotVerified
                : _classification,
            certificationBodyName: isFireStopping
                ? ''
                : (_classification == DoorClassification.thirdPartyCertified
                    ? _certificationBodyName.trim()
                    : ''),
            fireRating: isFireStopping
                ? _legacyFireRatingFromFireStopping(
                    firstDefect?.fireRating.trim().isNotEmpty == true
                        ? firstDefect!.fireRating.trim()
                        : _fireStoppingFireRating)
                : _fireRating,
            gradingLevel: _gradingLevel,
            configuration: _configuration,
            hasGlazing: _hasGlazing,
            result: isFireStopping ? d.result : derivePersistedDoorResult(d),
            maintenanceIntervalMonths:
                isFireStopping ? 1 : _maintenanceIntervalMonths,
            fireStoppingItemType:
                isFireStopping ? fireStoppingMeta : fireDoorMeta,
            fireStoppingFireRating:
                isFireStopping ? (firstDefect?.fireRating.trim() ?? '') : '',
            fireStoppingServiceType: '',
            fireStoppingSize: isFireStopping
                ? (() {
                    final length = firstDefect?.lengthMm.trim() ?? '';
                    final width = firstDefect?.widthMm.trim() ?? '';
                    if (length.isEmpty && width.isEmpty) return '';
                    return 'length=$length;width=$width';
                  })()
                : '',
            fireStoppingQuantity: 1,
            fireStoppingDefectDescription: isFireStopping
                ? (firstDefect?.description.trim() ??
                    _fireStoppingDefectDescriptionCtrl.text.trim())
                : '',
            fireStoppingRecommendedAction: isFireStopping
                ? (firstDefect?.recommendedAction.trim() ??
                    _fireStoppingRecommendedActionCtrl.text.trim())
                : '',
            fireStoppingVideoUrl: '',
            fireStoppingDefects: normalizedFireStoppingDefects,
            remedialStatus:
                isFireStopping ? RemedialStatus.pending : d.remedialStatus,
            doorPhotos: _doorPhotos,
            approvedMaintainerName: isFireStopping
                ? d.approvedMaintainerName
                : disclaimerInspectorName,
            approvedMaintainerNumber: isFireStopping
                ? d.approvedMaintainerNumber
                : _traceabilityNumberCtrl.text.trim(),
            approvedBy: isFireStopping ? d.approvedBy : disclaimerInspectorName,
            approvedAt: isFireStopping
                ? d.approvedAt
                : (disclaimerAcceptedAt ?? d.approvedAt ?? DateTime.now()),
            clearApprovedAt:
                isFireStopping ? false : disclaimerInspectorName.isEmpty,
            doorDrawingId: isFireStopping
                ? (_fireStoppingDrawingId.trim().isNotEmpty
                    ? _fireStoppingDrawingId.trim()
                    : _doorDrawingId.trim())
                : _doorDrawingId.trim(),
            doorPinId: isFireStopping
                ? (_fireStoppingPinId.trim().isNotEmpty
                    ? _fireStoppingPinId.trim()
                    : _doorPinId.trim())
                : _doorPinId.trim(),
            replacementRequired:
                isFireStopping ? d.replacementRequired : _replacementRequired,
            replacementDoor1Width: isFireStopping
                ? d.replacementDoor1Width
                : _replacementDoor1WidthCtrl.text.trim(),
            replacementDoor1Height: isFireStopping
                ? d.replacementDoor1Height
                : _replacementDoor1HeightCtrl.text.trim(),
            replacementDoor2Width: isFireStopping
                ? d.replacementDoor2Width
                : _replacementDoor2WidthCtrl.text.trim(),
            replacementDoor2Height: isFireStopping
                ? d.replacementDoor2Height
                : _replacementDoor2HeightCtrl.text.trim(),
          ),
        );

        _savedOnce = true;

        if (!context.mounted) return false;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isFireStopping ? 'Item saved' : 'Door saved')),
        );
        if (popAfterSave) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            context.go('${widget.routePrefix}/${widget.surveyId}/doors');
          }
        }
        return true;
      } on StateError catch (e) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
        return false;
      }
    }

    Widget checkRow(InspectionCheckDefinition def) {
      final r = resultFor(def.id);
      final o = r.outcome;
      final selectedDisplayCodes = <String, String>{
        for (final mapping in r.selectedActionMappings)
          if ((mapping['uiCode'] ?? '').trim().isNotEmpty)
            (mapping['uiCode'] ?? '').trim():
                ((mapping['displayCode'] ?? '').trim().isNotEmpty
                    ? (mapping['displayCode'] ?? '').trim()
                    : (mapping['uiCode'] ?? '').trim()),
      };

      final showDetails =
          o != InspectionOutcome.notAnswered && o != InspectionOutcome.pass;
      final showArt =
          o == InspectionOutcome.fail || o == InspectionOutcome.criticalFail;
      final needsPhoto = showArt;

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(def.title,
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (o != InspectionOutcome.notAnswered) ...[
                    const SizedBox(width: 10),
                    Text(
                      inspectionOutcomeLabel(o),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: outcomeColor(o),
                          fontSize: 12),
                    ),
                  ],
                ],
              ),
              if (o == InspectionOutcome.notAnswered) ...[
                const SizedBox(height: 2),
                Text(
                  def.helperText,
                  style: const TextStyle(color: Colors.black45, fontSize: 12),
                ),
              ],
              const SizedBox(height: 6),
              SegmentedButton<InspectionOutcome>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>(
                      (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      // Color will be determined by label; we use a neutral color here
                      return Colors.grey.shade200;
                    }
                    return Colors.transparent;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith<Color>(
                      (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.black87;
                    }
                    return Colors.grey.shade700;
                  }),
                  side: WidgetStateProperty.resolveWith<BorderSide>(
                      (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return BorderSide(
                          color: Colors.grey.shade400, width: 1.5);
                    }
                    return BorderSide(color: Colors.grey.shade300, width: 1);
                  }),
                ),
                segments: [
                  for (final allowed in def.allowedOutcomes)
                    ButtonSegment<InspectionOutcome>(
                      value: allowed,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: outcomeColor(allowed),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(inspectionOutcomeLabel(allowed)),
                        ],
                      ),
                    ),
                ],
                selected: def.allowedOutcomes.contains(o)
                    ? {o}
                    : <InspectionOutcome>{},
                onSelectionChanged: (selection) async {
                  if (selection.isEmpty) return;
                  await handleInspectionOutcomeChange(
                    definition: def,
                    result: r,
                    nextOutcome: selection.first,
                  );
                },
              ),
              if (showArt) ...[
                const SizedBox(height: 12),
                Text(
                  'Auto ART: ${artPreview(def.id, o)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: outcomeColor(o)),
                ),
              ],
              if (showDetails) ...[
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: r.comment,
                  onChanged: (v) => controller.setInspectionComment(
                    surveyId: widget.surveyId,
                    doorId: widget.existingDoorId,
                    checkId: def.id,
                    comment: v,
                  ),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Inspector comment / notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                // ── ART multi-select button (config-driven for every check) ──
                if (artGroupForCheck(def.id) != null &&
                    (o == InspectionOutcome.fail ||
                        o == InspectionOutcome.criticalFail)) ...[
                  SizedBox(
                    width: double.infinity,
                    child: r.selectedActionCodes.isEmpty
                        ? FilledButton.icon(
                            onPressed: () => _pickRecommendedActionsForCheck(
                              controller: controller,
                              definition: def,
                              result: r,
                            ),
                            icon: const Icon(Icons.playlist_add_check_outlined,
                                size: 18),
                            label: Text(
                                'Choose ${artGroupForCheck(def.id)!.parentCode} actions'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => _pickRecommendedActionsForCheck(
                              controller: controller,
                              definition: def,
                              result: r,
                            ),
                            icon: const Icon(Icons.playlist_add_check_outlined,
                                size: 18),
                            label: Text(
                                'Edit ${artGroupForCheck(def.id)!.parentCode} actions'),
                          ),
                  ),
                  // Show which codes are currently selected as compact chips
                  if (r.selectedActionCodes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final code in r.selectedActionCodes)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF5FB),
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: const Color(0xFFCCDBEE)),
                            ),
                            child: Text(
                              selectedDisplayCodes[code] ?? code,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ),
                        if (r.customActionText.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F3F3),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Text(
                              '${artGroupForCheck(def.id)!.customCode} custom',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  key: ValueKey(
                      '${def.id.name}_action_${r.recommendedAction.length}'),
                  initialValue: r.recommendedAction,
                  onChanged: (v) => controller.setInspectionRecommendedAction(
                    surveyId: widget.surveyId,
                    doorId: widget.existingDoorId,
                    checkId: def.id,
                    recommendedAction: v,
                  ),
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Recommended action',
                    helperText: artGroupForCheck(def.id) != null
                        ? 'Auto-filled from selector – you can edit freely'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                // ── Optional video record for door closer ─────────────────
                if (def.id == InspectionCheckId.doorCloserNotOperating &&
                    (o == InspectionOutcome.fail ||
                        o == InspectionOutcome.criticalFail)) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final video =
                          await picker.pickVideo(source: ImageSource.camera);
                      if (video == null || !context.mounted) return;
                      final auth = ref.read(authControllerProvider);
                      final companyId = auth.companyId;
                      if (companyId == null || companyId.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Company workspace is missing.')),
                        );
                        return;
                      }

                      final bytes = await video.readAsBytes();
                      if (!context.mounted) return;

                      final repo = ref.read(companyFileRepositoryProvider);
                      final fallbackName =
                          'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
                      final fileName = video.name.trim().isEmpty
                          ? fallbackName
                          : video.name.trim();

                      try {
                        final record = await repo.uploadBytes(
                          companyId: companyId,
                          entityType: 'inspectionVideo',
                          entityId: widget.surveyId,
                          createdByUid: auth.uid,
                          fileName: fileName,
                          bytes: bytes,
                          mimeType: _mimeForVideoName(fileName),
                          kind: CompanyFileKind.video,
                          tags: [
                            widget.surveyId,
                            widget.existingDoorId,
                            def.id.name
                          ],
                        );

                        if (!context.mounted) return;

                        controller.setInspectionStructuredActions(
                          surveyId: widget.surveyId,
                          doorId: widget.existingDoorId,
                          checkId: def.id,
                          selectedActionCodes: r.selectedActionCodes,
                          selectedActionMappings: r.selectedActionMappings,
                          customActionText: r.customActionText,
                          generatedRecommendedAction: r.recommendedAction,
                          optionalVideoPath: record.downloadUrl,
                        );

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('Video recorded: ${record.fileId}')),
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Video upload failed. Please try again.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.videocam_outlined),
                    label:
                        const Text('Record door closing operation (optional)'),
                  ),
                  if (r.optionalVideoPath.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Video recorded: ${_videoLabelFromPath(r.optionalVideoPath)}',
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ],
                if (def.id == InspectionCheckId.doorGapsIncorrect &&
                    (o == InspectionOutcome.fail ||
                        o == InspectionOutcome.criticalFail)) ...[
                  const SizedBox(height: 10),
                  const Text('Gap measurements (mm)',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _GapGrid(
                    top: r.gapTopMm,
                    bottom: r.gapBottomMm,
                    left: r.gapLeftMm,
                    right: r.gapRightMm,
                    meeting: r.gapMeetingMm,
                    showMeeting: configurationHasMeetingGap(_configuration),
                    onChanged: (top, bottom, left, right, meeting) {
                      controller.setInspectionGaps(
                        surveyId: widget.surveyId,
                        doorId: widget.existingDoorId,
                        checkId: def.id,
                        topMm: top,
                        bottomMm: bottom,
                        leftMm: left,
                        rightMm: right,
                        meetingMm: meeting,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 10),
                // Required-photo warning
                if (needsPhoto && r.photos.isEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF5350)),
                    ),
                    child: const Text(
                      'At least 1 photo is required for each failed item.',
                      style: TextStyle(
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                // Existing photo thumbnails with per-photo delete + fullscreen tap
                if (r.photos.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int pi = 0; pi < r.photos.length; pi++)
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              GestureDetector(
                                onTap: () => showPhotoViewer(
                                  context: context,
                                  photos: r.photos.map((p) => p.bytes).toList(),
                                  initialIndex: pi,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    Uint8List.fromList(r.photos[pi].bytes),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () {
                                    final updated = [...r.photos];
                                    updated.removeAt(pi);
                                    controller.setInspectionPhotos(
                                      surveyId: widget.surveyId,
                                      doorId: widget.existingDoorId,
                                      checkId: def.id,
                                      photos: updated,
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    padding: const EdgeInsets.all(3),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                // Take Photo + Upload Photo
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final photo = await _takePhoto();
                          if (photo == null) return;
                          controller.addInspectionPhotos(
                            surveyId: widget.surveyId,
                            doorId: widget.existingDoorId,
                            checkId: def.id,
                            photos: [photo],
                          );
                        },
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Take Photo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await _pickPhotos();
                          if (picked.isEmpty) return;
                          controller.addInspectionPhotos(
                            surveyId: widget.surveyId,
                            doorId: widget.existingDoorId,
                            checkId: def.id,
                            photos: picked,
                          );
                        },
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload Photo'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget compactGrid(List<Widget> children) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final useTwoColumns = constraints.maxWidth >= 760;
          final itemWidth = useTwoColumns
              ? (constraints.maxWidth - gap) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final child in children)
                SizedBox(width: itemWidth, child: child),
            ],
          );
        },
      );
    }

    Widget sectionGateButtons({
      required InspectionSection section,
      required List<InspectionCheckDefinition> checks,
    }) {
      final gate = sectionGateOutcome(section, checks);

      Widget gateButton(
        String label,
        _SectionGateOutcome value,
        Color selectedColor,
      ) {
        final selected = gate == value;
        return Expanded(
          child: FilledButton(
            onPressed: () {
              setSectionGateOutcome(
                section: section,
                checks: checks,
                choice: value,
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: selected ? selectedColor : Colors.white,
              foregroundColor:
                  selected ? Colors.white : const Color(0xFF263238),
              side: BorderSide(
                color: selected ? selectedColor : const Color(0xFFCFD8DC),
              ),
              elevation: selected ? 1 : 0,
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        );
      }

      return Row(
        children: [
          gateButton('Pass', _SectionGateOutcome.pass, const Color(0xFF2E7D32)),
          const SizedBox(width: 8),
          gateButton('Fail', _SectionGateOutcome.fail, const Color(0xFFC62828)),
          if (sectionAllowsNotApplicable(section)) ...[
            const SizedBox(width: 8),
            gateButton('N/A', _SectionGateOutcome.notApplicable,
                const Color(0xFF546E7A)),
          ],
        ],
      );
    }

    Card sectionCard(
      InspectionSection section,
      List<InspectionCheckDefinition> checks,
    ) {
      final answeredInSection = checks
          .where(
              (c) => resultFor(c.id).outcome != InspectionOutcome.notAnswered)
          .length;
      final defectsInSection = checks.where((c) {
        final o = resultFor(c.id).outcome;
        return o == InspectionOutcome.fail ||
            o == InspectionOutcome.criticalFail;
      }).length;
      final sectionSummary = '$answeredInSection/${checks.length} answered'
          '${defectsInSection > 0 ? ' • $defectsInSection defect${defectsInSection == 1 ? '' : 's'}' : ''}';
      final isExpanded = sectionExpandedOnFail(section, checks);

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inspectionSectionTitle(section),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                sectionSummary,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Text(
                inspectionSectionHelper(section),
                style: const TextStyle(color: Colors.black45, fontSize: 12),
              ),
              const SizedBox(height: 8),
              sectionGateButtons(section: section, checks: checks),
              if (isExpanded) ...[
                const SizedBox(height: 10),
                for (final c in checks) ...[
                  checkRow(c),
                  const SizedBox(height: 8),
                ],
              ] else ...[
                const SizedBox(height: 8),
                const Text(
                  'Details stay hidden until this section is marked Fail.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget detailsSection({
      required String title,
      required IconData icon,
      required List<Widget> children,
      Widget? headerTrailing,
    }) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                  if (headerTrailing != null) ...[
                    const SizedBox(width: 8),
                    headerTrailing,
                  ],
                ],
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );
    }

    Widget compactSelectRow({
      required String label,
      required String value,
      required VoidCallback onTap,
      bool warning = false,
    }) {
      final valueColor = Colors.black87;
      final bgColor = Colors.white;
      final borderColor = Colors.grey.shade300;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 2),
                      Text(
                        value.trim().isEmpty ? 'Not specified' : value,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: valueColor),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
    }

    List<String> missingSaveRequirements() {
      final list = <String>[];
      if (useDrawingPin) {
        if ((isFireStopping ? selectedFireStoppingPin : selectedDoorPlanPin) ==
            null) {
          list.add('select a drawing pin');
        }
      } else if (_doorIdTag.text.trim().isEmpty) {
        list.add(isSnagging ? 'enter Snag ID / Ref' : 'enter Door ID / Ref');
      }
      if (!isFireStopping) {
        final missingFailPhotos = failedChecksMissingPhotoCount();
        if (missingFailPhotos > 0) {
          list.add(
              'add fail photos for $missingFailPhotos check${missingFailPhotos == 1 ? '' : 's'}');
        }
        if (_replacementRequired) {
          if (_replacementDoor1WidthCtrl.text.trim().isEmpty ||
              _replacementDoor1HeightCtrl.text.trim().isEmpty) {
            list.add('enter opening width and opening height');
          }
          final replacementEvidencePhotoCount = _certPhotoIds
              .where((id) => _doorPhotos.any((photo) => photo.id == id))
              .length;
          if (replacementEvidencePhotoCount == 0) {
            list.add('add at least 1 replacement evidence photo');
          }
        }
      }
      return list;
    }

    Future<void> addCategorizedPhotos(Set<String> targetIds) async {
      final picked = await _pickPhotos();
      if (picked.isEmpty) return;
      setState(() {
        _doorPhotos = [..._doorPhotos, ...picked];
        targetIds.addAll(picked.map((p) => p.id));
      });
    }

    final answered = _isNotAFireDoor(_fireRating) ? 0 : startedCount();
    final total = _isNotAFireDoor(_fireRating) ? 0 : inspectionChecks.length;
    final defects = _isNotAFireDoor(_fireRating) ? 0 : defectCount();
    final missingFailPhotos =
        _isNotAFireDoor(_fireRating) ? 0 : failedChecksMissingPhotoCount();
    final showInspectorSignatureSection = !_isNotAFireDoor(_fireRating);
    final doorResultLabel = resultBadgeText();
    final canSavePrimary = useDrawingPin
        ? (isFireStopping
            ? selectedFireStoppingPin != null
            : selectedDoorPlanPin != null)
        : _doorIdTag.text.trim().isNotEmpty;
    final saveRequirements = missingSaveRequirements();

    final useFireDoorWebShell = kIsWeb && widget.workspaceKey == 'fire-door';
    final pageScaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: useFireDoorWebShell
          ? const PreferredSize(
              preferredSize: Size.fromHeight(0),
              child: SizedBox.shrink(),
            )
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(isFireStopping
                  ? _titleForDoor(door).replaceAll('Door', 'Item')
                  : _titleForDoor(door)),
              bottom: WorkspaceSwitchCardsBar(
                  currentWorkspaceKey: widget.workspaceKey),
              actions: [
                IconButton(
                  tooltip: 'Generate PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () async {
                    try {
                      await _exportDoorPdf(
                          context: context,
                          survey: survey,
                          door: door,
                          settings: settings);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('PDF export failed: $e')),
                      );
                    }
                  },
                ),
                IconButton(
                  tooltip: 'View Project Drawing',
                  icon: const Icon(Icons.map_outlined),
                  onPressed: () async {
                    final result = await ProjectDrawingAccess.showDrawingPicker(
                      context: context,
                      survey: survey,
                      preferredLevel: _floorLevel,
                    );
                    if (!context.mounted || result == null) return;
                    _assignFireStoppingPin(
                      drawing: result.drawing,
                      pin: result.pin,
                      addDefect: result.addDefect,
                    );
                  },
                ),
              ],
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          detailsSection(
            title: 'Location / Identification',
            icon: isFireStopping
                ? Icons.inventory_2_outlined
                : Icons.door_sliding_outlined,
            headerTrailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_fmtDateCompact(_inspectionDate)}, ${_fmtTime(_inspectionDate)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: _inspectionDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (pickedDate == null || !context.mounted) return;
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_inspectionDate),
                    );
                    if (pickedTime == null) return;
                    setState(
                      () => _inspectionDate = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: const Size(0, 0),
                  ),
                  child: const Text('Change'),
                ),
              ],
            ),
            children: [
              Text(
                identificationTitle,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              RadioListTile<_IdentificationMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _IdentificationMode.manual,
                groupValue: _identificationMode,
                title: const Text('Enter manually'),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _identificationMode = value;
                    _doorPinId = '';
                    _doorDrawingId = '';
                    _fireStoppingPinId = '';
                    _fireStoppingDrawingId = '';
                  });
                },
              ),
              RadioListTile<_IdentificationMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _IdentificationMode.drawingPin,
                groupValue: _identificationMode,
                title: const Text('Use drawing pin'),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _identificationMode = value;
                    _doorIdTag.clear();
                  });
                },
              ),
              const SizedBox(height: 8),
              if (!useDrawingPin)
                TextField(
                  controller: _doorIdTag,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: idLabel,
                    border: const OutlineInputBorder(),
                  ),
                )
              else if (survey.projectDrawings.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No drawing uploaded yet. Upload one to continue with pin-based location.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => _uploadDrawingsForLocationFlow(
                            survey: survey,
                            controller: controller,
                          ),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Upload Drawing'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: isFireStopping
                              ? (fireStoppingPinCandidates.any(
                                      (e) => e.pin.id == _fireStoppingPinId)
                                  ? _fireStoppingPinId
                                  : null)
                              : (doorPlanPinCandidates
                                      .any((e) => e.pin.id == _doorPinId)
                                  ? _doorPinId
                                  : null),
                          decoration: const InputDecoration(
                            labelText: 'Select Pin',
                            border: OutlineInputBorder(),
                          ),
                          items: (isFireStopping
                                  ? fireStoppingPinCandidates
                                  : doorPlanPinCandidates)
                              .map(
                                (entry) => DropdownMenuItem<String>(
                                  value: entry.pin.id,
                                  child: Text(
                                      '${entry.pin.label.isNotEmpty ? entry.pin.label : entry.pin.doorNumber} (${entry.drawing.name})'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            if (isFireStopping) {
                              final selected = fireStoppingPinCandidates
                                  .firstWhere((e) => e.pin.id == value);
                              _assignFireStoppingPin(
                                  drawing: selected.drawing, pin: selected.pin);
                            } else {
                              final selected = doorPlanPinCandidates
                                  .firstWhere((e) => e.pin.id == value);
                              _assignDoorPlanPin(
                                  drawing: selected.drawing, pin: selected.pin);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => isFireStopping
                                  ? _openFireStoppingPinSelector(survey: survey)
                                  : _openDoorPlanPinSelector(survey: survey),
                              icon: const Icon(Icons.location_on_outlined),
                              label: Text((isFireStopping
                                          ? selectedFireStoppingPin
                                          : selectedDoorPlanPin) ==
                                      null
                                  ? 'Select Pin'
                                  : 'Add Pin'),
                            ),
                            OutlinedButton.icon(
                              onPressed: (isFireStopping
                                          ? selectedFireStoppingPin
                                          : selectedDoorPlanPin) ==
                                      null
                                  ? null
                                  : () {
                                      final selected = isFireStopping
                                          ? selectedFireStoppingPin!
                                          : selectedDoorPlanPin!;
                                      ProjectDrawingAccess.showDrawingViewer(
                                        context: context,
                                        surveyId: widget.surveyId,
                                        drawingId: selected.drawing.id,
                                        fallbackTitle:
                                            selected.drawing.fileName,
                                        drawingOverride: selected.drawing,
                                        workspaceOverride: survey.workspace,
                                        selectionConfig:
                                            DrawingViewerSelectionConfig(
                                          highlightedPinId: selected.pin.id,
                                          hideOtherPins: true,
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.open_in_full),
                              label: const Text('Open Drawing'),
                            ),
                          ],
                        ),
                        if ((isFireStopping
                                ? selectedFireStoppingPin
                                : selectedDoorPlanPin) !=
                            null) ...[
                          const SizedBox(height: 10),
                          FutureBuilder<Uint8List?>(
                            future: isFireStopping
                                ? _buildFireStoppingPinPreview(
                                    drawing: selectedFireStoppingPin!.drawing,
                                    pin: selectedFireStoppingPin.pin,
                                  )
                                : _buildPinPreview(
                                    drawing: selectedDoorPlanPin!.drawing,
                                    pin: selectedDoorPlanPin.pin,
                                  ),
                            builder: (context, snapshot) {
                              final bytes = snapshot.data;
                              if (bytes == null || bytes.isEmpty) {
                                return Container(
                                  height: 170,
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F5F5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('Preview unavailable'),
                                );
                              }
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  bytes,
                                  height: 170,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (!isFireStopping) ...[
                const SizedBox(height: 8),
                compactGrid([
                  compactSelectRow(
                    label: 'Floor / Level',
                    value: _floorLevel,
                    onTap: () async {
                      final picked = await _pickFloorLevel(context,
                          currentValue: _floorLevel);
                      if (picked == null) return;
                      setState(() => _floorLevel = picked);
                    },
                  ),
                  compactSelectRow(
                    label: 'Location',
                    value: _doorLocation,
                    onTap: () async {
                      final picked = await _pickDoorLocation(context,
                          currentValue: _doorLocation);
                      if (picked == null) return;
                      setState(() => _doorLocation = picked);
                    },
                  ),
                ]),
              ],
            ],
          ),
          if (isFireStopping) ...[
            const SizedBox(height: 12),
            detailsSection(
              title: 'Location',
              icon: Icons.place_outlined,
              children: [
                TextFormField(
                  initialValue: _floorLevel,
                  decoration: const InputDecoration(
                    labelText: 'Room / Area',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _floorLevel = v,
                ),
              ],
            ),
          ],
          if (isFireStopping) ...[
            const SizedBox(height: 12),
            detailsSection(
              title: 'Fire Stopping Item',
              icon: Icons.inventory_2_outlined,
              children: [
                TextField(
                  controller: _reportPreparedByCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Prepared by',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            detailsSection(
              title: 'Defects',
              icon: Icons.report_problem_outlined,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _fireStoppingDefects
                            .add(_createBlankFireStoppingDefect());
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Defect'),
                  ),
                ),
                const SizedBox(height: 10),
                if (_fireStoppingDefects.isEmpty)
                  const Text(
                      'No defects added yet. Add a defect for the selected pin to continue the inspection record.'),
                for (int idx = 0; idx < _fireStoppingDefects.length; idx++) ...[
                  Builder(builder: (context) {
                    final defect = _fireStoppingDefects[idx];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Defect ${idx + 1}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                const Spacer(),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _fireStoppingDefects.removeAt(idx);
                                      _syncFireStoppingDoorPhotosFromDefects();
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Remove defect',
                                ),
                              ],
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _fireStoppingDefectTemplates
                                      .contains(defect.template)
                                  ? defect.template
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Defect Template',
                                border: OutlineInputBorder(),
                              ),
                              items: _fireStoppingDefectTemplates
                                  .map((e) => DropdownMenuItem<String>(
                                      value: e, child: Text(e)))
                                  .toList(),
                              onChanged: (v) async {
                                var value = (v ?? '').trim();
                                if (value == 'Other (custom)') {
                                  final custom = await _askCustomValue(
                                    context,
                                    title: 'Custom Defect Template',
                                    label: 'Defect Template',
                                    initialValue: defect.template,
                                  );
                                  if (!mounted || custom == null) return;
                                  value = custom;
                                }
                                setState(() {
                                  _fireStoppingDefects[idx] = defect.copyWith(
                                    template: value,
                                    description: value.isEmpty
                                        ? defect.description
                                        : value,
                                    recommendedAction:
                                        _defaultFireStoppingActionForTemplate(
                                                    value)
                                                .isEmpty
                                            ? defect.recommendedAction
                                            : _defaultFireStoppingActionForTemplate(
                                                value),
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _fireStoppingRatings
                                      .contains(defect.fireRating)
                                  ? defect.fireRating
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Fire Rating',
                                border: OutlineInputBorder(),
                              ),
                              items: _fireStoppingRatings
                                  .map((e) => DropdownMenuItem<String>(
                                      value: e, child: Text(e)))
                                  .toList(),
                              onChanged: (v) async {
                                final picked = (v ?? '').trim();
                                if (picked == 'Other (custom)') {
                                  final custom = await _askCustomValue(
                                    context,
                                    title: 'Custom Fire Rating',
                                    label: 'Fire Rating',
                                    initialValue: defect.fireRating,
                                  );
                                  if (!mounted || custom == null) return;
                                  setState(() {
                                    _fireStoppingDefects[idx] =
                                        defect.copyWith(fireRating: custom);
                                  });
                                  return;
                                }
                                setState(() {
                                  _fireStoppingDefects[idx] =
                                      defect.copyWith(fireRating: picked);
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: defect.lengthMm,
                                    decoration: const InputDecoration(
                                      labelText: 'Length (mm)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) {
                                      final current = _fireStoppingDefects[idx];
                                      _fireStoppingDefects[idx] =
                                          current.copyWith(lengthMm: v);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: defect.widthMm,
                                    decoration: const InputDecoration(
                                      labelText: 'Width (mm)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) {
                                      final current = _fireStoppingDefects[idx];
                                      _fireStoppingDefects[idx] =
                                          current.copyWith(widthMm: v);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: defect.description,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Description',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                final current = _fireStoppingDefects[idx];
                                _fireStoppingDefects[idx] =
                                    current.copyWith(description: v);
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  _fireStoppingRecommendedActionOptions
                                          .contains(defect.recommendedAction)
                                      ? defect.recommendedAction
                                      : null,
                              decoration: const InputDecoration(
                                labelText: 'Recommended Action Template',
                                border: OutlineInputBorder(),
                              ),
                              items: _fireStoppingRecommendedActionOptions
                                  .map((e) => DropdownMenuItem<String>(
                                      value: e, child: Text(e)))
                                  .toList(),
                              onChanged: (v) async {
                                var value = (v ?? '').trim();
                                if (value == 'Other (custom)') {
                                  final custom = await _askCustomValue(
                                    context,
                                    title: 'Custom Recommended Action',
                                    label: 'Recommended Action',
                                    initialValue: defect.recommendedAction,
                                  );
                                  if (!mounted || custom == null) return;
                                  value = custom;
                                }
                                setState(() {
                                  _fireStoppingDefects[idx] =
                                      defect.copyWith(recommendedAction: value);
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: defect.recommendedAction,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Recommended Action',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                final current = _fireStoppingDefects[idx];
                                _fireStoppingDefects[idx] =
                                    current.copyWith(recommendedAction: v);
                              },
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final p in defect.photos)
                                  InputChip(
                                    avatar: const Icon(Icons.photo_outlined,
                                        size: 16),
                                    label: Text(p.fileName.trim().isEmpty
                                        ? 'photo'
                                        : p.fileName.trim()),
                                    onDeleted: () {
                                      final nextPhotos = [...defect.photos]
                                        ..removeWhere((e) => e.id == p.id);
                                      setState(() {
                                        _fireStoppingDefects[idx] =
                                            defect.copyWith(photos: nextPhotos);
                                        _syncFireStoppingDoorPhotosFromDefects();
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final shot = await _takePhoto();
                                      if (shot == null) return;
                                      setState(() {
                                        _fireStoppingDefects[idx] = defect
                                            .copyWith(photos: [
                                          ...defect.photos,
                                          shot
                                        ]);
                                        _syncFireStoppingDoorPhotosFromDefects();
                                      });
                                    },
                                    icon:
                                        const Icon(Icons.photo_camera_outlined),
                                    label: const Text('Take Photo'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await _pickPhotos();
                                      if (picked.isEmpty) return;
                                      setState(() {
                                        _fireStoppingDefects[idx] = defect
                                            .copyWith(photos: [
                                          ...defect.photos,
                                          ...picked
                                        ]);
                                        _syncFireStoppingDoorPhotosFromDefects();
                                      });
                                    },
                                    icon:
                                        const Icon(Icons.upload_file_outlined),
                                    label: const Text('Upload Photo'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            detailsSection(
              title: 'Door Profile',
              icon: Icons.tune_outlined,
              children: [
                compactGrid([
                  compactSelectRow(
                    label: 'Door configuration',
                    value: _configurationLabel(_configuration),
                    onTap: () async {
                      final picked = await _pickConfiguration(context,
                          currentValue: _configuration);
                      if (picked == null) return;
                      applyDoorConfiguration(picked);
                    },
                  ),
                  compactSelectRow(
                    label: 'Door material',
                    value: _material == DoorMaterial.otherCustom &&
                            _customMaterial.trim().isNotEmpty
                        ? _customMaterial.trim()
                        : _materialLabel(_material),
                    onTap: () async {
                      final picked =
                          await _pickMaterial(context, currentValue: _material);
                      if (picked == null) return;
                      setState(() {
                        _material = picked;
                        if (_material != DoorMaterial.otherCustom) {
                          _customMaterial = '';
                          _customMaterialCtrl.clear();
                        }
                      });
                    },
                  ),
                  compactSelectRow(
                    label: 'Frame material',
                    value: _frameMaterial,
                    onTap: () async {
                      final picked = await _pickFrameMaterial(context,
                          currentValue: _frameMaterial);
                      if (picked == null) return;
                      setState(() => _frameMaterial = picked);
                    },
                  ),
                  compactSelectRow(
                    label: 'Fire rating',
                    value: _fireRatingLabel(_fireRating),
                    onTap: () async {
                      final picked = await _pickFireRating(context,
                          currentValue: _fireRating);
                      if (picked == null) return;
                      setState(() => _fireRating = picked);
                    },
                  ),
                ]),
                if (_smokeSealsRequired(_fireRating)) ...[
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    color: const Color(0xFFFFF7E6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.orange),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Smoke control (S) rating selected: smoke seals are required.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
                if (_material == DoorMaterial.otherCustom) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _customMaterialCtrl,
                    onChanged: (v) => _customMaterial = v,
                    decoration: const InputDecoration(
                      labelText: 'Custom material',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            detailsSection(
              title: 'Evidence & Certification',
              icon: Icons.verified_user_outlined,
              children: [
                compactSelectRow(
                  label: 'Evidence available',
                  value: _gradingLabel(_gradingLevel),
                  warning: _gradingLevel == GradingLevel.level4,
                  onTap: () async {
                    final picked = await _pickGrading(context,
                        currentValue: _gradingLevel);
                    if (picked == null) return;
                    setState(() => _gradingLevel = picked);
                  },
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD7DEE7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _gradingLevelExplanation(_gradingLevel),
                        style: const TextStyle(
                          color: Color(0xFF263238),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Where the doorset specification can be seen not to match the test evidence, or if the specification is clearly inappropriate for the declared fire resistance period, a label cannot be applied.',
                        style: TextStyle(
                          color: Color(0xFF5F6B76),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                compactSelectRow(
                  label: 'Certification status',
                  value: _classificationLabel(_classification),
                  warning:
                      _classification == DoorClassification.unknownNotVerified,
                  onTap: () async {
                    final picked = await _pickClassification(context,
                        currentValue: _classification);
                    if (picked == null) return;
                    setState(() {
                      _classification = picked;
                      if (_classification !=
                          DoorClassification.thirdPartyCertified) {
                        _certificationBodyName = '';
                      }
                    });
                  },
                ),
                if (_classification ==
                    DoorClassification.thirdPartyCertified) ...[
                  const SizedBox(height: 8),
                  compactSelectRow(
                    label: 'Certification scheme',
                    value: _certificationBodyName.trim().isEmpty
                        ? 'Not specified'
                        : _certificationBodyName.trim(),
                    onTap: () async {
                      final picked = await _pickCertificationBody(context,
                          currentValue: _certificationBodyName);
                      if (picked == null) return;
                      setState(() => _certificationBodyName = picked);
                    },
                  ),
                ],
                const SizedBox(height: 8),
                compactSelectRow(
                  label: 'Fire door designation source',
                  value: _fireDoorDesignationSource,
                  warning: _fireDoorDesignationSource == 'Unknown',
                  onTap: () async {
                    final picked = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (ctx) => _SimplePickerSheet(
                        title: 'Fire door designation source',
                        options: _designationSourceOptions,
                        initialValue: _fireDoorDesignationSource,
                        allowCustom: true,
                        confirmLabel: 'Select',
                      ),
                    );
                    if (picked == null) return;
                    if (picked == 'Other (custom)') {
                      if (!context.mounted) return;
                      final custom = await _askCustomValue(
                        context,
                        title: 'Custom designation source',
                        label: 'Designation source',
                        initialValue: _fireDoorDesignationSource,
                      );
                      if (!context.mounted) return;
                      if (custom == null) return;
                      setState(() => _fireDoorDesignationSource = custom);
                      return;
                    }
                    setState(() => _fireDoorDesignationSource = picked);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _designationSourceHelperText(_fireDoorDesignationSource),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade700, height: 1.3),
                ),
                if (_gradingLevel == GradingLevel.level4 &&
                    _classification ==
                        DoorClassification.unknownNotVerified) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE57373)),
                    ),
                    child: const Text(
                      'Evidence is incomplete. This should normally be treated as FAIL unless further evidence is provided.',
                      style: TextStyle(
                          color: Color(0xFFB71C1C),
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ] else if (_classification ==
                        DoorClassification.unknownNotVerified ||
                    _gradingLevel == GradingLevel.level4 ||
                    _fireDoorDesignationSource == 'Unknown') ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFCC80)),
                    ),
                    child: const Text(
                      'Evidence is incomplete. Confirm certification basis and traceability where possible.',
                      style: TextStyle(
                          color: Color(0xFF8D6E00),
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFDDE4ED)),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Traceability (optional)',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey.shade800),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() => _traceabilityExpanded =
                                    !_traceabilityExpanded);
                              },
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                minimumSize: const Size(0, 0),
                              ),
                              child: Text(_traceabilityExpanded
                                  ? 'Hide details'
                                  : 'Show details'),
                            ),
                          ],
                        ),
                        if (_traceabilityExpanded) ...[
                          const SizedBox(height: 6),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment<bool>(
                                  value: true,
                                  label: Text('Plug present: Yes')),
                              ButtonSegment<bool>(
                                  value: false,
                                  label: Text('Plug present: No')),
                            ],
                            selected: {_plugPresent},
                            onSelectionChanged: (value) {
                              if (value.isEmpty) return;
                              setState(() => _plugPresent = value.first);
                            },
                          ),
                          if (_plugPresent) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _plugOuterColourCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Plug outer colour',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _plugInnerCoreColourCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Plug inner tree colour',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          TextField(
                            controller: _traceabilityNumberCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Company / certificate number',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment<bool>(
                                  value: true,
                                  label: Text('Installer label: Yes')),
                              ButtonSegment<bool>(
                                  value: false,
                                  label: Text('Installer label: No')),
                            ],
                            selected: {_installerLabelPresent},
                            onSelectionChanged: (value) {
                              if (value.isEmpty) return;
                              setState(
                                  () => _installerLabelPresent = value.first);
                            },
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () =>
                                    addCategorizedPhotos(_plugPhotoIds),
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: Text(
                                    'Add plug photo (${_plugPhotoIds.where((id) => _doorPhotos.any((p) => p.id == id)).length})'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    addCategorizedPhotos(_labelPhotoIds),
                                icon: const Icon(Icons.badge_outlined),
                                label: Text(
                                    'Add label photo (${_labelPhotoIds.where((id) => _doorPhotos.any((p) => p.id == id)).length})'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    addCategorizedPhotos(_certPhotoIds),
                                icon: const Icon(Icons.verified_outlined),
                                label: Text(
                                    'Add certification photo (${_certPhotoIds.where((id) => _doorPhotos.any((p) => p.id == id)).length})'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _suggestedCertificationResultColor(_gradingLevel)
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _suggestedCertificationResultColor(_gradingLevel)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _suggestedCertificationResultIcon(_gradingLevel),
                            color: _suggestedCertificationResultColor(
                                _gradingLevel),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Suggested result: ${_suggestedCertificationResultLabel(_gradingLevel)}',
                              style: TextStyle(
                                color: _suggestedCertificationResultColor(
                                    _gradingLevel),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _suggestedCertificationResultHelp(_gradingLevel),
                        style: const TextStyle(
                          color: Color(0xFF455A64),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            detailsSection(
              title: 'Inspection & Maintenance',
              icon: Icons.fact_check_outlined,
              children: [
                const Text(
                  'Maintenance interval',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<_MaintenancePreset>(
                  initialValue: _presetFromMonths(
                    _maintenanceIntervalMonths,
                    custom: _useCustomMaintenanceInterval,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Inspection cycle',
                    border: OutlineInputBorder(),
                  ),
                  items: _MaintenancePreset.values
                      .map(
                        (preset) => DropdownMenuItem<_MaintenancePreset>(
                          value: preset,
                          child: Text(_maintenancePresetLabels[preset]!),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      if (value == _MaintenancePreset.custom) {
                        _useCustomMaintenanceInterval = true;
                        final parsed = int.tryParse(
                            _customMaintenanceInterval.text.trim());
                        if (parsed != null && parsed > 0) {
                          _maintenanceIntervalMonths = parsed;
                        }
                      } else {
                        _useCustomMaintenanceInterval = false;
                        _maintenanceIntervalMonths = _monthsForPreset(value);
                        _customMaintenanceInterval.text =
                            _maintenanceIntervalMonths.toString();
                      }
                    });
                  },
                ),
                if (_useCustomMaintenanceInterval) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _customMaintenanceInterval,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Custom interval (months)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      final parsed = int.tryParse(value.trim());
                      if (parsed == null || parsed <= 0) return;
                      setState(() => _maintenanceIntervalMonths = parsed);
                    },
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricChip(
                      label: 'Status',
                      value: doorResultLabel,
                      color: doorResultLabel == 'PASS'
                          ? Colors.green
                          : (doorResultLabel == 'FAIL'
                              ? Colors.red
                              : (doorResultLabel == 'N/A'
                                  ? Colors.grey
                                  : Colors.blueGrey)),
                    ),
                    _MetricChip(
                        label: 'Answered',
                        value: '$answered/$total',
                        color: Colors.blueGrey),
                    _MetricChip(
                      label: 'Issues found',
                      value: defects.toString(),
                      color: answered == 0
                          ? Colors.blueGrey
                          : (defects > 0 ? Colors.red : Colors.green),
                    ),
                    _MetricChip(
                      label: 'Missing fail photos',
                      value: missingFailPhotos.toString(),
                      color: answered == 0
                          ? Colors.blueGrey
                          : (missingFailPhotos == 0
                              ? Colors.green
                              : const Color(0xFFC62828)),
                    ),
                    _MetricChip(
                      label: 'Completion',
                      value: total == 0
                          ? '0%'
                          : '${((answered / total) * 100).round()}%',
                      color: total == 0
                          ? Colors.blueGrey
                          : (((answered / total) * 100).round() >= 80
                              ? Colors.green
                              : Colors.orange),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
            const SizedBox(height: 12),
            detailsSection(
              title: 'Major Issue',
              icon: Icons.warning_amber_outlined,
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Full door set replacement required',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                      'Selecting this marks the door as overall FAIL and flags urgent replacement.'),
                  value: _replacementRequired,
                  onChanged: (value) {
                    setState(() => _replacementRequired = value);
                  },
                ),
                if (_replacementRequired) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEF9A9A)),
                    ),
                    child: const Text(
                      'Overall result is FAIL. Record replacement doorset/opening dimensions and add evidence photos.',
                      style: TextStyle(
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _configuration == DoorConfiguration.singleLeaf
                        ? 'Replacement doorset / opening dimensions (single leaf)'
                        : 'Replacement doorset / opening dimensions (double / leaf-and-a-half)',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 8),
                  compactGrid([
                    TextField(
                      controller: _replacementDoor1WidthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            _configuration == DoorConfiguration.singleLeaf
                                ? 'Opening width (mm)'
                                : 'Overall opening width (mm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: _replacementDoor1HeightCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Opening height (mm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_configuration != DoorConfiguration.singleLeaf)
                      TextField(
                        controller: _replacementDoor2WidthCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Leaf 1 approximate width (mm)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    if (_configuration != DoorConfiguration.singleLeaf)
                      TextField(
                        controller: _replacementDoor2HeightCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Leaf 2 approximate width (mm)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFD54F)),
                    ),
                    child: const Text(
                      'These dimensions are recorded for pricing and survey reference only. Final manufacturing/order dimensions must be verified on site by the installer/supplier before any replacement doorset is ordered or manufactured.',
                      style: TextStyle(
                          color: Color(0xFF7A5A00),
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => addCategorizedPhotos(_certPhotoIds),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Add replacement evidence'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (_isNotAFireDoor(_fireRating)) ...[
              const Text(
                'Inspection hidden (Not a fire door selected).',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: Colors.black54),
              ),
              const SizedBox(height: 12),
            ] else ...[
              const SizedBox(height: 8),
              ...() {
                final entries = bySection.entries.toList();
                return [
                  for (int i = 0; i < entries.length; i++) ...[
                    sectionCard(entries[i].key, entries[i].value),
                    const SizedBox(height: 12),
                  ],
                ];
              }(),
            ],
          ],
          if (!isFireStopping) ...[
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.photo_library_outlined, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Photos',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF5FB),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFCCDBEE)),
                  ),
                  child: Text(
                    '${_doorPhotos.length} uploaded',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
                if (needsPhotoEvidence()) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F0FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Defect evidence attached per item',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1565C0)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (!isFireStopping && !needsPhotoEvidence() && _doorPhotos.isEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCFE0FB)),
                ),
                child: const Text(
                  'Capture an overview photo, then add evidence and defect photos as needed.',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => addCategorizedPhotos(<String>{}),
                  icon: const Icon(Icons.house_outlined),
                  label: const Text('Add overview photo'),
                ),
                OutlinedButton.icon(
                  onPressed: () => addCategorizedPhotos(_labelPhotoIds),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Add evidence photo'),
                ),
                OutlinedButton.icon(
                  onPressed: () => addCategorizedPhotos(_plugPhotoIds),
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text('Add defect photo'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (imageAttachments.isNotEmpty) ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: imageAttachments.length,
                itemBuilder: (context, idx) {
                  final photo = imageAttachments[idx];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          showPhotoViewer(
                            context: context,
                            photos:
                                imageAttachments.map((p) => p.bytes).toList(),
                            initialIndex: idx,
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            Uint8List.fromList(photo.bytes),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setState(() {
                            final updated = [..._doorPhotos];
                            updated.removeWhere((m) => m.id == photo.id);
                            _doorPhotos = updated;
                            _plugPhotoIds.remove(photo.id);
                            _labelPhotoIds.remove(photo.id);
                            _certPhotoIds.remove(photo.id);
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 12),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
            if (videoAttachments.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final video in videoAttachments)
                    InputChip(
                      avatar: const Icon(Icons.videocam_outlined, size: 16),
                      label: Text(_videoLabelFromPath(video.fileName)),
                      onDeleted: () {
                        setState(() {
                          final updated = [..._doorPhotos];
                          updated.removeWhere((m) => m.id == video.id);
                          _doorPhotos = updated;
                          _plugPhotoIds.remove(video.id);
                          _labelPhotoIds.remove(video.id);
                          _certPhotoIds.remove(video.id);
                        });
                      },
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 20),
          if (showInspectorSignatureSection && !isFireStopping) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_user_outlined),
                        const SizedBox(width: 8),
                        const Text('Inspector acknowledgement',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      !hasCurrentDisclaimer
                          ? 'Complete the saved disclaimer form for this report before saving this door.'
                          : 'Inspector name and signature are already captured in the disclaimer acceptance record for this report.',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (isFireStopping) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () async {
                  final ok = await saveDoor(popAfterSave: false);
                  if (!ok || !context.mounted) return;
                  final choice = await askAfterSaveChoice();
                  if (!context.mounted || choice == null) return;
                  if (choice == 'back') {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      context
                          .go('${widget.routePrefix}/${widget.surveyId}/doors');
                    }
                    return;
                  }

                  controller.addDoor(widget.surveyId);
                  final updatedSurvey = controller.getById(widget.surveyId);
                  if (updatedSurvey == null || updatedSurvey.doors.isEmpty) {
                    return;
                  }
                  final newDoorId = updatedSurvey.doors.last.id;

                  if (choice == 'next' && selectedFireStoppingPin != null) {
                    controller.updateDoor(
                      surveyId: widget.surveyId,
                      doorId: newDoorId,
                      update: (d) => d.copyWith(
                        doorIdTag: _doorIdTag.text.trim(),
                        floor: _floorLevel.trim(),
                        area: _doorLocation.trim(),
                        doorDrawingId: selectedFireStoppingPin.drawing.id,
                        doorPinId: selectedFireStoppingPin.pin.id,
                        fireStoppingItemType:
                            'drawing=${selectedFireStoppingPin.drawing.id};pin=${selectedFireStoppingPin.pin.id}',
                        fireStoppingDefects: const [],
                      ),
                    );
                  }

                  if (choice == 'new_pin') {
                    final result = await ProjectDrawingAccess.showDrawingPicker(
                      context: context,
                      survey: survey,
                      preferredLevel: _floorLevel,
                      selectionConfig: const DrawingViewerSelectionConfig(
                        enablePinPlacement: true,
                        allowExistingPinSelection: true,
                        autoAssignPinNumbers: false,
                      ),
                    );
                    if (!context.mounted || result == null) return;
                    controller.updateDoor(
                      surveyId: widget.surveyId,
                      doorId: newDoorId,
                      update: (d) => d.copyWith(
                        doorIdTag: result.pin.label.trim().isNotEmpty
                            ? result.pin.label.trim()
                            : result.pin.doorNumber.trim(),
                        floor: _floorLevel.trim(),
                        area: _doorLocation.trim(),
                        doorDrawingId: result.drawing.id,
                        doorPinId: result.pin.id,
                        fireStoppingItemType:
                            'drawing=${result.drawing.id};pin=${result.pin.id}',
                        fireStoppingDefects: result.addDefect
                            ? [
                                FireStoppingDefect(
                                    id: 'defect_${DateTime.now().millisecondsSinceEpoch}',
                                    drawingId: result.drawing.id,
                                    pinId: result.pin.id)
                              ]
                            : const [],
                      ),
                    );
                  }

                  if (!context.mounted) return;
                  await Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => DoorDetailScreen(
                        surveyId: widget.surveyId,
                        mode: DoorDetailMode.edit,
                        existingDoorId: newDoorId,
                        isTempDraft: true,
                        moduleKey: widget.moduleKey,
                        routePrefix: widget.routePrefix,
                        workspaceKey: widget.workspaceKey,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text(
                  'Save Item',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ] else ...[
            if (saveRequirements.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Complete required fields before saving: ${saveRequirements.join(', ')}.',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: !canSavePrimary
                    ? null
                    : () async {
                        final ok = await saveDoor(popAfterSave: false);
                        if (!ok || !context.mounted) return;

                        final choice = await askAfterSaveChoice();
                        if (!context.mounted) return;

                        if (choice == 'next') {
                          controller.addDoor(widget.surveyId);
                          final updatedSurvey =
                              controller.getById(widget.surveyId);
                          if (updatedSurvey == null ||
                              updatedSurvey.doors.isEmpty) {
                            return;
                          }
                          final newDoorId = updatedSurvey.doors.last.id;

                          await Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => DoorDetailScreen(
                                surveyId: widget.surveyId,
                                mode: DoorDetailMode.edit,
                                existingDoorId: newDoorId,
                                isTempDraft: true,
                              ),
                            ),
                          );
                          return;
                        }

                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          context.go(
                              '${widget.routePrefix}/${widget.surveyId}/doors');
                        }
                      },
                icon: const Icon(Icons.save),
                label: const Text(
                  'Save Door',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          const SizedBox(height: 20),
          // ── Approval status (read-only) ───────────────────────────────────────
          if (door.approvedAt != null) ...[
            const Divider(),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF66BB6A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_outlined, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Approved — ${door.approvedMaintainerName} (${door.approvedMaintainerNumber})\n'
                      'Date: ${door.approvedAt!.day.toString().padLeft(2, "0")}/${door.approvedAt!.month.toString().padLeft(2, "0")}/${door.approvedAt!.year}',
                      style: const TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && widget.isTempDraft && !_savedOnce) {
          controller.deleteDoor(
              surveyId: widget.surveyId, doorId: widget.existingDoorId);
        }
      },
      child: useFireDoorWebShell
          ? FireDoorWebShellScaffold(
              currentRoute:
                  '/workspace/fire-door/inspection/projects/${widget.surveyId}/doors/${widget.existingDoorId}',
              title: isFireStopping
                  ? _titleForDoor(door).replaceAll('Door', 'Item')
                  : _titleForDoor(door),
              workflowLabel: 'Inspection Projects',
              drawerRoute: '/workspace/fire-door/inspection/projects',
              surveyId: widget.surveyId,
              backgroundColor: const Color(0xFFF6F7F9),
              body: pageScaffold,
            )
          : pageScaffold,
    );
  }

  String _configurationLabel(DoorConfiguration c) {
    switch (c) {
      case DoorConfiguration.singleLeaf:
        return 'Single leaf';
      case DoorConfiguration.doubleLeaf:
        return 'Double leaf';
      case DoorConfiguration.leafAndAHalf:
        return 'Leaf and a half';
    }
  }

  String _materialLabel(DoorMaterial m) {
    switch (m) {
      case DoorMaterial.timber:
        return 'Timber';
      case DoorMaterial.metalDoor:
        return 'Metal door';
      case DoorMaterial.composite:
        return 'Composite';
      case DoorMaterial.aluminium:
        return 'Aluminium';
      case DoorMaterial.upvc:
        return 'uPVC';
      case DoorMaterial.otherCustom:
        return 'Other (custom)';
      case DoorMaterial.unknown:
        return 'Unknown';
    }
  }

  String _classificationLabel(DoorClassification c) {
    switch (c) {
      case DoorClassification.thirdPartyCertified:
        return 'Third-party certified';
      case DoorClassification.manufacturerEvidenceAvailable:
        return 'Manufacturer evidence available';
      case DoorClassification.noEvidenceClientStatedFireRated:
        return 'No evidence (client states door is fire-rated)';
      case DoorClassification.unknownNotVerified:
        return 'Unknown / not verified';
    }
  }

  String _fireRatingLabel(FireRating r) {
    switch (r) {
      case FireRating.notAFireDoor:
        return 'Not a fire door';
      case FireRating.fd30:
        return 'FD30';
      case FireRating.fd30s:
        return 'FD30S';
      case FireRating.fd60:
        return 'FD60';
      case FireRating.fd60s:
        return 'FD60S';
      case FireRating.fd90:
        return 'FD90';
      case FireRating.fd90s:
        return 'FD90S';
      case FireRating.fd120:
        return 'FD120';
      case FireRating.fd120s:
        return 'FD120S';
      case FireRating.unknown:
        return 'Unknown';
    }
  }

  String _gradingLabel(GradingLevel g) {
    switch (g) {
      case GradingLevel.level1:
        return 'Level 1 – Full certification & installation records';
      case GradingLevel.level2:
        return 'Level 2 – Certification present, no install records';
      case GradingLevel.level3:
        return 'Level 3 – Label/marking only';
      case GradingLevel.level4:
        return 'Level 4 – No evidence available';
    }
  }

  String _gradingLevelExplanation(GradingLevel g) {
    switch (g) {
      case GradingLevel.level1:
        return 'Doorset with test report, FoA (or historical assessment), project specific assessment or third-party certification evidence, and complete records confirming installation by a third-party certified installation company.';
      case GradingLevel.level2:
        return 'Doorset with test report, FoA (or historical assessment), project specific assessment or third-party certification evidence, but with no records confirming installation by a third-party certified installation company.';
      case GradingLevel.level3:
        return 'Doorset identified only by fire door manufacturer marking or labelling.';
      case GradingLevel.level4:
        return 'Doorset with no supporting records, but declared by the client as a fire-resisting doorset.';
    }
  }

  String _designationSourceHelperText(String source) {
    switch (source) {
      case 'Fire risk assessment':
        return 'Source based on fire risk assessment documentation provided.';
      case 'Label / plug':
        return 'Source based on physical identification label or plug on the doorset.';
      case 'Unknown':
        return 'No reliable source available for fire door designation.';
      case 'Floor plan':
        return 'Source based on project floor plan information.';
      case 'Client / Responsible Person':
        return 'Source based on declaration from the client or Responsible Person.';
      case 'Test / certification document':
        return 'Source based on test or certification documentation provided.';
      case 'Previous survey':
        return 'Source based on records from a previous survey.';
      default:
        return 'Source recorded from project-provided designation information.';
    }
  }

  String _suggestedCertificationResultLabel(GradingLevel g) {
    switch (g) {
      case GradingLevel.level1:
      case GradingLevel.level2:
        return 'PASS';
      case GradingLevel.level3:
        return 'REVIEW / CAUTION';
      case GradingLevel.level4:
        return 'FAIL';
    }
  }

  String _suggestedCertificationResultHelp(GradingLevel g) {
    switch (g) {
      case GradingLevel.level1:
        return 'Evidence supports a pass result subject to the selected certification basis and traceability details.';
      case GradingLevel.level2:
        return 'Evidence generally supports a pass result, but the missing installation record should be noted.';
      case GradingLevel.level3:
        return 'Marking or labelling alone should be treated with caution. Inspect visible specification and traceability before setting the final result.';
      case GradingLevel.level4:
        return 'No supporting evidence is available. Fail should remain the default unless additional evidence is provided.';
    }
  }

  Color _suggestedCertificationResultColor(GradingLevel g) {
    switch (g) {
      case GradingLevel.level1:
      case GradingLevel.level2:
        return const Color(0xFF2E7D32);
      case GradingLevel.level3:
        return const Color(0xFFF9A825);
      case GradingLevel.level4:
        return const Color(0xFFC62828);
    }
  }

  IconData _suggestedCertificationResultIcon(GradingLevel g) {
    switch (g) {
      case GradingLevel.level1:
      case GradingLevel.level2:
        return Icons.check_circle_outline;
      case GradingLevel.level3:
        return Icons.rule_folder_outlined;
      case GradingLevel.level4:
        return Icons.warning_amber_rounded;
    }
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontWeight: FontWeight.w900, color: color),
      ),
    );
  }
}

class _GapGrid extends StatelessWidget {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double? meeting;
  final bool showMeeting;

  final void Function(double? top, double? bottom, double? left, double? right,
      double? meeting) onChanged;

  const _GapGrid({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
    required this.meeting,
    required this.showMeeting,
    required this.onChanged,
  });

  double? _parse(String v) {
    final t = v.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        );

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: top?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: dec('Top (mm)'),
                onChanged: (v) =>
                    onChanged(_parse(v), bottom, left, right, meeting),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: bottom?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: dec('Bottom (mm)'),
                onChanged: (v) =>
                    onChanged(top, _parse(v), left, right, meeting),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: left?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: dec('Left (mm)'),
                onChanged: (v) =>
                    onChanged(top, bottom, _parse(v), right, meeting),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: right?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: dec('Right (mm)'),
                onChanged: (v) =>
                    onChanged(top, bottom, left, _parse(v), meeting),
              ),
            ),
          ],
        ),
        if (showMeeting) ...[
          const SizedBox(height: 10),
          TextFormField(
            initialValue: meeting?.toString() ?? '',
            keyboardType: TextInputType.number,
            decoration: dec('Meeting (mm)'),
            onChanged: (v) => onChanged(top, bottom, left, right, _parse(v)),
          ),
        ],
      ],
    );
  }
}

class _DoorLocationPickerSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final Map<String, List<String>> groupedOptions;
  final String initialValue;

  const _DoorLocationPickerSheet({
    required this.title,
    required this.options,
    required this.groupedOptions,
    required this.initialValue,
  });

  @override
  State<_DoorLocationPickerSheet> createState() =>
      _DoorLocationPickerSheetState();
}

class _DoorLocationPickerSheetState extends State<_DoorLocationPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();

    final filtered = widget.options.where((o) {
      if (q.isEmpty) return true;
      return o.toLowerCase().contains(q);
    }).toList();

    final grouped = widget.groupedOptions.entries
        .map(
          (entry) => (
            title: entry.key,
            values: entry.value
                .where((o) => q.isEmpty || o.toLowerCase().contains(q))
                .toList(),
          ),
        )
        .where((entry) => entry.values.isNotEmpty)
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search locations',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (q.isNotEmpty) ...[
                    for (final opt in filtered)
                      ListTile(
                        title: Text(opt),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, opt),
                      ),
                  ] else ...[
                    for (final section in grouped) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                        child: Text(
                          section.title,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.black54),
                        ),
                      ),
                      for (final opt in section.values)
                        ListTile(
                          dense: true,
                          title: Text(opt),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, opt),
                        ),
                    ],
                  ],
                  const Divider(),
                  ListTile(
                    title: const Text('Other (custom)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final custom = await _askCustomLocation(context);
                      if (!context.mounted) return;
                      if (custom == null) return;
                      Navigator.pop(context, custom);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askCustomLocation(BuildContext context) async {
    final c = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom door location'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: 'Door location',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = c.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Use'),
          ),
        ],
      ),
    );
    c.dispose();
    return res;
  }
}

class _FloorLevelPickerSheet extends StatefulWidget {
  final String title;
  final String initialValue;

  const _FloorLevelPickerSheet({
    required this.title,
    required this.initialValue,
  });

  @override
  State<_FloorLevelPickerSheet> createState() => _FloorLevelPickerSheetState();
}

class _FloorLevelPickerSheetState extends State<_FloorLevelPickerSheet> {
  static const _customOption = 'Other (Custom)';
  late final TextEditingController _customController;
  late bool _showCustomInput;

  @override
  void initState() {
    super.initState();
    final presetValues = <String>{
      '-3 (Basement)',
      '-2 (Basement)',
      '-1 (Basement)',
      '0 (Ground)',
      'Mezzanine',
      ...[for (var i = 1; i <= 25; i++) i.toString()],
      'Roof level',
      'Roof',
      'External',
    };
    final initialCustom = widget.initialValue.trim();
    _showCustomInput =
        initialCustom.isNotEmpty && !presetValues.contains(initialCustom);
    _customController =
        TextEditingController(text: _showCustomInput ? initialCustom : '');
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = <({String title, List<String> values})>[
      (
        title: 'Basement',
        values: const ['-3 (Basement)', '-2 (Basement)', '-1 (Basement)']
      ),
      (title: 'Ground & Mezzanine', values: const ['0 (Ground)', 'Mezzanine']),
      (
        title: 'Upper Floors',
        values: [for (var i = 1; i <= 25; i++) i.toString()]
      ),
      (
        title: 'Top / External',
        values: const ['Roof level', 'Roof', 'External']
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                      child: Text(
                        section.title,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.black54),
                      ),
                    ),
                    for (final opt in section.values)
                      ListTile(
                        dense: true,
                        title: Text(opt),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, opt),
                      ),
                  ],
                  const Divider(height: 20),
                  ListTile(
                    dense: true,
                    title: const Text(_customOption),
                    trailing: Icon(_showCustomInput
                        ? Icons.expand_less
                        : Icons.chevron_right),
                    onTap: () {
                      setState(() {
                        _showCustomInput = true;
                      });
                    },
                  ),
                  if (_showCustomInput) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _customController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Custom level name',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (value) {
                          final trimmed = value.trim();
                          if (trimmed.isEmpty) return;
                          Navigator.pop(context, trimmed);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final trimmed = _customController.text.trim();
                                if (trimmed.isEmpty) return;
                                Navigator.pop(context, trimmed);
                              },
                              child: const Text('Use Custom Level'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimplePickerSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String initialValue;
  final bool allowCustom;
  final String confirmLabel;

  const _SimplePickerSheet({
    required this.title,
    required this.options,
    required this.initialValue,
    required this.allowCustom,
    required this.confirmLabel,
  });

  @override
  State<_SimplePickerSheet> createState() => _SimplePickerSheetState();
}

class _SimplePickerSheetState extends State<_SimplePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = widget.options
        .where((o) => q.isEmpty || o.toLowerCase().contains(q))
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final opt in filtered)
                    ListTile(
                      title: Text(opt),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, opt),
                    ),
                  if (widget.allowCustom) ...[
                    const Divider(),
                    ListTile(
                      title: const Text('Other (custom)'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, 'Other (custom)'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnumPickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> options;
  final T initialValue;
  final String Function(T v) labelFor;

  const _EnumPickerSheet({
    required this.title,
    required this.options,
    required this.initialValue,
    required this.labelFor,
  });

  @override
  State<_EnumPickerSheet<T>> createState() => _EnumPickerSheetState<T>();
}

class _EnumPickerSheetState<T> extends State<_EnumPickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();

    final filtered = widget.options.where((o) {
      if (q.isEmpty) return true;
      return widget.labelFor(o).toLowerCase().contains(q);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final opt in filtered)
                    ListTile(
                      title: Text(widget.labelFor(opt)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, opt),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
