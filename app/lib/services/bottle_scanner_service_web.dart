import 'dart:js_interop';
import '../models/drug.dart';
import 'bottle_label_parser.dart';

@JS('rxBottleOcr')
external _RxBottleOcrBridge? get _rxBottleOcr;

extension type _RxBottleOcrBridge(JSObject _) implements JSObject {
  external bool isSupported();
  external JSPromise<JSString> scanBottle();
}

/// Web on-device prescription bottle scanner.
/// - Opens the device's rear camera via `<input accept="image/*" capture="environment">`.
/// - Runs Tesseract.js WASM OCR strictly in the browser (never uploads photos).
/// - Immediately wipes the image canvas in `finally`.
/// - Extracts only the medication name / NDC via [BottleLabelParser] and discards all PII.
class BottleScannerService {
  BottleScannerService();

  static bool get isSupported {
    try {
      return _rxBottleOcr?.isSupported() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<BottleScanParseResult?> scanBottleAndDeletePhoto(List<Drug> knownCatalog) async {
    final bridge = _rxBottleOcr;
    if (bridge == null || !isSupported) return null;

    final rawJs = await bridge.scanBottle().toDart;
    final rawText = rawJs.toDart;
    if (rawText == '__CANCELED__') {
      return null;
    }
    return BottleLabelParser.parse(rawText, knownCatalog);
  }
}
