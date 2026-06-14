import 'dart:typed_data';

void downloadBytesWeb({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError('downloadBytesWeb is only available on web builds.');
}
