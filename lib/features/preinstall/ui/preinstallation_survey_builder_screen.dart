import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../../../app/app_drawer.dart';
import '../../../app/ui/branding_resolver.dart';
import '../../../app/ui/selection_controls.dart';
import '../../../app/ui/workspace_switch_cards_bar.dart';
import '../../../auth/auth_state.dart';
import '../../fire_door/ui/fire_door_web_shell_scaffold.dart';
import '../../installation/pdf/factory_supplier_pdf.dart';
import '../../installation/pdf/preinstall_pdf.dart';
import '../../reports/domain/report_file_naming.dart';
import '../../settings/state/settings_controller.dart';
import '../../storage/data/company_file_providers.dart';
import '../../storage/domain/company_file_record.dart';
import '../../surveys/domain/models.dart';
import '../../surveys/pdf/web_download_stub.dart'
    if (dart.library.html) '../../surveys/pdf/web_download.dart';
import '../../surveys/state/survey_controller.dart';
import '../../surveys/ui/project_drawing_viewer.dart';
import '../domain/preinstallation_survey_builder_logic.dart';
import '../domain/preinstallation_survey_builder_model.dart';

enum _ExportAction { download, email }

enum _IdentificationMode { manual, drawingPin }

class PreInstallationSurveyBuilderScreen extends ConsumerStatefulWidget {
  final String surveyId;
  final String itemId;
  final String workspaceKey;

  const PreInstallationSurveyBuilderScreen({
    super.key,
    required this.surveyId,
    required this.itemId,
    this.workspaceKey = 'fire-door',
  });

  @override
  ConsumerState<PreInstallationSurveyBuilderScreen> createState() =>
      _PreInstallationSurveyBuilderScreenState();
}

class _PreInstallationSurveyBuilderScreenState
    extends ConsumerState<PreInstallationSurveyBuilderScreen> {
  PreInstallationSurveyBuilderData? _data;
  bool _loaded = false;
  bool _cloudPhotoSynced = false;
  _IdentificationMode _identificationMode = _IdentificationMode.manual;

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

  static final _standardFloorLevels = <String>[
    'External',
    '-3 (Basement)',
    '-2 (Basement)',
    '-1 (Basement)',
    '0 (Ground)',
    'Mezzanine',
    for (var i = 1; i <= 100; i++) i.toString(),
    'Roof level',
    'Roof',
  ];

  static const _colourOptions = <String>[
    'White',
    'Black',
    'Grey',
    'Brown',
    'Oak',
    'Walnut',
    'Beech',
    'Ash',
    'Redwood',
    'Primed only',
    'Custom',
  ];

  bool _isInstallationOnly(PreInstallItem item) {
    return item.surveyType == PreInstallSurveyType.installation_only;
  }

  String _workflowTypeTitle(PreInstallSurveyType type) {
    if (isSpecificationOrderWorkflowType(type)) {
      return 'Specification / Order';
    }
    return 'Installation Only';
  }

  String _workflowTypeSubtitle(PreInstallItem item) {
    if (!isSpecificationOrderWorkflowType(item.surveyType)) {
      return 'Client/main contractor supplied doorset.';
    }
    if (item.existingDoorRemovalRequired) {
      return 'Existing door removal required before installation.';
    }
    return 'New opening (no existing door removal required).';
  }

  void _assignDoorPlanPin({
    required PreInstallationSurveyBuilderData data,
    required void Function(PreInstallationSurveyBuilderData next) setData,
    required ProjectDrawing drawing,
    required FloorPlanPin pin,
  }) {
    final label =
        pin.label.trim().isNotEmpty ? pin.label.trim() : pin.doorNumber.trim();
    setData(
      data.copyWith(
        doorPinId: pin.id,
        doorDrawingId: drawing.id,
        doorRef: label.isEmpty ? data.doorRef : label,
        level: drawing.level.trim().isEmpty ? data.level : drawing.level.trim(),
      ),
    );
  }

  Future<void> _openDoorPlanPinSelector({
    required BuildContext context,
    required Survey survey,
    required String preferredLevel,
    required PreInstallationSurveyBuilderData data,
    required void Function(PreInstallationSurveyBuilderData next) setData,
  }) async {
    final result = await ProjectDrawingAccess.showDrawingPicker(
      context: context,
      survey: survey,
      preferredLevel: preferredLevel,
      selectionConfig: DrawingViewerSelectionConfig(
        enablePinPlacement: true,
        allowExistingPinSelection: true,
        autoAssignPinNumbers: false,
        highlightedPinId: data.doorPinId,
        hideOtherPins: true,
      ),
    );
    if (!context.mounted || result == null) return;
    _assignDoorPlanPin(
      data: data,
      setData: setData,
      drawing: result.drawing,
      pin: result.pin,
    );
  }

  Future<Uint8List?> _buildPinPreview({
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
          dpi: 240,
        )) {
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
    img.fillCircle(
      full,
      x: markerX,
      y: markerY,
      radius: 11,
      color: img.ColorRgb8(198, 40, 40),
    );
    img.drawCircle(
      full,
      x: markerX,
      y: markerY,
      radius: 18,
      color: img.ColorRgb8(255, 255, 255),
    );
    img.drawCircle(
      full,
      x: markerX,
      y: markerY,
      radius: 19,
      color: img.ColorRgb8(255, 255, 255),
    );
    return Uint8List.fromList(img.encodeJpg(full, quality: 92));
  }

  String _mimeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        res.bodyBytes.isEmpty) {
      throw Exception('download failed');
    }
    return res.bodyBytes;
  }

  List<PreInstallPhoto> _mergePreInstallPhotos(
      List<PreInstallPhoto> current, List<PreInstallPhoto> incoming) {
    final next = [...current];
    for (final photo in incoming) {
      final idx = next.indexWhere((p) => p.id == photo.id);
      if (idx == -1) {
        next.add(photo);
      } else {
        final existing = next[idx];
        next[idx] = existing.copyWith(
          fileName: photo.fileName,
          mimeType: photo.mimeType,
          cloudStoragePath: photo.cloudStoragePath,
          cloudDownloadUrl: photo.cloudDownloadUrl,
          bytes: existing.bytes.isEmpty ? photo.bytes : existing.bytes,
        );
      }
    }
    return next;
  }

  Future<List<PreInstallPhoto>> _uploadPreInstallPhotosToCloud({
    required String companyId,
    required String uploaderUid,
    required String type,
    required List<Map<String, dynamic>> files,
  }) async {
    final repo = ref.read(companyFileRepositoryProvider);
    final uploaded = <PreInstallPhoto>[];

    for (final file in files) {
      final fileName = file['name'] as String;
      final mimeType = file['mimeType'] as String;
      final bytes = file['bytes'] as Uint8List;
      try {
        final record = await repo.uploadBytes(
          companyId: companyId,
          entityType: 'preInstallPhoto',
          entityId: widget.itemId,
          createdByUid: uploaderUid,
          fileName: fileName,
          bytes: bytes,
          mimeType: mimeType,
          kind: CompanyFileKind.image,
          tags: [type, widget.surveyId],
        );

        uploaded.add(
          PreInstallPhoto(
            id: record.fileId,
            projectId: widget.surveyId,
            itemId: widget.itemId,
            type: type,
            fileName: fileName,
            mimeType: mimeType,
            bytes: bytes,
            cloudStoragePath: record.storagePath,
            cloudDownloadUrl: record.downloadUrl,
            createdAt: record.createdAt,
          ),
        );
      } catch (_) {
        // Continue remaining files.
      }
    }

    return uploaded;
  }

  Future<void> _syncCloudPreInstallPhotos({
    required String companyId,
    required SurveyController controller,
    required PreInstallItem item,
    required void Function(PreInstallationSurveyBuilderData next) setData,
  }) async {
    if (_cloudPhotoSynced) return;
    _cloudPhotoSynced = true;

    final repo = ref.read(companyFileRepositoryProvider);
    try {
      final records = await repo.listEntityFiles(
        companyId: companyId,
        entityType: 'preInstallPhoto',
        entityId: widget.itemId,
      );
      if (!mounted || records.isEmpty) return;

      final incoming = <PreInstallPhoto>[];
      for (final r in records) {
        Uint8List bytes = Uint8List(0);
        if (r.downloadUrl.trim().isNotEmpty) {
          try {
            bytes = await _downloadBytes(r.downloadUrl);
          } catch (_) {}
        }
        incoming.add(
          PreInstallPhoto(
            id: r.fileId,
            projectId: widget.surveyId,
            itemId: widget.itemId,
            type: r.tags.isEmpty ? 'sitePhoto' : r.tags.first,
            fileName: r.originalName,
            mimeType: r.mimeType,
            bytes: bytes,
            cloudStoragePath: r.storagePath,
            cloudDownloadUrl: r.downloadUrl,
            createdAt: r.createdAt,
          ),
        );
      }

      final merged = _mergePreInstallPhotos(item.preInstallPhotos, incoming);
      controller.setPreInstallPhotos(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        photos: merged,
      );

      final latest = controller.getPreInstallItem(
          surveyId: widget.surveyId, itemId: widget.itemId);
      if (latest != null && mounted) {
        setData(PreInstallationSurveyBuilderLogic.fromItem(latest));
      }
    } catch (_) {
      // Non-blocking fallback to local photos.
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = parseInspectionWorkspaceKey(widget.workspaceKey) ??
        InspectionWorkspace.fireDoor;
    final workspaceSlug = inspectionWorkspaceSlug(workspace);
    ref.watch(surveyControllerFamilyProvider(workspace));
    final controller =
        ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final settings = ref.watch(settingsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final survey = controller.getById(widget.surveyId);
    final item = controller.getPreInstallItem(
        surveyId: widget.surveyId, itemId: widget.itemId);
    final role = auth.role;
    final canManageWorkflow = role == UserRole.owner ||
        role == UserRole.admin ||
        role == UserRole.manager;

    if (survey == null || item == null) {
      return const Scaffold(
          body: Center(child: Text('Door specification not found')));
    }

    if (!_loaded) {
      _data = _sanitizeData(PreInstallationSurveyBuilderLogic.fromItem(item));
      _identificationMode = (_data!.doorPinId.trim().isNotEmpty &&
              survey.projectDrawings.isNotEmpty)
          ? _IdentificationMode.drawingPin
          : _IdentificationMode.manual;
      _loaded = true;
    }

    final data = _data!;
    final isInstallationOnly = _isInstallationOnly(item);
    final isSpecificationWorkflow =
        isSpecificationOrderWorkflowType(item.surveyType);

    void setData(PreInstallationSurveyBuilderData next) {
      setState(() => _data = _sanitizeData(next));
    }

    if (isSpecificationWorkflow &&
        data.supplyResponsibility !=
            PreInstallSupplyResponsibility.bw_supply_install) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setData(data.copyWith(
          supplyResponsibility:
              PreInstallSupplyResponsibility.bw_supply_install,
          customSupplyResponsibility: '',
        ));
      });
    }

    String formatDate(DateTime? value) {
      if (value == null) return '-';
      final day = value.day.toString().padLeft(2, '0');
      final month = value.month.toString().padLeft(2, '0');
      return '$day/$month/${value.year}';
    }

    String statusLabel(PreInstallItem current) {
      if (current.releasedToInstallation) {
        return 'Released to Installation';
      }
      if (current.deliveryConfirmed) {
        return 'Ready for Installation';
      }
      switch (current.preInstallationStatus) {
        case PreInstallationWorkflowStatus.draft:
          return 'Draft';
        case PreInstallationWorkflowStatus.survey_completed:
          return isSpecificationOrderWorkflowType(current.surveyType)
              ? 'Specification Complete'
              : 'Draft';
        case PreInstallationWorkflowStatus.approved_for_order:
          return 'Approved for Order';
        case PreInstallationWorkflowStatus.ready_for_factory_order:
          return 'Factory PDF Generated';
        case PreInstallationWorkflowStatus.ordered:
          return 'Awaiting Delivery';
        case PreInstallationWorkflowStatus.delivered_ready:
          return 'Delivery Confirmed';
        case PreInstallationWorkflowStatus.available_on_site:
          return 'Available on Site';
        case PreInstallationWorkflowStatus.released_to_installation:
          return 'Released to Installation';
      }
    }

    final pinCandidates = controller.getDrawingPinCandidates(widget.surveyId);
    final selectedDoorPlanPin = pinCandidates
        .cast<({ProjectDrawing drawing, FloorPlanPin pin})?>()
        .firstWhere(
          (entry) => entry != null && entry.pin.id == data.doorPinId,
          orElse: () => null,
        );
    final useDrawingPin = _identificationMode == _IdentificationMode.drawingPin;

    List<String> identificationErrors() {
      final list = <String>[];
      if (useDrawingPin) {
        if (selectedDoorPlanPin == null) {
          list.add('Select Pin before saving.');
        }
      } else if (data.doorRef.trim().isEmpty) {
        list.add('Door ID / Ref is required.');
      }
      return list;
    }

    final companyId = auth.companyId;
    if (companyId != null && companyId.isNotEmpty) {
      _syncCloudPreInstallPhotos(
        companyId: companyId,
        controller: controller,
        item: item,
        setData: setData,
      );
    }

    PreInstallItem currentItemFromData() {
      return PreInstallationSurveyBuilderLogic.toItem(
          current: item, data: data);
    }

    bool saveToStore({bool toast = false}) {
      final identificationValidationErrors = identificationErrors();
      if (identificationValidationErrors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(identificationValidationErrors.first)),
        );
        return false;
      }
      final updated = currentItemFromData();
      controller.updatePreInstallItem(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        update: (_) => updated,
      );
      if (toast) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Installation survey saved.')));
      }
      return true;
    }

    Future<void> addPhoto({required bool camera, required String type}) async {
      final companyId = auth.companyId;
      if (companyId == null || companyId.isEmpty) return;

      final filesPayload = <Map<String, dynamic>>[];
      if (camera) {
        final bytes = await _captureCamera();
        if (bytes == null) return;
        filesPayload.add({
          'name': 'pre_${DateTime.now().millisecondsSinceEpoch}.jpg',
          'mimeType': 'image/jpeg',
          'bytes': bytes,
        });
      } else {
        final files = await _pickUpload();
        if (files.isEmpty) return;
        for (final file in files) {
          filesPayload.add({
            'name': file.name,
            'mimeType': _mimeForName(file.name),
            'bytes': file.bytes!,
          });
        }
      }

      final uploaded = await _uploadPreInstallPhotosToCloud(
        companyId: companyId,
        uploaderUid: auth.uid,
        type: type,
        files: filesPayload,
      );
      if (uploaded.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Photo upload failed. Please try again.')),
        );
        return;
      }

      controller.addPreInstallPhotos(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        photos: uploaded,
      );

      final latest = controller.getPreInstallItem(
          surveyId: widget.surveyId, itemId: widget.itemId);
      if (latest != null) {
        setData(PreInstallationSurveyBuilderLogic.fromItem(latest));
      }
    }

    Future<void> generateSingleSpecPdf() async {
      if (!saveToStore()) return;
      final refreshed = controller.getPreInstallItem(
          surveyId: widget.surveyId, itemId: widget.itemId);
      if (refreshed == null) return;

      final action = kIsWeb
          ? _ExportAction.download
          : await showModalBottomSheet<_ExportAction>(
              context: context,
              showDragHandle: true,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('Download PDF'),
                      onTap: () => Navigator.pop(ctx, _ExportAction.download),
                    ),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Share by email'),
                      subtitle: const Text(
                          'Opens your share sheet (Mail / Gmail / Outlook etc).'),
                      onTap: () => Navigator.pop(ctx, _ExportAction.email),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );

      if (action == null) return;

      final single = survey.copyWith(preInstallItems: [refreshed]);
      final branding = resolvePdfBranding(settings);
      final bytes = await PreInstallPdfBuilder.buildCombinedProjectPdf(
        single,
        companyName: branding.companyName,
        companyLogoBytes: branding.logoBytes,
        reportHeaderText: branding.reportHeaderText,
        reportFooterText: branding.reportFooterText,
      );
      final fileName = buildReportFileName(
        settings: settings,
        survey: single,
        reportType: 'DoorSpec',
        extension: 'pdf',
      );

      if (action == _ExportAction.download) {
        if (kIsWeb) {
          downloadBytesWeb(
              bytes: bytes, fileName: fileName, mimeType: 'application/pdf');
        } else {
          await Printing.layoutPdf(onLayout: (_) async => bytes);
        }
        return;
      }

      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }

    Future<void> generateFactorySpecPdf() async {
      if (!saveToStore()) return;
      final refreshed = controller.getPreInstallItem(
          surveyId: widget.surveyId, itemId: widget.itemId);
      if (refreshed == null) return;

      if (!isSpecificationOrderWorkflowType(refreshed.surveyType)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Factory/Supplier PDF is available only for Specification / Order workflow items.',
            ),
          ),
        );
        return;
      }

      // Only generate if "Our company" supply responsibility
      if (refreshed.supplyResponsibility !=
          PreInstallSupplyResponsibility.bw_supply_install) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Factory/Supplier PDF is only available when "Our company" is supplying the doorset.',
            ),
          ),
        );
        return;
      }

      final action = kIsWeb
          ? _ExportAction.download
          : await showModalBottomSheet<_ExportAction>(
              context: context,
              showDragHandle: true,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('Download Factory Spec PDF'),
                      onTap: () => Navigator.pop(ctx, _ExportAction.download),
                    ),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Share by email'),
                      subtitle: const Text(
                          'Opens your share sheet (Mail / Gmail / Outlook etc).'),
                      onTap: () => Navigator.pop(ctx, _ExportAction.email),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );

      if (action == null) return;

      final branding = resolvePdfBranding(settings);
      final bytes = await FactorySupplierPdfBuilder.buildFactorySpecPdf(
        survey: survey,
        item: refreshed,
        companyName: branding.companyName,
        companyLogoBytes: branding.logoBytes,
        reportHeaderText: branding.reportHeaderText,
        reportFooterText: branding.reportFooterText,
      );
      final fileName = buildReportFileName(
        settings: settings,
        survey: survey,
        reportType: 'FactorySpec',
        extension: 'pdf',
      );

      if (action == _ExportAction.download) {
        if (kIsWeb) {
          downloadBytesWeb(
              bytes: bytes, fileName: fileName, mimeType: 'application/pdf');
        } else {
          await Printing.layoutPdf(onLayout: (_) async => bytes);
        }
        controller.updatePreInstallItem(
          surveyId: widget.surveyId,
          itemId: widget.itemId,
          update: (current) => current.copyWith(
            preInstallationStatus:
                PreInstallationWorkflowStatus.ready_for_factory_order,
          ),
        );
        return;
      }

      await Printing.sharePdf(bytes: bytes, filename: fileName);
      controller.updatePreInstallItem(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        update: (current) => current.copyWith(
          preInstallationStatus:
              PreInstallationWorkflowStatus.ready_for_factory_order,
        ),
      );
    }

    void setWorkflowStatus(PreInstallationWorkflowStatus status) {
      controller.updatePreInstallItem(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        update: (current) => current.copyWith(preInstallationStatus: status),
      );
    }

    Future<void> pickExpectedDeliveryDate() async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: item.expectedDeliveryDate ?? now,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 5),
      );
      if (picked == null) return;
      controller.updatePreInstallItem(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        update: (current) => current.copyWith(
          expectedDeliveryDate: DateTime(picked.year, picked.month, picked.day),
          clearExpectedDeliveryDate: false,
        ),
      );
    }

    void confirmDelivery() {
      final confirmedBy = auth.currentUser?.name.trim().isNotEmpty == true
          ? auth.currentUser!.name.trim()
          : (auth.email.trim().isNotEmpty ? auth.email.trim() : auth.uid);
      final now = DateTime.now();
      controller.updatePreInstallItem(
        surveyId: widget.surveyId,
        itemId: widget.itemId,
        update: (current) => current.copyWith(
          deliveryConfirmed: true,
          deliveryConfirmedAt: now,
          deliveryConfirmedBy: confirmedBy,
          preInstallationStatus: PreInstallationWorkflowStatus.delivered_ready,
        ),
      );
    }

    final expectedDeliveryReached = item.expectedDeliveryDate != null &&
        !item.deliveryConfirmed &&
        DateTime.now().isAfter(item.expectedDeliveryDate!);

    final errors = [
      ...identificationErrors(),
      ...PreInstallationSurveyBuilderLogic.validate(
        data,
        surveyType: item.surveyType,
      ),
    ];
    final customGlazingPhotos =
        data.photos.where((p) => p.type == 'glazingCustom').toList();
    final generalPhotos =
        data.photos.where((p) => p.type != 'glazingCustom').toList();

    final pageBody = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _section(
              title: 'Location / Identification',
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Workflow type: ${_workflowTypeTitle(item.surveyType)}\n${_workflowTypeSubtitle(item)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Door Identification',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
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
                        _data = _sanitizeData(
                          data.copyWith(doorDrawingId: '', doorPinId: ''),
                        );
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
                        _data = _sanitizeData(data.copyWith(doorRef: ''));
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  if (!useDrawingPin)
                    TextFormField(
                      initialValue: data.doorRef,
                      decoration: const InputDecoration(
                          labelText: 'Door ID / Ref (required)',
                          border: OutlineInputBorder()),
                      onChanged: (v) => setData(data.copyWith(
                          doorRef: v, doorDrawingId: '', doorPinId: '')),
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
                              onPressed: () => context.go(
                                  '/workspace/$workspaceSlug/modules/preinstall/projects/${widget.surveyId}/details'),
                              icon: const Icon(Icons.upload_file_outlined),
                              label: const Text('Upload Drawing'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
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
                              initialValue: pinCandidates.any(
                                      (entry) => entry.pin.id == data.doorPinId)
                                  ? data.doorPinId
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Select Pin',
                                border: OutlineInputBorder(),
                              ),
                              items: pinCandidates
                                  .map(
                                    (entry) => DropdownMenuItem<String>(
                                      value: entry.pin.id,
                                      child: Text(
                                        '${entry.pin.label.isNotEmpty ? entry.pin.label : entry.pin.doorNumber} (${entry.drawing.name})',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                final selected = pinCandidates.firstWhere(
                                    (entry) => entry.pin.id == value);
                                _assignDoorPlanPin(
                                  data: data,
                                  setData: setData,
                                  drawing: selected.drawing,
                                  pin: selected.pin,
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: () => _openDoorPlanPinSelector(
                                    context: context,
                                    survey: survey,
                                    preferredLevel: data.level,
                                    data: data,
                                    setData: setData,
                                  ),
                                  icon: const Icon(Icons.location_on_outlined),
                                  label: Text(selectedDoorPlanPin == null
                                      ? 'Select Pin'
                                      : 'Add Pin'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: selectedDoorPlanPin == null
                                      ? null
                                      : () {
                                          ProjectDrawingAccess
                                              .showDrawingViewer(
                                            context: context,
                                            surveyId: widget.surveyId,
                                            drawingId:
                                                selectedDoorPlanPin.drawing.id,
                                            fallbackTitle: selectedDoorPlanPin
                                                .drawing.fileName,
                                            drawingOverride:
                                                selectedDoorPlanPin.drawing,
                                            workspaceOverride: survey.workspace,
                                            selectionConfig:
                                                DrawingViewerSelectionConfig(
                                              highlightedPinId:
                                                  selectedDoorPlanPin.pin.id,
                                              hideOtherPins: true,
                                            ),
                                          );
                                        },
                                  icon: const Icon(Icons.open_in_full),
                                  label: const Text('Open Drawing'),
                                ),
                              ],
                            ),
                            if (selectedDoorPlanPin != null) ...[
                              const SizedBox(height: 10),
                              FutureBuilder<Uint8List?>(
                                future: _buildPinPreview(
                                  drawing: selectedDoorPlanPin.drawing,
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
                  ],
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 720;
                      final width = isWide
                          ? (constraints.maxWidth - 8) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: width,
                            child: AppSelectorCard(
                              title: 'Floor / Level',
                              value: data.level.trim().isEmpty
                                  ? '-'
                                  : data.level.trim(),
                              buttonLabel: data.level.trim().isEmpty
                                  ? 'Select floor'
                                  : 'Change floor',
                              icon: Icons.layers_outlined,
                              isSelected: data.level.trim().isNotEmpty,
                              onPressed: () async {
                                final picked = await _pickFloorLevel(context,
                                    currentValue: data.level);
                                if (picked == null) return;
                                setData(data.copyWith(level: picked));
                              },
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: AppSelectorCard(
                              title: 'Location',
                              value: data.location.trim().isEmpty
                                  ? '-'
                                  : data.location.trim(),
                              buttonLabel: data.location.trim().isEmpty
                                  ? 'Select location'
                                  : 'Change location',
                              icon: Icons.place_outlined,
                              isSelected: data.location.trim().isNotEmpty,
                              onPressed: () async {
                                final picked = await _pickDoorLocation(context,
                                    currentValue: data.location);
                                if (picked == null) return;
                                setData(data.copyWith(location: picked));
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            if (isInstallationOnly)
              _section(
                title: '2. Supply Responsibility',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Door / Doorset supplied by',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppChoicePill(
                          label: 'Our company',
                          selected: data.supplyResponsibility ==
                              PreInstallSupplyResponsibility.bw_supply_install,
                          onPressed: () => setData(data.copyWith(
                            supplyResponsibility: PreInstallSupplyResponsibility
                                .bw_supply_install,
                            customSupplyResponsibility: '',
                          )),
                        ),
                        AppChoicePill(
                          label: 'Client supplied',
                          selected: data.supplyResponsibility ==
                              PreInstallSupplyResponsibility.client_supplied,
                          onPressed: () => setData(data.copyWith(
                            supplyResponsibility:
                                PreInstallSupplyResponsibility.client_supplied,
                            customSupplyResponsibility: '',
                          )),
                        ),
                        AppChoicePill(
                          label: 'Main contractor',
                          selected: data.supplyResponsibility ==
                              PreInstallSupplyResponsibility
                                  .main_contractor_supplied,
                          onPressed: () => setData(data.copyWith(
                            supplyResponsibility: PreInstallSupplyResponsibility
                                .main_contractor_supplied,
                            customSupplyResponsibility: '',
                          )),
                        ),
                        AppChoicePill(
                          label: 'Other / Custom',
                          selected: data.supplyResponsibility ==
                              PreInstallSupplyResponsibility.custom,
                          onPressed: () => setData(data.copyWith(
                            supplyResponsibility:
                                PreInstallSupplyResponsibility.custom,
                          )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        'Installation Only can be client/main contractor supplied. This affects delivery and release flow only.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          height: 1.5,
                        ),
                      ),
                    ),
                    if (data.supplyResponsibility ==
                        PreInstallSupplyResponsibility.custom) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: data.customSupplyResponsibility,
                        decoration: const InputDecoration(
                          labelText: 'Custom supplier / responsibility details',
                          border: OutlineInputBorder(),
                          hintText: 'e.g., Specify or XYZ Company',
                        ),
                        maxLines: 2,
                        onChanged: (v) => setData(
                            data.copyWith(customSupplyResponsibility: v)),
                      ),
                    ],
                  ],
                ),
              ),
            if (isSpecificationWorkflow)
              _section(
                title: '2. Supply Responsibility',
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    'Specification / Order defaults to "Our company" supply for factory/manufacturing workflow.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            _section(
              title: '3. Door Type & Handing',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isInstallationOnly)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text(
                        'Installation Only keeps the data light: no manufacturing measurements or factory specification steps are required.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade800,
                          height: 1.35,
                        ),
                      ),
                    ),
                  const Text('Configuration',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _diagramOptionButton(
                          label: 'Single door',
                          subtitle: 'One leaf',
                          icon: Icons.door_front_door_outlined,
                          selected: data.doorType == BuilderDoorType.single,
                          onTap: () => setData(
                              data.copyWith(doorType: BuilderDoorType.single)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _diagramOptionButton(
                          label: 'Double door',
                          subtitle: 'Two leaves',
                          icon: Icons.view_week_outlined,
                          selected: data.doorType == BuilderDoorType.doubleLeaf,
                          onTap: () => setData(data.copyWith(
                              doorType: BuilderDoorType.doubleLeaf)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('Scope',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _diagramOptionButton(
                          label: 'Door only',
                          subtitle: 'No frame input',
                          icon: Icons.crop_portrait_outlined,
                          selected: data.frameMode == BuilderFrameMode.doorOnly,
                          onTap: () => setData(data.copyWith(
                              frameMode: BuilderFrameMode.doorOnly,
                              clearFrameWidth: true,
                              clearFrameHeight: true)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _diagramOptionButton(
                          label: 'Door + frame',
                          subtitle: 'Frame dimensions',
                          icon: Icons.crop_square_outlined,
                          selected:
                              data.frameMode == BuilderFrameMode.doorAndFrame,
                          onTap: () => setData(data.copyWith(
                              frameMode: BuilderFrameMode.doorAndFrame)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('Fire rating',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        PreInstallationSurveyBuilderLogic.supportedFireRatings
                            .map(
                              (r) => AppChoicePill(
                                label: r,
                                selected: data.fireRating == r,
                                onPressed: () =>
                                    setData(data.copyWith(fireRating: r)),
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 10),
                  const Text('Door orientation',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: AppChoicePill(
                          label: 'Internal',
                          selected: !data.isExternal,
                          onPressed: () =>
                              setData(data.copyWith(isExternal: false)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppChoicePill(
                          label: 'External',
                          selected: data.isExternal,
                          onPressed: () =>
                              setData(data.copyWith(isExternal: true)),
                        ),
                      ),
                    ],
                  ),
                  if (data.doorType == BuilderDoorType.single) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _diagramOptionButton(
                            label: 'Hinges left',
                            subtitle: 'Open from left',
                            icon: Icons.subdirectory_arrow_right,
                            selected: data.hingesSide == 'left',
                            onTap: () =>
                                setData(data.copyWith(hingesSide: 'left')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _diagramOptionButton(
                            label: 'Hinges right',
                            subtitle: 'Open from right',
                            icon: Icons.subdirectory_arrow_left,
                            selected: data.hingesSide == 'right',
                            onTap: () =>
                                setData(data.copyWith(hingesSide: 'right')),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      'Double doors show primary leaf in preview based on handing side.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
            _section(
              title: '4. Visual Door Preview',
              child: _DoorPreview(data: data),
            ),
            if (!isInstallationOnly)
              _section(
                title: '5. Measurements',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.frameMode == BuilderFrameMode.doorOnly
                          ? 'Door only: leaf measurements are the primary manufacturing sizes.'
                          : 'Door + Frame: overall frame sizes are the primary manufacturing sizes.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    if (data.frameMode == BuilderFrameMode.doorAndFrame) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _numberInput(
                              label: 'Overall frame width (mm)',
                              value: data.frameWidth,
                              onChanged: (v) =>
                                  setData(data.copyWith(frameWidth: v)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numberInput(
                              label: 'Overall frame height (mm)',
                              value: data.frameHeight,
                              onChanged: (v) =>
                                  setData(data.copyWith(frameHeight: v)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _numberInput(
                              label: 'Structural opening width (mm)',
                              value: data.openingWidth,
                              onChanged: (v) =>
                                  setData(data.copyWith(openingWidth: v)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numberInput(
                              label: 'Structural opening height (mm)',
                              value: data.openingHeight,
                              onChanged: (v) =>
                                  setData(data.copyWith(openingHeight: v)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Structural opening fields are optional unless your project specification requires them.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _numberInput(
                              label: 'Door leaf width (mm) (optional)',
                              value: data.leafWidth,
                              onChanged: (v) =>
                                  setData(data.copyWith(leafWidth: v)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numberInput(
                              label: 'Door leaf height (mm) (optional)',
                              value: data.leafHeight,
                              onChanged: (v) =>
                                  setData(data.copyWith(leafHeight: v)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _numberInput(
                        label: 'Door thickness (mm) (optional)',
                        value: data.leafThickness,
                        onChanged: (v) =>
                            setData(data.copyWith(leafThickness: v)),
                      ),
                    ],
                    if (data.frameMode == BuilderFrameMode.doorOnly) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _numberInput(
                              label: 'Door leaf width (mm)',
                              value: data.leafWidth,
                              onChanged: (v) =>
                                  setData(data.copyWith(leafWidth: v)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numberInput(
                              label: 'Door leaf height (mm)',
                              value: data.leafHeight,
                              onChanged: (v) =>
                                  setData(data.copyWith(leafHeight: v)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _numberInput(
                        label: 'Door thickness (mm) (optional)',
                        value: data.leafThickness,
                        onChanged: (v) =>
                            setData(data.copyWith(leafThickness: v)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _numberInput(
                              label: 'Structural opening width (mm) (optional)',
                              value: data.openingWidth,
                              onChanged: (v) =>
                                  setData(data.copyWith(openingWidth: v)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numberInput(
                              label:
                                  'Structural opening height (mm) (optional)',
                              value: data.openingHeight,
                              onChanged: (v) =>
                                  setData(data.copyWith(openingHeight: v)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            if (!isInstallationOnly)
              _section(
                title: '6. Glazing / Grille Style + Panels',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _visibleVisionOptions(data).length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemBuilder: (context, index) {
                        final vision = _visibleVisionOptions(data)[index];
                        return _VisionStyleTile(
                          selected: data.visionPanel == vision,
                          label: _visionLabel(vision),
                          style: vision,
                          onTap: () =>
                              setData(data.copyWith(visionPanel: vision)),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Select a standard factory door style. For unusual layouts use notes/photos below.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'For unusual glazing, use Photos & Notes below instead of custom glazing presets.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    if (data.visionPanel == BuilderVisionPanel.custom) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          'Legacy record: custom glazing was selected previously. It is preserved for compatibility.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: data.customGlazingNote,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Legacy glazing note',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) =>
                            setData(data.copyWith(customGlazingNote: v)),
                      ),
                      if (customGlazingPhotos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in customGlazingPhotos)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: p.bytes.isEmpty
                                    ? Container(
                                        width: 90,
                                        height: 90,
                                        color: const Color(0xFFE8EEF7),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                            Icons.cloud_done_outlined,
                                            color: Color(0xFF1565C0)),
                                      )
                                    : Image.memory(
                                        Uint8List.fromList(p.bytes),
                                        width: 90,
                                        height: 90,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            if (!isInstallationOnly)
              _section(
                title: '6.1 Side / Top Panels',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      value: data.sidePanelLeft,
                      title: const Text('Left panel'),
                      onChanged: (v) =>
                          setData(data.copyWith(sidePanelLeft: v)),
                    ),
                    SwitchListTile(
                      value: data.sidePanelRight,
                      title: const Text('Right panel'),
                      onChanged: (v) =>
                          setData(data.copyWith(sidePanelRight: v)),
                    ),
                    SwitchListTile(
                      value: data.overPanel,
                      title: const Text('Over panel'),
                      onChanged: (v) => setData(data.copyWith(overPanel: v)),
                    ),
                    if (data.sidePanelLeft || data.sidePanelRight) ...[
                      const SizedBox(height: 6),
                      _numberInput(
                        label: 'Side panel opening width (mm)',
                        value: data.sidePanelOpeningWidth,
                        onChanged: (v) =>
                            setData(data.copyWith(sidePanelOpeningWidth: v)),
                      ),
                    ],
                    if (data.overPanel) ...[
                      const SizedBox(height: 8),
                      _numberInput(
                        label: 'Over panel opening height (mm)',
                        value: data.overPanelOpeningHeight,
                        onChanged: (v) =>
                            setData(data.copyWith(overPanelOpeningHeight: v)),
                      ),
                    ],
                  ],
                ),
              ),
            if (!isInstallationOnly)
              _section(
                title: '7. Ironmongery / Extras',
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: data.lockType,
                      decoration: appSelectFieldDecoration(
                        labelText: 'Lock type',
                        hasSelection: data.lockType.trim().isNotEmpty &&
                            data.lockType != 'none',
                      ),
                      items: PreInstallationSurveyBuilderLogic.lockTypeOptions
                          .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (v) =>
                          setData(data.copyWith(lockType: v ?? 'none')),
                    ),
                    if (data.lockType == 'custom') ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: data.customLockType,
                        decoration: const InputDecoration(
                            labelText: 'Custom lock type',
                            border: OutlineInputBorder()),
                        onChanged: (v) =>
                            setData(data.copyWith(customLockType: v)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: data.closer,
                      title: const Text('Closer'),
                      onChanged: (v) => setData(data.copyWith(closer: v)),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _extraChip('Letter plate', data.letterPlate,
                            (v) => setData(data.copyWith(letterPlate: v))),
                        _extraChip('Spyhole', data.spyhole,
                            (v) => setData(data.copyWith(spyhole: v))),
                        _extraChip(
                            'Grille',
                            data.ventilationGrille,
                            (v) =>
                                setData(data.copyWith(ventilationGrille: v))),
                        _extraChip('Drop down seal', data.dropDownSeal,
                            (v) => setData(data.copyWith(dropDownSeal: v))),
                        _extraChip('Signage', data.signage,
                            (v) => setData(data.copyWith(signage: v))),
                        _extraChip(
                            'Door number / plaque',
                            data.doorNumberPlaque,
                            (v) => setData(data.copyWith(doorNumberPlaque: v))),
                      ],
                    ),
                    if (data.signage) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: data.signageText,
                        decoration: const InputDecoration(
                            labelText: 'Signage text',
                            border: OutlineInputBorder()),
                        onChanged: (v) =>
                            setData(data.copyWith(signageText: v)),
                      ),
                    ],
                    if (data.doorNumberPlaque) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: data.plaqueText,
                        decoration: const InputDecoration(
                            labelText: 'Door number / plaque text',
                            border: OutlineInputBorder()),
                        onChanged: (v) => setData(data.copyWith(plaqueText: v)),
                      ),
                    ],
                  ],
                ),
              ),
            if (!isInstallationOnly)
              _section(
                title: '7.1 Perimeter / Intumescent Seals',
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppChoicePill(
                          label: 'No seal',
                          selected: data.sealType == 'none',
                          onPressed: () =>
                              setData(data.copyWith(sealType: 'none')),
                        ),
                        AppChoicePill(
                          label: 'Intumescent',
                          selected: data.sealType == 'intumescent',
                          onPressed: () =>
                              setData(data.copyWith(sealType: 'intumescent')),
                        ),
                        AppChoicePill(
                          label: 'Smoke seal',
                          selected: data.sealType == 'smoke',
                          onPressed: () =>
                              setData(data.copyWith(sealType: 'smoke')),
                        ),
                        AppChoicePill(
                          label: 'Combined seal',
                          selected: data.sealType == 'combined',
                          onPressed: () =>
                              setData(data.copyWith(sealType: 'combined')),
                        ),
                      ],
                    ),
                    if (data.sealType != 'none') ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          AppChoicePill(
                            label: 'In frame',
                            selected: data.sealPosition == 'inFrame',
                            onPressed: () =>
                                setData(data.copyWith(sealPosition: 'inFrame')),
                          ),
                          AppChoicePill(
                            label: 'On door',
                            selected: data.sealPosition == 'onDoor',
                            onPressed: () =>
                                setData(data.copyWith(sealPosition: 'onDoor')),
                          ),
                          AppChoicePill(
                            label: 'Other',
                            selected: data.sealPosition == 'other',
                            onPressed: () =>
                                setData(data.copyWith(sealPosition: 'other')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: data.sealNote,
                        decoration: const InputDecoration(
                            labelText: 'Seal note (optional)',
                            border: OutlineInputBorder()),
                        onChanged: (v) => setData(data.copyWith(sealNote: v)),
                      ),
                    ],
                  ],
                ),
              ),
            if (!isInstallationOnly)
              _section(
                title: '8. Finish',
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppChoicePill(
                          label: 'Primer',
                          selected: data.finishType == BuilderFinishType.primer,
                          onPressed: () => setData(data.copyWith(
                              finishType: BuilderFinishType.primer)),
                        ),
                        AppChoicePill(
                          label: 'Painted',
                          selected:
                              data.finishType == BuilderFinishType.painted,
                          onPressed: () => setData(data.copyWith(
                              finishType: BuilderFinishType.painted)),
                        ),
                        AppChoicePill(
                          label: 'Veneer',
                          selected: data.finishType == BuilderFinishType.veneer,
                          onPressed: () => setData(data.copyWith(
                              finishType: BuilderFinishType.veneer)),
                        ),
                        AppChoicePill(
                          label: 'Laminate',
                          selected:
                              data.finishType == BuilderFinishType.laminate,
                          onPressed: () => setData(data.copyWith(
                              finishType: BuilderFinishType.laminate)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedColourOption(data.colour),
                      decoration: appSelectFieldDecoration(
                        labelText: 'Colour / Finish',
                        hasSelection: data.colour.trim().isNotEmpty,
                      ),
                      items: _colourOptions
                          .map((value) => DropdownMenuItem<String>(
                              value: value, child: Text(value)))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        if (value == 'Custom') {
                          setData(data.copyWith(
                              colour: data.colour.trim().isEmpty
                                  ? ''
                                  : data.colour));
                          return;
                        }
                        setData(data.copyWith(colour: value));
                      },
                    ),
                    if (_selectedColourOption(data.colour) == 'Custom') ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue:
                            _isPresetColour(data.colour) ? '' : data.colour,
                        decoration: const InputDecoration(
                            labelText: 'Custom colour / finish',
                            border: OutlineInputBorder()),
                        onChanged: (v) =>
                            setData(data.copyWith(colour: v.trim())),
                      ),
                    ],
                  ],
                ),
              ),
            _section(
              title: '9. Photos & Notes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              addPhoto(camera: true, type: 'sitePhoto'),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Take photo'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              addPhoto(camera: false, type: 'sitePhoto'),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Upload photo'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (generalPhotos.isEmpty)
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('No general photos added.'))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (int i = 0; i < generalPhotos.length; i++)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: generalPhotos[i].bytes.isEmpty
                                ? Container(
                                    width: 90,
                                    height: 90,
                                    color: const Color(0xFFE8EEF7),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.cloud_done_outlined,
                                        color: Color(0xFF1565C0)),
                                  )
                                : Image.memory(
                                    Uint8List.fromList(generalPhotos[i].bytes),
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: data.notes,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: isInstallationOnly
                          ? 'Installation notes'
                          : 'Additional notes',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setData(data.copyWith(notes: v)),
                  ),
                ],
              ),
            ),
            _section(
              title: '10. Save / Factory PDF / Order Status',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isInstallationOnly)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Installation Only items are excluded from manufacturing/specification exports.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  if (errors.isNotEmpty) ...[
                    const Text(
                        'Please complete required fields before generating PDF.',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    for (final e in errors) Text('- $e'),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => saveToStore(toast: true),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save draft'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (!isInstallationOnly)
                              ? () {
                                  saveToStore(toast: true);
                                  if (canManageWorkflow) {
                                    setWorkflowStatus(
                                        PreInstallationWorkflowStatus
                                            .survey_completed);
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.task_alt_outlined),
                          label: const Text('Save Specification'),
                        ),
                      ),
                    ],
                  ),
                  if (!isInstallationOnly) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: errors.isEmpty ? generateSingleSpecPdf : null,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Generate Specification PDF'),
                    ),
                  ],
                ],
              ),
            ),
            _section(
              title: '10.1 Factory / Supplier PDF',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isInstallationOnly)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.alt_route_outlined,
                            color: Colors.green.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Installation Only bypasses factory ordering and delivery waiting. This item moves directly into the installation approval flow.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade800,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (data.supplyResponsibility !=
                      PreInstallSupplyResponsibility.bw_supply_install)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.grey.shade600,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Factory order PDF is not required for this supply responsibility.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.blue.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Generate factory order pack for supplier / manufacturing review',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This PDF contains the measurements, doorset details and ordering information required before release to installation.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed:
                                errors.isEmpty ? generateFactorySpecPdf : null,
                            icon: const Icon(Icons.factory_outlined),
                            label: const Text('Generate Factory Order PDF'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _section(
              title: '10.2 Order / Delivery Status',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (expectedDeliveryReached)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        'Delivery expected. Confirm delivery before release.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Current status: ${statusLabel(item)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Expected delivery date',
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(
                      text: formatDate(item.expectedDeliveryDate),
                    ),
                    onTap: canManageWorkflow ? pickExpectedDeliveryDate : null,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: canManageWorkflow &&
                                isSpecificationOrderWorkflowType(
                                    item.surveyType)
                            ? () => setWorkflowStatus(
                                PreInstallationWorkflowStatus.survey_completed)
                            : null,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Mark Specification Complete'),
                      ),
                      OutlinedButton.icon(
                        onPressed: canManageWorkflow
                            ? () => setWorkflowStatus(
                                PreInstallationWorkflowStatus.ordered)
                            : null,
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: const Text('Mark Ordered'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: canManageWorkflow ? confirmDelivery : null,
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('Confirm Delivery'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.deliveryConfirmed
                        ? 'Confirmed by ${item.deliveryConfirmedBy.trim().isEmpty ? '-' : item.deliveryConfirmedBy.trim()} on ${formatDate(item.deliveryConfirmedAt)}'
                        : 'Delivery not confirmed yet.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Release to Installation is managed from the saved item status/actions area and bulk workflow tools.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final pageTitle =
        'Installation Survey - ${data.doorRef.isEmpty ? _workflowTypeTitle(item.surveyType) : data.doorRef}';

    if (kIsWeb) {
      return FireDoorWebShellScaffold(
        title: pageTitle,
        workspaceKey: widget.workspaceKey,
        currentRoute: '/workspace/$workspaceSlug/modules/preinstall/projects',
        body: pageBody,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(pageTitle),
        bottom: WorkspaceSwitchCardsBar(currentWorkspaceKey: workspaceSlug),
        actions: [
          IconButton(
            onPressed: () => ProjectDrawingAccess.showDrawingPicker(
                context: context, survey: survey),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'View Drawing',
          ),
        ],
      ),
      drawer: AppDrawer(
          currentRoute:
              '/workspace/$workspaceSlug/modules/preinstall/projects'),
      body: pageBody,
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _numberInput({
    required String label,
    required double? value,
    required void Function(double?) onChanged,
  }) {
    return TextFormField(
      initialValue: value == null ? '' : value.toStringAsFixed(1),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      onChanged: (v) => onChanged(double.tryParse(v.trim())),
    );
  }

  Widget _extraChip(
      String label, bool selected, void Function(bool) onChanged) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppSelectionColors.selectedFill,
      checkmarkColor: AppSelectionColors.selectedGreen,
      side: BorderSide(
          color: selected
              ? AppSelectionColors.selectedGreen
              : Colors.grey.shade300),
      onSelected: onChanged,
    );
  }

  Widget _diagramOptionButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? AppSelectionColors.selectedFill
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppSelectionColors.selectedGreen
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? AppSelectionColors.selectedGreen
                  : const Color(0xFF455A64),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppSelectionColors.selectedGreen
                          : const Color(0xFF263238),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreInstallationSurveyBuilderData _sanitizeData(
      PreInstallationSurveyBuilderData data) {
    var next = data;

    if (next.doorType == BuilderDoorType.doubleLeaf &&
        !_visibleVisionOptions(next).contains(next.visionPanel)) {
      next = next.copyWith(visionPanel: BuilderVisionPanel.narrowVertical);
    }

    return next;
  }

  List<BuilderVisionPanel> _visibleVisionOptions(
      PreInstallationSurveyBuilderData data) {
    if (data.doorType == BuilderDoorType.doubleLeaf) {
      return const [
        BuilderVisionPanel.none,
        BuilderVisionPanel.narrowVertical,
        BuilderVisionPanel.halfHeight,
        BuilderVisionPanel.fullHeight,
        BuilderVisionPanel.lowGrille,
        BuilderVisionPanel.highGrille,
        BuilderVisionPanel.glazingLowGrille,
      ];
    }

    return const [
      BuilderVisionPanel.none,
      BuilderVisionPanel.top,
      BuilderVisionPanel.narrowVertical,
      BuilderVisionPanel.halfHeight,
      BuilderVisionPanel.fullHeight,
      BuilderVisionPanel.lowGrille,
      BuilderVisionPanel.highGrille,
      BuilderVisionPanel.glazingLowGrille,
      BuilderVisionPanel.fullGlazed,
    ];
  }

  bool _isPresetColour(String value) {
    final normalized = value.trim().toLowerCase();
    return _colourOptions
        .where((entry) => entry != 'Custom')
        .any((entry) => entry.toLowerCase() == normalized);
  }

  String _selectedColourOption(String colour) {
    final normalized = colour.trim().toLowerCase();
    for (final option in _colourOptions) {
      if (option == 'Custom') continue;
      if (option.toLowerCase() == normalized) return option;
    }
    return 'Custom';
  }

  String _visionLabel(BuilderVisionPanel value) {
    switch (value) {
      case BuilderVisionPanel.none:
        return 'Blank';
      case BuilderVisionPanel.top:
        return 'Small Top Vision Panel';
      case BuilderVisionPanel.narrowVertical:
        return 'Narrow Vertical Vision Panel';
      case BuilderVisionPanel.halfHeight:
        return 'Half Height Vision Panel';
      case BuilderVisionPanel.fullHeight:
        return 'Full Height Vision Panel';
      case BuilderVisionPanel.lowGrille:
        return 'Low Grille';
      case BuilderVisionPanel.highGrille:
        return 'High Grille';
      case BuilderVisionPanel.glazingLowGrille:
        return 'Glazing + Low Grille';
      case BuilderVisionPanel.fullGlazed:
        return 'Full Glazed Style';
      case BuilderVisionPanel.custom:
        return 'Other / Legacy';
    }
  }

  Future<String?> _pickDoorLocation(BuildContext context,
      {required String currentValue}) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _SearchPickerSheet(
          title: 'Door location',
          options: _standardDoorLocations,
          initialValue: currentValue,
          customTitle: 'Custom door location',
          customLabel: 'Door location',
        );
      },
    );
  }

  Future<String?> _pickFloorLevel(BuildContext context,
      {required String currentValue}) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _SearchPickerSheet(
          title: 'Floor / Level',
          options: _standardFloorLevels,
          initialValue: currentValue,
          customTitle: 'Custom Floor / Level',
          customLabel: 'Floor / Level',
        );
      },
    );
    return picked;
  }

  Future<Uint8List?> _captureCamera() async {
    final picker = ImagePicker();
    final x =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (x == null) return null;
    return x.readAsBytes();
  }

  Future<List<PlatformFile>> _pickUpload() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (res == null) return const [];
    return res.files.where((f) => f.bytes != null).toList();
  }
}

class _DoorPreview extends StatelessWidget {
  final PreInstallationSurveyBuilderData data;

  const _DoorPreview({required this.data});

  List<String> _selectedExtras() {
    final extras = <String>[];
    if (data.closer) extras.add('Closer');
    if (data.letterPlate) extras.add('Letter plate');
    if (data.spyhole) extras.add('Spyhole');
    if (data.ventilationGrille) extras.add('Grille');
    if (data.dropDownSeal) extras.add('Drop seal');
    if (data.signage) extras.add('Signage');
    if (data.doorNumberPlaque) extras.add('Door plaque');
    return extras;
  }

  @override
  Widget build(BuildContext context) {
    final extras = _selectedExtras();
    return Container(
      height: 312,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Text(
            'Configuration: ${data.doorType == BuilderDoorType.doubleLeaf ? 'Double leaf' : 'Single leaf'} • ${data.frameMode == BuilderFrameMode.doorAndFrame ? 'Door + Frame' : 'Door Only'}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF455A64)),
          ),
          const SizedBox(height: 4),
          Text(
            data.doorType == BuilderDoorType.doubleLeaf
                ? 'Primary leaf follows selected handing side in this preview.'
                : 'Handing: ${data.hingesSide == 'left' ? 'Hinges left' : 'Hinges right'}',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF607D8B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.maxWidth - 24;
                final previewWidth = available < 220
                    ? 220.0
                    : (available > 560 ? 560.0 : available);
                final previewHeight = previewWidth * (190 / 320);
                return Center(
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: 320,
                        height: 190,
                        child: _schematic(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (extras.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final extra in extras)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9EEF5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        extra,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF455A64),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _schematic() {
    const leafH = 136.0;
    const singleLeafW = 62.0;
    const doubleLeafW = 50.0;
    const leafGap = 4.0;
    const framePad = 7.0;
    const sidePanelW = 24.0;
    const overPanelH = 24.0;

    final hasFrame = data.frameMode == BuilderFrameMode.doorAndFrame;
    final leavesW = data.doorType == BuilderDoorType.single
        ? singleLeafW
        : (doubleLeafW * 2 + leafGap);
    final coreW = hasFrame ? leavesW + framePad * 2 : leavesW;
    final coreH = hasFrame ? leafH + framePad * 2 : leafH;

    final leftPanelW = data.sidePanelLeft ? sidePanelW : 0.0;
    final rightPanelW = data.sidePanelRight ? sidePanelW : 0.0;
    final topPanelH = data.overPanel ? overPanelH : 0.0;

    final blockW = leftPanelW + coreW + rightPanelW;
    final blockH = topPanelH + coreH;

    final startX = (320 - blockW) / 2;
    final startY = (190 - blockH) / 2;

    final coreX = startX + leftPanelW;
    final coreY = startY + topPanelH;

    final leafAreaX = hasFrame ? coreX + framePad : coreX;
    final leafAreaY = hasFrame ? coreY + framePad : coreY;

    return Stack(
      children: [
        if (data.overPanel)
          Positioned(
            left: coreX,
            top: startY,
            width: coreW,
            height: topPanelH,
            child: _panel('Over'),
          ),
        if (data.sidePanelLeft)
          Positioned(
            left: startX,
            top: coreY,
            width: leftPanelW,
            height: coreH,
            child: _panel('L'),
          ),
        if (data.sidePanelRight)
          Positioned(
            left: coreX + coreW,
            top: coreY,
            width: rightPanelW,
            height: coreH,
            child: _panel('R'),
          ),
        if (hasFrame)
          Positioned(
            left: coreX,
            top: coreY,
            width: coreW,
            height: coreH,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                border: Border.all(color: const Color(0xFF546E7A), width: 2),
              ),
            ),
          ),
        if (data.doorType == BuilderDoorType.single)
          Positioned(
            left: leafAreaX,
            top: leafAreaY,
            width: singleLeafW,
            height: leafH,
            child: _leaf(
              mirror: false,
              hingeLeft: data.hingesSide == 'left',
              leafLabel: 'Leaf',
            ),
          )
        else ...[
          Positioned(
            left: leafAreaX,
            top: leafAreaY,
            width: doubleLeafW,
            height: leafH,
            child: _leaf(
              mirror: false,
              hingeLeft: true,
              leafLabel: data.hingesSide == 'left' ? 'Primary' : 'Leaf',
            ),
          ),
          Positioned(
            left: leafAreaX + doubleLeafW + leafGap,
            top: leafAreaY,
            width: doubleLeafW,
            height: leafH,
            child: _leaf(
              mirror: true,
              hingeLeft: false,
              leafLabel: data.hingesSide == 'right' ? 'Primary' : 'Leaf',
            ),
          ),
          Positioned(
            left: leafAreaX + doubleLeafW,
            top: leafAreaY,
            width: leafGap,
            height: leafH,
            child: Container(color: const Color(0xFF90A4AE)),
          ),
        ],
      ],
    );
  }

  Widget _panel(String label) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF90A4AE)),
      ),
      child: Center(
          child: Text(label,
              style:
                  const TextStyle(fontSize: 9, fontWeight: FontWeight.w700))),
    );
  }

  Widget _leaf(
      {required bool mirror,
      required bool hingeLeft,
      required String leafLabel}) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFF607D8B), width: 1.4)),
      child: Stack(
        children: [
          _hinges(hingeLeft: hingeLeft),
          if (data.visionPanel != BuilderVisionPanel.none)
            _vision(mirror: mirror),
          Positioned(
            bottom: 2,
            left: 2,
            right: 2,
            child: Text(
              leafLabel,
              style: const TextStyle(fontSize: 7, color: Color(0xFF455A64)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hinges({required bool hingeLeft}) {
    return Positioned(
      left: hingeLeft ? 1 : null,
      right: hingeLeft ? null : 1,
      top: 16,
      bottom: 16,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          _HingePlate(),
          _HingePlate(),
          _HingePlate(),
        ],
      ),
    );
  }

  Widget _vision({required bool mirror}) {
    switch (data.visionPanel) {
      case BuilderVisionPanel.top:
        return Positioned(
          left: 16,
          right: 16,
          top: 16,
          height: 16,
          child: _glass(),
        );
      case BuilderVisionPanel.narrowVertical:
        return Positioned(
          left: mirror ? null : 16,
          right: mirror ? 16 : null,
          top: 18,
          bottom: 24,
          width: 14,
          child: _glass(),
        );
      case BuilderVisionPanel.halfHeight:
        return Positioned(
          left: mirror ? null : 16,
          right: mirror ? 16 : null,
          top: 18,
          height: 52,
          width: 16,
          child: _glass(),
        );
      case BuilderVisionPanel.fullHeight:
        return Positioned(
          left: mirror ? null : 16,
          right: mirror ? 16 : null,
          top: 12,
          bottom: 12,
          width: 16,
          child: _glass(),
        );
      case BuilderVisionPanel.fullGlazed:
        return Positioned(
          left: 10,
          right: 10,
          top: 10,
          bottom: 10,
          child: _glass(),
        );
      case BuilderVisionPanel.lowGrille:
        return Positioned(
          left: 10,
          right: 10,
          bottom: 14,
          height: 16,
          child: _grille(),
        );
      case BuilderVisionPanel.highGrille:
        return Positioned(
          left: 10,
          right: 10,
          top: 12,
          height: 16,
          child: _grille(),
        );
      case BuilderVisionPanel.glazingLowGrille:
        return Stack(
          children: [
            Positioned(
              left: mirror ? null : 16,
              right: mirror ? 16 : null,
              top: 16,
              height: 46,
              width: 16,
              child: _glass(),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 14,
              height: 16,
              child: _grille(),
            ),
          ],
        );
      case BuilderVisionPanel.custom:
        return Positioned(
          left: 12,
          right: 12,
          top: 36,
          bottom: 24,
          child: _glass(),
        );
      case BuilderVisionPanel.none:
        return const SizedBox.shrink();
    }
  }

  Widget _glass() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFB3E5FC),
        border: Border.all(color: const Color(0xFF0288D1)),
      ),
    );
  }

  Widget _grille() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        border: Border.all(color: const Color(0xFF607D8B)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          4,
          (_) => Container(height: 1.2, color: const Color(0xFF607D8B)),
        ),
      ),
    );
  }
}

class _HingePlate extends StatelessWidget {
  const _HingePlate();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF1),
        border: Border.all(color: const Color(0xFF455A64), width: 0.8),
        borderRadius: BorderRadius.circular(1.2),
      ),
    );
  }
}

class _VisionStyleTile extends StatelessWidget {
  final BuilderVisionPanel style;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _VisionStyleTile({
    required this.style,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? AppSelectionColors.selectedGreen : const Color(0xFFB0BEC5);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected ? AppSelectionColors.selectedFill : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCFD8DC)),
                ),
                child: Center(
                  child: SizedBox(
                    width: 36,
                    height: 56,
                    child: _DoorPreview(
                        data: PreInstallationSurveyBuilderData(
                      visionPanel: style,
                      frameMode: BuilderFrameMode.doorOnly,
                    ))._leaf(
                      mirror: false,
                      hingeLeft: true,
                      leafLabel: '',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF37474F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPickerSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String initialValue;
  final String customTitle;
  final String customLabel;

  const _SearchPickerSheet({
    required this.title,
    required this.options,
    required this.initialValue,
    required this.customTitle,
    required this.customLabel,
  });

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = widget.options
        .where((entry) => q.isEmpty || entry.toLowerCase().contains(q))
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
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in filtered)
                    ListTile(
                      title: Text(option),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, option),
                    ),
                  const Divider(),
                  ListTile(
                    title: const Text('Other (custom)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final value = await _askCustomValue(context);
                      if (!context.mounted || value == null) return;
                      Navigator.pop(context, value);
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

  Future<String?> _askCustomValue(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.customTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: widget.customLabel,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(ctx, value);
            },
            child: const Text('Use'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
