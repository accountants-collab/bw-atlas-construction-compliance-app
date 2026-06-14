class DrawingPinReference {
  final String drawingId;
  final String pinId;

  const DrawingPinReference({
    required this.drawingId,
    required this.pinId,
  });

  bool get hasDrawing => drawingId.trim().isNotEmpty;
  bool get hasPin => pinId.trim().isNotEmpty;
  bool get isLinked => hasDrawing && hasPin;

  String toMetadata() {
    final drawing = drawingId.trim();
    final pin = pinId.trim();
    if (drawing.isEmpty && pin.isEmpty) return '';
    return 'drawing=$drawing;pin=$pin';
  }

  static DrawingPinReference? fromMetadata(String raw) {
    final value = raw.trim();
    if (value.isEmpty || !value.contains('=')) return null;

    var drawing = '';
    var pin = '';
    for (final part in value.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final key = part.substring(0, eq).trim().toLowerCase();
      final data = part.substring(eq + 1).trim();
      if (key == 'drawing') drawing = data;
      if (key == 'pin') pin = data;
    }
    if (drawing.isEmpty && pin.isEmpty) return null;
    return DrawingPinReference(drawingId: drawing, pinId: pin);
  }
}