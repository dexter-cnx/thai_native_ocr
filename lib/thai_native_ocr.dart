import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Result returned by native OCR.
class ThaiOcrResult {
  /// Creates an immutable OCR result.
  const ThaiOcrResult({
    required this.text,
    required this.containsThai,
    required this.detectedLanguage,
    required this.confidence,
  });

  /// Recognized text from the accurate OCR pass.
  final String text;

  /// Whether Thai was detected by the detector and/or final OCR output.
  final bool containsThai;

  /// Detected language: `th`, `en`, or `mixed`.
  final String detectedLanguage;

  /// Mean OCR confidence normalized to the range 0.0–1.0.
  final double confidence;

  /// Creates a result from the platform-channel response map.
  factory ThaiOcrResult.fromMap(Map<Object?, Object?> map) {
    return ThaiOcrResult(
      text: map['text'] as String? ?? '',
      containsThai: map['containsThai'] as bool? ?? false,
      detectedLanguage: map['detectedLanguage'] as String? ?? 'en',
      confidence:
          (map['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0,
    );
  }
}

/// Native OCR entry point.
class ThaiNativeOcr {
  ThaiNativeOcr._();

  static const MethodChannel _channel = MethodChannel('thai_native_ocr');

  /// Recognizes text from an image at [imagePath].
  ///
  /// With [autoDetectThai] enabled (default), native code performs a fast
  /// Stage 1 Thai detector before choosing one of two accurate OCR modes:
  /// Thai + English when Thai is detected, or English-only otherwise.
  ///
  /// When [autoDetectThai] is false, Stage 1 is skipped and the accurate pass
  /// uses Thai + English directly.
  ///
  /// [forceLanguage] bypasses detection and accepts only `th`, `en`, or
  /// `mixed`. `th` is retained as a compatibility alias for bilingual
  /// Thai + English recognition; there is no Thai-only execution mode.
  ///
  /// When [preprocess] is true, native code applies OCR-oriented image
  /// preprocessing before the accurate pass.
  static Future<ThaiOcrResult> recognize(
    String imagePath, {
    bool autoDetectThai = true,
    String? forceLanguage,
    bool preprocess = false,
  }) {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError.value(imagePath, 'imagePath', 'must not be empty');
    }

    return _recognize(
      imagePath: imagePath,
      autoDetectThai: autoDetectThai,
      forceLanguage: forceLanguage,
      preprocess: preprocess,
    );
  }

  /// Recognizes text from [file].
  ///
  /// This is a convenience wrapper around [recognize].
  static Future<ThaiOcrResult> recognizeFile(
    File file, {
    bool autoDetectThai = true,
    String? forceLanguage,
    bool preprocess = false,
  }) {
    return recognize(
      file.path,
      autoDetectThai: autoDetectThai,
      forceLanguage: forceLanguage,
      preprocess: preprocess,
    );
  }

  /// Recognizes text directly from encoded image [bytes].
  ///
  /// Bytes are sent directly over the platform channel. iOS constructs the
  /// Vision request from in-memory image data, so no temporary image file is
  /// required.
  static Future<ThaiOcrResult> recognizeBytes(
    Uint8List bytes, {
    bool autoDetectThai = true,
    String? forceLanguage,
    bool preprocess = false,
  }) {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }

    return _recognize(
      imageBytes: bytes,
      autoDetectThai: autoDetectThai,
      forceLanguage: forceLanguage,
      preprocess: preprocess,
    );
  }

  static Future<ThaiOcrResult> _recognize({
    String? imagePath,
    Uint8List? imageBytes,
    required bool autoDetectThai,
    required String? forceLanguage,
    required bool preprocess,
  }) async {
    _validateForceLanguage(forceLanguage);

    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'recognize',
      <String, Object?>{
        if (imagePath != null) 'imagePath': imagePath,
        if (imageBytes != null) 'imageBytes': imageBytes,
        'autoDetectThai': autoDetectThai,
        'forceLanguage': forceLanguage,
        'preprocess': preprocess,
      },
    );

    if (result == null) {
      throw PlatformException(
        code: 'NULL_RESULT',
        message: 'Native OCR returned no result.',
      );
    }

    return ThaiOcrResult.fromMap(result);
  }

  static void _validateForceLanguage(String? forceLanguage) {
    if (forceLanguage != null &&
        forceLanguage != 'th' &&
        forceLanguage != 'en' &&
        forceLanguage != 'mixed') {
      throw ArgumentError.value(
        forceLanguage,
        'forceLanguage',
        "must be one of 'th', 'en', or 'mixed'",
      );
    }
  }
}
