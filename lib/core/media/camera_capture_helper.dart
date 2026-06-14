import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class CameraCaptureHelper {
  CameraCaptureHelper._();

  static Future<XFile?> pickImage(
    BuildContext context, {
    int imageQuality = 85,
  }) async {
    final picker = ImagePicker();
    try {
      return await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: imageQuality,
      );
    } on PlatformException catch (error) {
      if (!context.mounted) return null;
      final code = error.code.toLowerCase();
      final denied = code.contains('denied') ||
          code.contains('permission') ||
          code.contains('access');
      final message = denied
          ? 'Camera permission is required to take photos. Allow camera access in system settings and try again.'
          : 'Could not open camera. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return null;
    } catch (_) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open camera. Please try again.')),
      );
      return null;
    }
  }
}
