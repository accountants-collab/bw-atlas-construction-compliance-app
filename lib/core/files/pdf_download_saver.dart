import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SavedPdfFile {
  final String fileName;
  final String filePath;

  const SavedPdfFile({
    required this.fileName,
    required this.filePath,
  });
}

class PdfDownloadSaver {
  static Future<SavedPdfFile> savePdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Mobile PDF save is not supported on web.');
    }

    final safeFileName = _sanitizeFileName(fileName);

    // On Android/iOS prefer a user-visible save flow.
    final pickedPath = await _trySaveViaSystemPicker(
      bytes: bytes,
      fileName: safeFileName,
    );
    if (pickedPath != null && pickedPath.isNotEmpty) {
      return SavedPdfFile(fileName: safeFileName, filePath: pickedPath);
    }

    final targetDir = await _resolveSaveDirectory();
    final fullPath = '${targetDir.path}${Platform.pathSeparator}$safeFileName';
    final outFile = File(fullPath);
    await outFile.create(recursive: true);
    await outFile.writeAsBytes(bytes, flush: true);

    return SavedPdfFile(fileName: safeFileName, filePath: fullPath);
  }

  static Future<String?> _trySaveViaSystemPicker({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return null;
    }

    try {
      final selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (selectedPath == null || selectedPath.trim().isEmpty) {
        return null;
      }

      final normalizedPath = _normalizeSelectedPath(selectedPath);
      final file = File(normalizedPath);
      if (!await file.exists()) {
        await file.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
      return normalizedPath;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _resolveSaveDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return downloads;
      }
    } catch (_) {
      // Fall back to app documents when downloads folder is unavailable.
    }
    return getApplicationDocumentsDirectory();
  }

  static String _sanitizeFileName(String value) {
    var out = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    if (!out.toLowerCase().endsWith('.pdf')) {
      out = '$out.pdf';
    }
    if (out.isEmpty) {
      return 'report.pdf';
    }
    return out;
  }

  static String _normalizeSelectedPath(String selectedPath) {
    final trimmed = selectedPath.trim();
    if (trimmed.startsWith('file://')) {
      return Uri.parse(trimmed).toFilePath();
    }
    return trimmed;
  }
}
