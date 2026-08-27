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

  /// Recognizes text from [imagePath].
  ///
  /// With [autoDetectThai] enabled (default), native code performs a fast
  /// Stage 1 Thai detector before choosing one of two accurate Stage 2 modes:
  /// Thai + English when Thai is detected, or English only otherwise.
  ///
  /// When [autoDetectThai] is false, Stage 1 is skipped and the accurate pass
  /// uses Thai + English directly.
  ///
  /// [forceLanguage] bypasses detection and accepts `th`, `en`, or `mixed`.
  /// `en` forces English-only OCR. Both `mixed` and the backward-compatible
  /// `th` alias force Thai + English OCR; there is no Thai-only execution mode.
  /// It takes precedence over [autoDetectThai].
  static Future<ThaiOcrResult> recognize(
    String imagePath, {
    bool autoDetectThai = true,
    String? forceLanguage,
  }) async {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError.value(imagePath, 'imagePath', 'must not be empty');
    }

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

    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'recognize',
      <String, Object?>{
        'imagePath': imagePath,
        'autoDetectThai': autoDetectThai,
        'forceLanguage': forceLanguage,
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
}
