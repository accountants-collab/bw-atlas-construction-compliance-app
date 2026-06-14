import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../auth/auth_state.dart';
import '../domain/models.dart';
import '../state/survey_controller.dart';

final Map<String, Uint8List> _drawingPreviewCache = <String, Uint8List>{};
const int _drawingPreviewCacheMaxEntries = 72;

Uint8List _drawingBytesView(List<int> bytes) {
  if (bytes is Uint8List) return bytes;
  return Uint8List.fromList(bytes);
}

void _storeDrawingPreview(String key, Uint8List bytes) {
  _drawingPreviewCache[key] = bytes;
  if (_drawingPreviewCache.length <= _drawingPreviewCacheMaxEntries) {
    return;
  }
  _drawingPreviewCache.remove(_drawingPreviewCache.keys.first);
}

class DrawingPinSelectionResult {
  final ProjectDrawing drawing;
  final FloorPlanPin pin;
  final bool addDefect;

  const DrawingPinSelectionResult({
    required this.drawing,
    required this.pin,
    this.addDefect = false,
  });
}

class DrawingViewerSelectionConfig {
  final bool enablePinPlacement;
  final bool allowExistingPinSelection;
  final bool autoAssignPinNumbers;
  final String? highlightedPinId;
  final bool hideOtherPins;

  const DrawingViewerSelectionConfig({
    this.enablePinPlacement = false,
    this.allowExistingPinSelection = false,
    this.autoAssignPinNumbers = false,
    this.highlightedPinId,
    this.hideOtherPins = false,
  });
}

class ProjectDrawingAccess {
  static bool hasDrawings(Survey survey) => survey.projectDrawings.isNotEmpty;

  static Future<DrawingPinSelectionResult?> showDrawingPicker({
    required BuildContext context,
    required Survey survey,
    String title = 'Project Drawings / Plans (DRW)',
    String? preferredLevel,
    Future<ProjectDrawing?> Function(ProjectDrawing drawing)? beforeOpen,
    DrawingViewerSelectionConfig? selectionConfig,
  }) async {
    if (survey.projectDrawings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No drawings uploaded yet for this project.')),
      );
      return null;
    }

    final preferred = _normalizeLevel(preferredLevel ?? '');
    final suggested = preferred.isEmpty
        ? <ProjectDrawing>[]
        : survey.projectDrawings
            .where((d) => _isLevelMatch(d.level, preferred))
            .toList();
    final suggestedIds = suggested.map((d) => d.id).toSet();

    final groups = {
      'Ground Floor': <ProjectDrawing>[],
      'Level 1': <ProjectDrawing>[],
      'Level 2': <ProjectDrawing>[],
      'Basement': <ProjectDrawing>[],
      'Other': <ProjectDrawing>[],
    };
    for (final drawing in survey.projectDrawings) {
      if (suggestedIds.contains(drawing.id)) continue;
      groups[_bucketForLevel(drawing.level)]!.add(drawing);
    }

    final selected = await showModalBottomSheet<ProjectDrawing>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(title),
              subtitle: Text(
                preferred.isEmpty
                    ? 'BW Atlas - quick orientation access'
                    : 'BW Atlas - suggested for: ${_displayLevel(preferredLevel ?? '')}',
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (suggested.isNotEmpty) ...[
                    _sectionLabel('Suggested Drawing'),
                    for (final d in suggested)
                      _drawingTile(ctx, d, suggested: true),
                  ],
                  for (final entry in groups.entries)
                    if (entry.value.isNotEmpty) ...[
                      _sectionLabel(entry.key),
                      for (final d in entry.value) _drawingTile(ctx, d),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!context.mounted || selected == null) return null;
    final resolved = beforeOpen == null ? selected : await beforeOpen(selected);
    if (!context.mounted || resolved == null) return null;

    return showDrawingViewer(
      context: context,
      surveyId: survey.id,
      drawingId: resolved.id,
      fallbackTitle: resolved.fileName,
      drawingOverride: resolved,
      workspaceOverride: survey.workspace,
      selectionConfig: selectionConfig,
    );
  }

  static Future<DrawingPinSelectionResult?> showDrawingViewer({
    required BuildContext context,
    required String surveyId,
    required String drawingId,
    String fallbackTitle = 'Drawing',
    ProjectDrawing? drawingOverride,
    InspectionWorkspace? workspaceOverride,
    DrawingViewerSelectionConfig? selectionConfig,
  }) async {
    return showDialog<DrawingPinSelectionResult>(
      context: context,
      useSafeArea: true,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: _DrawingViewerDialog(
          surveyId: surveyId,
          drawingId: drawingId,
          fallbackTitle: fallbackTitle,
          drawingOverride: drawingOverride,
          workspaceOverride: workspaceOverride,
          selectionConfig: selectionConfig,
        ),
      ),
    );
  }

  static Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label,
        style:
            const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
      ),
    );
  }

  static Widget _drawingTile(BuildContext context, ProjectDrawing drawing,
      {bool suggested = false}) {
    final uploadDate = _fmtDate(drawing.createdAt);
    final level = drawing.level.trim().isEmpty ? 'Other' : drawing.level.trim();
    final description = drawing.description.trim();

    return ListTile(
      leading: Icon(_isPdf(drawing)
          ? Icons.picture_as_pdf_outlined
          : Icons.image_outlined),
      title:
          Text(drawing.name.trim().isEmpty ? drawing.fileName : drawing.name),
      subtitle: Text(
        [
          'Level: $level',
          if (description.isNotEmpty) description,
          'Uploaded: $uploadDate',
        ].join(' | '),
      ),
      trailing: suggested ? const Icon(Icons.auto_awesome, size: 18) : null,
      onTap: () => Navigator.pop(context, drawing),
    );
  }

  static bool _isPdf(ProjectDrawing drawing) {
    final mime = drawing.mimeType.toLowerCase();
    final name = drawing.fileName.toLowerCase();
    return mime.contains('pdf') || name.endsWith('.pdf');
  }

  static String _bucketForLevel(String raw) {
    final n = _normalizeLevel(raw);
    if (n.contains('ground')) return 'Ground Floor';
    if (n.contains('level 1') || n == 'l1' || n == '1' || n.contains('first')) {
      return 'Level 1';
    }
    if (n.contains('level 2') ||
        n == 'l2' ||
        n == '2' ||
        n.contains('second')) {
      return 'Level 2';
    }
    if (n.contains('basement') ||
        n == 'b' ||
        n == 'b1' ||
        n.contains('lower ground')) {
      return 'Basement';
    }
    return 'Other';
  }

  static bool _isLevelMatch(String drawingLevel, String preferred) {
    if (preferred.isEmpty) return false;
    final d = _normalizeLevel(drawingLevel);
    if (d.isEmpty) return false;
    return d == preferred ||
        d.contains(preferred) ||
        preferred.contains(d) ||
        _bucketForLevel(d) == _bucketForLevel(preferred);
  }

  static String _normalizeLevel(String raw) {
    return raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _displayLevel(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return 'Unknown';
    return n
        .replaceAll('_', ' ')
        .split(' ')
        .where((e) => e.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  static String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _DrawingViewerDialog extends ConsumerWidget {
  final String surveyId;
  final String drawingId;
  final String fallbackTitle;
  final ProjectDrawing? drawingOverride;
  final InspectionWorkspace? workspaceOverride;
  final DrawingViewerSelectionConfig? selectionConfig;

  const _DrawingViewerDialog({
    required this.surveyId,
    required this.drawingId,
    required this.fallbackTitle,
    this.drawingOverride,
    this.workspaceOverride,
    this.selectionConfig,
  });

  Survey? _watchSurveyForWorkspace(
      WidgetRef ref, InspectionWorkspace workspace) {
    return ref.watch(
      surveyControllerFamilyProvider(workspace).select((state) {
        for (final survey in state.surveys) {
          if (survey.id == surveyId) {
            return survey;
          }
        }
        return null;
      }),
    );
  }

  ({Survey survey, InspectionWorkspace workspace})? _resolveSurveyAndWorkspace(
      WidgetRef ref) {
    if (workspaceOverride != null) {
      final survey = _watchSurveyForWorkspace(ref, workspaceOverride!);
      if (survey != null) {
        return (survey: survey, workspace: workspaceOverride!);
      }
    }

    for (final ws in InspectionWorkspace.values) {
      final survey = _watchSurveyForWorkspace(ref, ws);
      if (survey != null) {
        return (survey: survey, workspace: ws);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = _resolveSurveyAndWorkspace(ref);
    final survey = resolved?.survey;
    final workspace = resolved?.workspace ?? InspectionWorkspace.fireDoor;
    final matches =
        survey?.projectDrawings.where((d) => d.id == drawingId).toList() ??
            const <ProjectDrawing>[];
    final drawing = drawingOverride ?? (matches.isEmpty ? null : matches.first);
    final isFireStopping = survey?.type == SurveyType.fireStopping;

    if (drawing == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(fallbackTitle),
        ),
        body: const Center(child: Text('Drawing no longer exists.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(drawing.fileName),
      ),
      body: ProjectDrawingAccess._isPdf(drawing)
          ? _PinnedPdfDrawingCanvas(
              surveyId: surveyId,
              drawing: drawing,
              workspace: workspace,
              isFireStopping: isFireStopping,
              selectionConfig: selectionConfig,
            )
          : _PinnedDrawingCanvas(
              surveyId: surveyId,
              drawing: drawing,
              workspace: workspace,
              isFireStopping: isFireStopping,
              selectionConfig: selectionConfig,
            ),
    );
  }
}

class _PinnedPdfDrawingCanvas extends ConsumerStatefulWidget {
  final String surveyId;
  final ProjectDrawing drawing;
  final InspectionWorkspace workspace;
  final bool isFireStopping;
  final DrawingViewerSelectionConfig? selectionConfig;

  const _PinnedPdfDrawingCanvas({
    required this.surveyId,
    required this.drawing,
    required this.workspace,
    this.isFireStopping = false,
    this.selectionConfig,
  });

  @override
  ConsumerState<_PinnedPdfDrawingCanvas> createState() =>
      _PinnedPdfDrawingCanvasState();
}

class _PinnedPdfDrawingCanvasState
    extends ConsumerState<_PinnedPdfDrawingCanvas> {
  final Map<int, Uint8List> _pageImageCache = {};
  final GlobalKey _canvasStackKey = GlobalKey();
  int _currentPage = 1;
  bool _loading = false;

  int get _renderDpi {
    if (kIsWeb) return 190;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 130;
      default:
        return 220;
    }
  }

  String _previewKey(int page) =>
      '${widget.workspace.name}|${widget.surveyId}|${widget.drawing.id}|$page|$_renderDpi';

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  void _persistPinDrop({
    required FloorPlanPin pin,
    required DraggableDetails details,
    required Size canvasSize,
  }) {
    final box =
        _canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(details.offset);
    final x = (local.dx / canvasSize.width).clamp(0.0, 1.0);
    final y = (local.dy / canvasSize.height).clamp(0.0, 1.0);

    ref
        .read(surveyControllerFamilyProvider(widget.workspace).notifier)
        .updateFloorPlanPin(
          surveyId: widget.surveyId,
          drawingId: widget.drawing.id,
          pinId: pin.id,
          x: x,
          y: y,
          page: _currentPage,
        );
  }

  Future<void> _loadPage(int page) async {
    if (_loading) return;
    if (_pageImageCache.containsKey(page)) {
      setState(() => _currentPage = page);
      return;
    }

    final cached = _drawingPreviewCache[_previewKey(page)];
    if (cached != null) {
      setState(() {
        _pageImageCache[page] = cached;
        _currentPage = page;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      Uint8List? png;
      await for (final raster in Printing.raster(
        _drawingBytesView(widget.drawing.bytes),
        pages: [page - 1],
        dpi: _renderDpi.toDouble(),
      )) {
        png = await raster.toPng();
      }

      if (png == null || png.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Page not available.')),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _pageImageCache[page] = png!;
        _currentPage = page;
      });
      _storeDrawingPreview(_previewKey(page), png);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not render this PDF page.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAddPinDialog({
    required Offset localPosition,
    required Size canvasSize,
    required List<FloorPlanPin> existingPins,
  }) async {
    final isSelectionMode = widget.selectionConfig?.enablePinPlacement ?? false;
    final doorRefCtrl = TextEditingController();
    final markerTitle =
        widget.isFireStopping ? 'Add Markup Point' : 'Add Drawing Pin';
    final markerLabel =
        widget.isFireStopping ? 'Location Marker Label' : 'Door Ref';
    final markerHint =
        widget.isFireStopping ? 'e.g. Riser GF - Item 01' : 'e.g. D-12';
    final saveLabel = widget.isFireStopping ? 'Save Marker' : 'Save Pin';
    String doorRef = '';
    if (isSelectionMode &&
        (widget.selectionConfig?.autoAssignPinNumbers ?? false)) {
      doorRef = _nextAutoPinLabel(existingPins);
    } else {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(markerTitle),
          content: TextField(
            controller: doorRefCtrl,
            decoration: InputDecoration(
              labelText: markerLabel,
              hintText: markerHint,
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(saveLabel)),
          ],
        ),
      );

      if (saved != true) return;
      doorRef = doorRefCtrl.text.trim();
      if (doorRef.isEmpty) return;
    }

    final x = (localPosition.dx / canvasSize.width).clamp(0.0, 1.0);
    final y = (localPosition.dy / canvasSize.height).clamp(0.0, 1.0);
    final pin = FloorPlanPin(
      drawingId: widget.drawing.id,
      page: _currentPage,
      x: x,
      y: y,
      doorNumber: doorRef,
      label: doorRef,
    );
    ref
        .read(surveyControllerFamilyProvider(widget.workspace).notifier)
        .addFloorPlanPin(
          surveyId: widget.surveyId,
          drawingId: widget.drawing.id,
          pin: pin,
        );
    if (!mounted) return;
    if (!isSelectionMode && !widget.isFireStopping) return;
    final addDefect = await _askAddDefectForPin(
      isSelectionMode
          ? doorRef
          : '$doorRef is ready. Go to Report and start inspection?',
      title: isSelectionMode ? 'Add defect for this pin?' : 'Open Report now?',
      confirmLabel: isSelectionMode ? 'Yes' : 'Go to Report',
      cancelLabel: 'Cancel',
    );
    if (!mounted) return;
    if (addDefect) {
      Navigator.pop(
        context,
        DrawingPinSelectionResult(
          drawing: widget.drawing,
          pin: pin,
          addDefect: true,
        ),
      );
    }
  }

  Future<void> _showPinActions(FloorPlanPin pin, bool canManagePins) async {
    final allowExistingPinSelection =
        widget.selectionConfig?.allowExistingPinSelection ?? false;
    if (allowExistingPinSelection) {
      Navigator.pop(
        context,
        DrawingPinSelectionResult(
          drawing: widget.drawing,
          pin: pin,
          addDefect: false,
        ),
      );
      return;
    }
    final markerLabel =
        widget.isFireStopping ? 'Location marker' : 'Door Ref pin';
    final editMarkerLabel =
        widget.isFireStopping ? 'Edit marker label' : 'Edit Door Ref';
    final inputLabel =
        widget.isFireStopping ? 'Location Marker Label' : 'Door Ref';
    final deleteLabel = widget.isFireStopping ? 'Delete marker' : 'Delete pin';
    if (!canManagePins) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(pin.doorNumber),
                subtitle: Text('$markerLabel • Page ${pin.page} (read-only)'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      return;
    }

    final doorRefCtrl = TextEditingController(text: pin.doorNumber);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(pin.doorNumber),
              subtitle: Text('$markerLabel • Page ${pin.page}'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(editMarkerLabel),
              onTap: () async {
                final saved = await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Edit Pin'),
                    content: TextField(
                      controller: doorRefCtrl,
                      decoration: InputDecoration(
                        labelText: inputLabel,
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                final nextRef = doorRefCtrl.text.trim();
                if (saved == true && nextRef.isNotEmpty) {
                  ref
                      .read(surveyControllerFamilyProvider(widget.workspace)
                          .notifier)
                      .updateFloorPlanPin(
                        surveyId: widget.surveyId,
                        drawingId: widget.drawing.id,
                        pinId: pin.id,
                        doorRef: nextRef,
                      );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  Text(deleteLabel, style: const TextStyle(color: Colors.red)),
              onTap: () {
                ref
                    .read(surveyControllerFamilyProvider(widget.workspace)
                        .notifier)
                    .removeFloorPlanPin(
                      surveyId: widget.surveyId,
                      drawingId: widget.drawing.id,
                      pinId: pin.id,
                    );
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    doorRefCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userRole =
        ref.watch(authControllerProvider.select((auth) => auth.userRole));
    final isSelectionMode = widget.selectionConfig?.enablePinPlacement ?? false;
    final canManagePins = userRole == UserRole.manager ||
        isSelectionMode ||
        widget.isFireStopping;
    ref.watch(surveyDrawingPinsRevisionProvider(widget.workspace));
    final surveyController =
        ref.read(surveyControllerFamilyProvider(widget.workspace).notifier);
    final currentDrawing = ref.watch(
      surveyControllerFamilyProvider(widget.workspace).select((state) {
        Survey? survey;
        for (final item in state.surveys) {
          if (item.id == widget.surveyId) {
            survey = item;
            break;
          }
        }
        if (survey == null) return widget.drawing;
        for (final drawing in survey.projectDrawings) {
          if (drawing.id == widget.drawing.id) {
            return drawing;
          }
        }
        return widget.drawing;
      }),
    );
    final allDrawingPins = surveyController.getDrawingPins(
      surveyId: widget.surveyId,
      drawingId: widget.drawing.id,
      fallback: currentDrawing.pins,
    );

    final currentPageImage = _pageImageCache[_currentPage];
    var pagePins = allDrawingPins.where((p) => p.page == _currentPage).toList();
    final highlightedPinId = widget.selectionConfig?.highlightedPinId ?? '';
    if ((widget.selectionConfig?.hideOtherPins ?? false) &&
        highlightedPinId.isNotEmpty) {
      pagePins = pagePins.where((p) => p.id == highlightedPinId).toList();
    }

    return Container(
      color: const Color(0xFF111111),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.black.withValues(alpha: 0.35),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _currentPage > 1
                      ? () => _loadPage(_currentPage - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Prev'),
                ),
                const SizedBox(width: 8),
                Text('Page $_currentPage',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _loadPage(_currentPage + 1),
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                ),
                const Spacer(),
                if (canManagePins)
                  Text(
                    isSelectionMode
                        ? 'Tap drawing to place pin'
                        : (widget.isFireStopping
                            ? 'Long press to add marker. Long press and drag a pin to reposition.'
                            : 'Long press to add pin. Long press and drag a pin to reposition.'),
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading && currentPageImage == null
                ? const Center(child: CircularProgressIndicator())
                : (currentPageImage == null
                    ? const Center(
                        child: Text(
                          'Could not render PDF page.',
                          style: TextStyle(color: Colors.white),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final canvasSize =
                              Size(constraints.maxWidth, constraints.maxHeight);
                          return Center(
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 5,
                              child: SizedBox(
                                width: canvasSize.width,
                                height: canvasSize.height,
                                child: GestureDetector(
                                  onTapUp: isSelectionMode
                                      ? (details) => _showAddPinDialog(
                                            localPosition:
                                                details.localPosition,
                                            canvasSize: canvasSize,
                                            existingPins: allDrawingPins,
                                          )
                                      : null,
                                  onLongPressStart: canManagePins
                                      ? (isSelectionMode
                                          ? null
                                          : (details) => _showAddPinDialog(
                                                localPosition:
                                                    details.localPosition,
                                                canvasSize: canvasSize,
                                                existingPins: allDrawingPins,
                                              ))
                                      : null,
                                  child: Stack(
                                    key: _canvasStackKey,
                                    children: [
                                      Positioned.fill(
                                        child: RepaintBoundary(
                                          child: IgnorePointer(
                                            child: Image.memory(
                                              currentPageImage,
                                              fit: BoxFit.contain,
                                              filterQuality:
                                                  FilterQuality.medium,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: RepaintBoundary(
                                          child: Stack(
                                            children: [
                                              for (final pin in pagePins)
                                                Positioned(
                                                  left: (pin.x *
                                                          canvasSize.width) -
                                                      10,
                                                  top: (pin.y *
                                                          canvasSize.height) -
                                                      24,
                                                  child: LongPressDraggable<
                                                      FloorPlanPin>(
                                                    data: pin,
                                                    feedback: Material(
                                                      color: Colors.transparent,
                                                      child: _PinMarker(
                                                        label: pin.doorNumber,
                                                        highlighted: pin.id ==
                                                            highlightedPinId,
                                                      ),
                                                    ),
                                                    dragAnchorStrategy:
                                                        pointerDragAnchorStrategy,
                                                    onDragEnd: canManagePins
                                                        ? (details) =>
                                                            _persistPinDrop(
                                                              pin: pin,
                                                              details: details,
                                                              canvasSize:
                                                                  canvasSize,
                                                            )
                                                        : null,
                                                    child: InkWell(
                                                      onTap: () =>
                                                          _showPinActions(pin,
                                                              canManagePins),
                                                      child: _PinMarker(
                                                        label: pin.doorNumber,
                                                        highlighted: pin.id ==
                                                            highlightedPinId,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }

  Future<bool> _askAddDefectForPin(
    String message, {
    required String title,
    required String confirmLabel,
    required String cancelLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message.startsWith('Pin ') ? message : 'Pin $message'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancelLabel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
    return result ?? false;
  }

  String _nextAutoPinLabel(List<FloorPlanPin> pins) {
    var next = 1;
    for (final pin in pins) {
      final match = RegExp(r'(\d+)')
          .firstMatch(pin.label.isNotEmpty ? pin.label : pin.doorNumber);
      final parsed = int.tryParse(match?.group(1) ?? '');
      if (parsed != null && parsed >= next) next = parsed + 1;
    }
    return 'Pin $next';
  }
}

class _PinnedDrawingCanvas extends ConsumerWidget {
  final String surveyId;
  final ProjectDrawing drawing;
  final InspectionWorkspace workspace;
  final bool isFireStopping;
  final DrawingViewerSelectionConfig? selectionConfig;

  const _PinnedDrawingCanvas({
    required this.surveyId,
    required this.drawing,
    required this.workspace,
    this.isFireStopping = false,
    this.selectionConfig,
  });

  void _persistPinDrop({
    required BuildContext context,
    required WidgetRef ref,
    required FloorPlanPin pin,
    required DraggableDetails details,
    required Size canvasSize,
  }) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(details.offset);
    final x = (local.dx / canvasSize.width).clamp(0.0, 1.0);
    final y = (local.dy / canvasSize.height).clamp(0.0, 1.0);

    ref
        .read(surveyControllerFamilyProvider(workspace).notifier)
        .updateFloorPlanPin(
          surveyId: surveyId,
          drawingId: drawing.id,
          pinId: pin.id,
          x: x,
          y: y,
          page: pin.page,
        );
  }

  Future<void> _showAddPinDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Offset localPosition,
    required Size canvasSize,
    required List<FloorPlanPin> existingPins,
  }) async {
    final isSelectionMode = selectionConfig?.enablePinPlacement ?? false;
    final doorRefCtrl = TextEditingController();
    final markerTitle = isFireStopping ? 'Add Markup Point' : 'Add Drawing Pin';
    final markerLabel = isFireStopping ? 'Location Marker Label' : 'Door Ref';
    final markerHint = isFireStopping ? 'e.g. Riser GF - Item 01' : 'e.g. D-12';
    final saveLabel = isFireStopping ? 'Save Marker' : 'Save Pin';
    String doorRef = '';
    if (isSelectionMode && (selectionConfig?.autoAssignPinNumbers ?? false)) {
      doorRef = _nextAutoPinLabel(existingPins);
    } else {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(markerTitle),
          content: TextField(
            controller: doorRefCtrl,
            decoration: InputDecoration(
              labelText: markerLabel,
              hintText: markerHint,
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(saveLabel)),
          ],
        ),
      );

      if (saved != true) return;
      doorRef = doorRefCtrl.text.trim();
      if (doorRef.isEmpty) return;
    }

    final x = (localPosition.dx / canvasSize.width).clamp(0.0, 1.0);
    final y = (localPosition.dy / canvasSize.height).clamp(0.0, 1.0);
    final pin = FloorPlanPin(
      drawingId: drawing.id,
      x: x,
      y: y,
      doorNumber: doorRef,
      label: doorRef,
    );
    ref
        .read(surveyControllerFamilyProvider(workspace).notifier)
        .addFloorPlanPin(
          surveyId: surveyId,
          drawingId: drawing.id,
          pin: pin,
        );
    if (!context.mounted) return;
    if (!isSelectionMode && !isFireStopping) return;
    final addDefect = await _askAddDefectForPin(
      context,
      isSelectionMode
          ? doorRef
          : '$doorRef is ready. Go to Report and start inspection?',
      title: isSelectionMode ? 'Add defect for this pin?' : 'Open Report now?',
      confirmLabel: isSelectionMode ? 'Yes' : 'Go to Report',
      cancelLabel: 'Cancel',
    );
    if (!context.mounted) return;
    if (addDefect) {
      Navigator.pop(
        context,
        DrawingPinSelectionResult(drawing: drawing, pin: pin, addDefect: true),
      );
    }
  }

  Future<void> _showPinActions(
    BuildContext context,
    WidgetRef ref,
    FloorPlanPin pin,
    bool canManagePins,
  ) async {
    if (selectionConfig?.allowExistingPinSelection ?? false) {
      Navigator.pop(
        context,
        DrawingPinSelectionResult(drawing: drawing, pin: pin, addDefect: false),
      );
      return;
    }
    final markerLabel = isFireStopping ? 'Location marker' : 'Door Ref pin';
    final editMarkerLabel =
        isFireStopping ? 'Edit marker label' : 'Edit Door Ref';
    final inputLabel = isFireStopping ? 'Location Marker Label' : 'Door Ref';
    final deleteLabel = isFireStopping ? 'Delete marker' : 'Delete pin';
    if (!canManagePins) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(pin.doorNumber),
                subtitle: Text('$markerLabel (read-only)'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      return;
    }

    final doorRefCtrl = TextEditingController(text: pin.doorNumber);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(pin.doorNumber),
              subtitle: Text(markerLabel),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(editMarkerLabel),
              onTap: () async {
                final saved = await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Edit Pin'),
                    content: TextField(
                      controller: doorRefCtrl,
                      decoration: InputDecoration(
                        labelText: inputLabel,
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                final nextRef = doorRefCtrl.text.trim();
                if (saved == true && nextRef.isNotEmpty) {
                  ref
                      .read(surveyControllerFamilyProvider(workspace).notifier)
                      .updateFloorPlanPin(
                        surveyId: surveyId,
                        drawingId: drawing.id,
                        pinId: pin.id,
                        doorRef: nextRef,
                      );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  Text(deleteLabel, style: const TextStyle(color: Colors.red)),
              onTap: () {
                ref
                    .read(surveyControllerFamilyProvider(workspace).notifier)
                    .removeFloorPlanPin(
                      surveyId: surveyId,
                      drawingId: drawing.id,
                      pinId: pin.id,
                    );
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    doorRefCtrl.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userRole =
        ref.watch(authControllerProvider.select((auth) => auth.userRole));
    final isSelectionMode = selectionConfig?.enablePinPlacement ?? false;
    final canManagePins =
        userRole == UserRole.manager || isSelectionMode || isFireStopping;
    ref.watch(surveyDrawingPinsRevisionProvider(workspace));
    final surveyController =
        ref.read(surveyControllerFamilyProvider(workspace).notifier);
    final currentDrawing = ref.watch(
      surveyControllerFamilyProvider(workspace).select((state) {
        Survey? survey;
        for (final item in state.surveys) {
          if (item.id == surveyId) {
            survey = item;
            break;
          }
        }
        if (survey == null) return drawing;
        for (final item in survey.projectDrawings) {
          if (item.id == drawing.id) {
            return item;
          }
        }
        return drawing;
      }),
    );
    final allDrawingPins = surveyController.getDrawingPins(
      surveyId: surveyId,
      drawingId: drawing.id,
      fallback: currentDrawing.pins,
    );
    final highlightedPinId = selectionConfig?.highlightedPinId ?? '';
    final visiblePins = ((selectionConfig?.hideOtherPins ?? false) &&
            highlightedPinId.isNotEmpty)
        ? allDrawingPins.where((p) => p.id == highlightedPinId).toList()
        : allDrawingPins;

    return Container(
      color: const Color(0xFF111111),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: SizedBox(
                width: canvasSize.width,
                height: canvasSize.height,
                child: GestureDetector(
                  onTapUp: isSelectionMode
                      ? (details) => _showAddPinDialog(
                            context: context,
                            ref: ref,
                            localPosition: details.localPosition,
                            canvasSize: canvasSize,
                            existingPins: allDrawingPins,
                          )
                      : null,
                  onLongPressStart: canManagePins
                      ? (isSelectionMode
                          ? null
                          : (details) => _showAddPinDialog(
                                context: context,
                                ref: ref,
                                localPosition: details.localPosition,
                                canvasSize: canvasSize,
                                existingPins: allDrawingPins,
                              ))
                      : null,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: IgnorePointer(
                            child: Image.memory(
                              _drawingBytesView(currentDrawing.bytes),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.low,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: Stack(
                            children: [
                              for (final pin in visiblePins)
                                Positioned(
                                  left: (pin.x * canvasSize.width) - 10,
                                  top: (pin.y * canvasSize.height) - 24,
                                  child: LongPressDraggable<FloorPlanPin>(
                                    data: pin,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: _PinMarker(
                                        label: pin.doorNumber,
                                        highlighted: pin.id == highlightedPinId,
                                      ),
                                    ),
                                    dragAnchorStrategy:
                                        pointerDragAnchorStrategy,
                                    onDragEnd: canManagePins
                                        ? (details) => _persistPinDrop(
                                              context: context,
                                              ref: ref,
                                              pin: pin,
                                              details: details,
                                              canvasSize: canvasSize,
                                            )
                                        : null,
                                    child: InkWell(
                                      onTap: () => _showPinActions(
                                          context, ref, pin, canManagePins),
                                      child: _PinMarker(
                                        label: pin.doorNumber,
                                        highlighted: pin.id == highlightedPinId,
                                      ),
                                    ),
                                  ),
                                ),
                              if (canManagePins)
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Color(0xCC000000),
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(8)),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      child: Text(
                                        isSelectionMode
                                            ? 'Tap drawing to place pin'
                                            : (isFireStopping
                                                ? 'Long press to add markup point'
                                                : 'Long press to add pin'),
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _askAddDefectForPin(
    BuildContext context,
    String message, {
    required String title,
    required String confirmLabel,
    required String cancelLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message.startsWith('Pin ') ? message : 'Pin $message'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancelLabel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
    return result ?? false;
  }

  String _nextAutoPinLabel(List<FloorPlanPin> pins) {
    var next = 1;
    for (final pin in pins) {
      final match = RegExp(r'(\d+)')
          .firstMatch(pin.label.isNotEmpty ? pin.label : pin.doorNumber);
      final parsed = int.tryParse(match?.group(1) ?? '');
      if (parsed != null && parsed >= next) next = parsed + 1;
    }
    return 'Pin $next';
  }
}

class _PinMarker extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _PinMarker({
    required this.label,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color:
                highlighted ? const Color(0xFFC62828) : const Color(0xFF1565C0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ),
        Icon(
          Icons.location_on,
          color: highlighted ? const Color(0xFFC62828) : Colors.red,
          size: 22,
        ),
      ],
    );
  }
}
