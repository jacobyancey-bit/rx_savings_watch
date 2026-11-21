import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../models/drug.dart';
import 'bottle_label_parser.dart';

/// On-device prescription bottle scanner.
/// - Runs Google ML Kit OCR strictly on-device (never uploads photos).
/// - Guarantees immediate deletion of the temporary photo file in `finally`.
/// - Never returns or displays raw photo bytes or raw OCR text containing PII.
class BottleScannerService {
  final ImagePicker _picker;

  BottleScannerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  static bool get isSupported => !kIsWeb;

  Future<BottleScanParseResult?> scanBottleAndDeletePhoto(List<Drug> knownCatalog) async {
    if (!isSupported) return null;

    final XFile? picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (picked == null) return null;

    final tempFile = File(picked.path);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final inputImage = InputImage.fromFilePath(picked.path);
      final recognizedText = await recognizer.processImage(inputImage);
      return BottleLabelParser.parse(recognizedText.text, knownCatalog);
    } finally {
      // Close ML Kit recognizer
      await recognizer.close();
      // Immediately & unconditionally delete the temporary photo so no PII remains on disk
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        debugPrint('[BottleScannerService] Temp photo cleanup warning: $e');
      }
    }
  }
}
