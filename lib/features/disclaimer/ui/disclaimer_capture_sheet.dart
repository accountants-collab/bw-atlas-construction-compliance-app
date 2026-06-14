import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/branding_resolver.dart';
import '../../../auth/auth_state.dart';
import '../../settings/state/settings_controller.dart';
import '../data/disclaimer_providers.dart';
import '../domain/disclaimer_models.dart';

Future<DisclaimerAcceptanceRecord?> showDisclaimerCaptureSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String companyId,
  required String projectId,
  required String reportId,
  required String moduleType,
  required String projectName,
  required String projectNumber,
  required String reportReference,
}) {
  return showModalBottomSheet<DisclaimerAcceptanceRecord>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _DisclaimerCaptureSheet(
      companyId: companyId,
      projectId: projectId,
      reportId: reportId,
      moduleType: moduleType,
      projectName: projectName,
      projectNumber: projectNumber,
      reportReference: reportReference,
    ),
  );
}

class _DisclaimerCaptureSheet extends ConsumerStatefulWidget {
  const _DisclaimerCaptureSheet({
    required this.companyId,
    required this.projectId,
    required this.reportId,
    required this.moduleType,
    required this.projectName,
    required this.projectNumber,
    required this.reportReference,
  });

  final String companyId;
  final String projectId;
  final String reportId;
  final String moduleType;
  final String projectName;
  final String projectNumber;
  final String reportReference;

  @override
  ConsumerState<_DisclaimerCaptureSheet> createState() =>
      _DisclaimerCaptureSheetState();
}

class _DisclaimerCaptureSheetState
    extends ConsumerState<_DisclaimerCaptureSheet> {
  final _nameController = TextEditingController();
  final _scrollController = ScrollController();
  final _signatureRevision = ValueNotifier<int>(0);
  final List<Offset?> _signaturePoints = [];
  bool _accepted = false;
  bool _reviewed = false;
  bool _isSigning = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.text = '';
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleScroll());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _signatureRevision.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 8) {
      if (!_reviewed) {
        setState(() => _reviewed = true);
      }
    }
  }

  bool get _hasSignature => _signaturePoints.any((point) => point != null);

  bool get _canContinue {
    return _nameController.text.trim().isNotEmpty &&
        _hasSignature &&
        _accepted &&
        _reviewed &&
        !_saving;
  }

  String _friendlySaveError(Object error) {
    if (error is FirebaseException) {
      final code = error.code.trim().toLowerCase();
      if (code == 'permission-denied') {
        return 'You do not have permission to save this disclaimer record.';
      }
      if (code == 'unavailable') {
        return 'Firestore is temporarily unavailable. Please try again.';
      }
      if (code == 'failed-precondition') {
        return 'Firestore setup is incomplete for this disclaimer flow. Please contact support.';
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return 'Could not save disclaimer record. ${error.message!.trim()}';
      }
    }

    final text = error.toString();
    if (text.contains('INTERNAL ASSERTION FAILED')) {
      return 'Could not save disclaimer record. The database rejected the save request.';
    }
    return 'Could not save disclaimer record. Please try again.';
  }

  Future<Uint8List?> _signatureBytes() async {
    final points = _signaturePoints.whereType<Offset>().toList();
    if (points.isEmpty) return null;

    var minX = points.first.dx;
    var minY = points.first.dy;
    var maxX = points.first.dx;
    var maxY = points.first.dy;
    for (final point in points) {
      if (point.dx < minX) minX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy > maxY) maxY = point.dy;
    }

    const padding = 8.0;
    final width = (maxX - minX + padding * 2).clamp(64.0, 900.0);
    final height = (maxY - minY + padding * 2).clamp(42.0, 320.0);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset? previous;
    for (final point in _signaturePoints) {
      if (point == null) {
        previous = null;
        continue;
      }
      final shifted =
          Offset(point.dx - minX + padding, point.dy - minY + padding);
      if (previous != null) {
        canvas.drawLine(previous, shifted, paint);
      }
      previous = shifted;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), height.ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _submit() async {
    final auth = ref.read(authControllerProvider);
    final user = auth.currentUser;
    if (user == null) {
      setState(
          () => _error = 'You must be signed in to accept the disclaimer.');
      return;
    }
    final signatureBytes = await _signatureBytes();
    if (signatureBytes == null || signatureBytes.isEmpty) {
      setState(() => _error = 'Signature is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final settings = ref.read(settingsControllerProvider);
      final branding = resolvePdfBranding(settings);
      final repo = ref.read(disclaimerRepositoryProvider);
      final record = await repo.createAcceptance(
        companyId: widget.companyId,
        projectId: widget.projectId,
        reportId: widget.reportId,
        moduleType: widget.moduleType,
        projectName: widget.projectName,
        projectNumber: widget.projectNumber,
        reportReference: widget.reportReference,
        userId: user.id,
        userEmail: user.email,
        userRole: user.role.name,
        inspectorName: _nameController.text.trim(),
        signatureImageBytes: signatureBytes,
        companyName: branding.companyName,
        companyAddress: settings.companyProfile.address,
        companyEmail: settings.companyProfile.email,
        companyPhone: settings.companyProfile.phone,
        companyLogoBytes: branding.logoBytes,
      );
      if (!mounted) return;
      Navigator.of(context).pop(record);
    } catch (error) {
      debugPrint('[DisclaimerCaptureSheet] Save error: $error');
      setState(() {
        _saving = false;
        _error = _friendlySaveError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = disclaimerTitleForModule(widget.moduleType);
    final text = disclaimerTextForModule(widget.moduleType);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isPhone = MediaQuery.of(context).size.width < 760;
    final signatureHeight = isPhone ? 220.0 : 170.0;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.92;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
        child: Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: 760, maxHeight: maxSheetHeight),
            child: Material(
              color: Colors.white,
              elevation: 8,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  physics: _isSigning
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.gavel_outlined,
                              color: Color(0xFF1E3A5F)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(title,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your acceptance is saved as a compliance record for this module and can be reviewed later.',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 220,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: Text(text,
                              style:
                                  const TextStyle(height: 1.45, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _reviewed
                            ? 'Disclaimer reviewed.'
                            : 'Scroll to the bottom to review the full disclaimer before accepting.',
                        style: TextStyle(
                            fontSize: 12,
                            color: _reviewed
                                ? Colors.green.shade700
                                : Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Inspector / Manager full name',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Signature',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                      _signaturePoints.clear();
                                      _signatureRevision.value++;
                                    }),
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text('Clear Signature'),
                          ),
                        ],
                      ),
                      Text(
                        'Use your finger to sign',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: signatureHeight,
                        width: double.infinity,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade400),
                          color: Colors.white,
                        ),
                        child: Listener(
                          onPointerDown: (_) {
                            if (!_isSigning && mounted) {
                              setState(() => _isSigning = true);
                            }
                          },
                          onPointerUp: (_) {
                            if (_isSigning && mounted) {
                              setState(() => _isSigning = false);
                            }
                          },
                          onPointerCancel: (_) {
                            if (_isSigning && mounted) {
                              setState(() => _isSigning = false);
                            }
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            dragStartBehavior: DragStartBehavior.down,
                            onPanStart: (details) {
                              setState(() {
                                _isSigning = true;
                                _signaturePoints.add(details.localPosition);
                              });
                              _signatureRevision.value++;
                            },
                            onPanUpdate: (details) {
                              _signaturePoints.add(details.localPosition);
                              _signatureRevision.value++;
                            },
                            onPanEnd: (_) {
                              setState(() {
                                _isSigning = false;
                                _signaturePoints.add(null);
                              });
                              _signatureRevision.value++;
                            },
                            onPanCancel: () {
                              setState(() {
                                _isSigning = false;
                                _signaturePoints.add(null);
                              });
                              _signatureRevision.value++;
                            },
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _SignaturePadPainter(
                                  _signaturePoints,
                                  repaint: _signatureRevision,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: _accepted,
                        onChanged: !_reviewed || _saving
                            ? null
                            : (value) => setState(() {
                                  _accepted = value ?? false;
                                }),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(kDisclaimerAcceptanceCheckboxLabel),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12)),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          FilledButton.icon(
                            onPressed: _canContinue ? _submit : null,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                                _saving ? 'Saving...' : 'Accept & Continue'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePadPainter extends CustomPainter {
  const _SignaturePadPainter(this.points, {Listenable? repaint})
      : super(repaint: repaint);

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < points.length - 1; index++) {
      final a = points[index];
      final b = points[index + 1];
      if (a != null && b != null) {
        canvas.drawLine(a, b, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePadPainter oldDelegate) =>
      oldDelegate.points != points;
}
