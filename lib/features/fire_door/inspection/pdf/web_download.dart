import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void downloadBytesWeb({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) {
  // Create Blob from bytes
  final blobParts = <JSAny>[bytes.toJS];
  final blob = web.Blob(
    blobParts.toJS,
    web.BlobPropertyBag(type: mimeType),
  );

  // Create object URL
  final url = web.URL.createObjectURL(blob);

  // Create an <a> element and click it
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  // Cleanup
  web.URL.revokeObjectURL(url);
}

void downloadUrlWeb({
  required String url,
  String? fileName,
}) {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..style.display = 'none';

  if (fileName != null && fileName.trim().isNotEmpty) {
    anchor.download = fileName.trim();
  }

  // Use a new tab/window for best cross-origin compatibility on Firebase Storage links.
  anchor.target = '_blank';
  anchor.rel = 'noopener noreferrer';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}