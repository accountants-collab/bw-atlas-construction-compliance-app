import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Show a full-screen swipe + pinch-zoom photo viewer.
///
/// [photos] – raw bytes for each image.
/// [initialIndex] – which image to open first (default 0).
Future<void> showPhotoViewer({
  required BuildContext context,
  required List<List<int>> photos,
  int initialIndex = 0,
}) {
  assert(photos.isNotEmpty, 'photos must not be empty');
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    barrierColor: Colors.black,
    builder: (ctx) => _PhotoViewer(
      photos: photos,
      initialIndex: initialIndex.clamp(0, photos.length - 1),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  final List<List<int>> photos;
  final int initialIndex;
  const _PhotoViewer({required this.photos, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          // Swipeable pages
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: Center(
                  child: Image.memory(
                    Uint8List.fromList(widget.photos[i]),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              );
            },
          ),

          // Close button (top-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),

          // Counter (bottom-centre) – only visible when multiple photos
          if (widget.photos.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_current + 1} / ${widget.photos.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
