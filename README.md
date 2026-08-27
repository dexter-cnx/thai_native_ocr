# thai_native_ocr

Native OCR for Flutter with a hybrid platform implementation:

- **iOS:** Apple Vision only. No Tesseract dependency and no `tessdata` bundle.
- **Android:** Tesseract via `tess-two`, with Thai + English `tessdata_best` models.
- **Two-stage Thai auto-detection:** run a lightweight detector first, then select the accurate OCR language set.

## Why this fixes the iOS Tesseract file-not-found bug

A common Flutter/Tesseract failure on iOS is caused by resource lookup differences. Flutter assets are packaged under `App.framework/flutter_assets`, while native Tesseract integrations commonly expect `tessdata` under `Bundle.main` (or a manually configured native bundle path). That mismatch can surface as a classic `Tesseract file not found` / traineddata initialization error.

`thai_native_ocr` removes that failure mode entirely on iOS. The iOS implementation uses Apple's built-in Vision framework (`VNRecognizeTextRequest`) and has **no Tesseract import, pod dependency, tessdata resource, or Tesseract file path handling**.

Android intentionally uses Tesseract and keeps its models in the Android plugin asset bundle at `android/src/main/assets/tessdata/`.

## Two-stage OCR

### Stage 1 — fast Thai detector

When `autoDetectThai` is `true` and `forceLanguage` is not set:

- **iOS:** `VNRecognizeTextRequest`, `.fast`, `automaticallyDetectsLanguage = true`, no explicit recognition language.
- **Android:** quick English Tesseract OCR with `PSM_AUTO_OSD`.
- The resulting text is checked for at least one character in the Thai Unicode range `U+0E00..U+0E7F`.

This stage exists to cheaply determine whether the accurate pass should load Thai recognition.

### Stage 2 — accurate OCR

If Thai was detected:

- iOS: `th-TH`, `en-US`, `.accurate`, language correction enabled.
- Android: `tha+eng`, `PSM_AUTO`, using `tessdata_best`.

Otherwise:

- iOS: `en-US`, `.accurate`.
- Android: `eng`, `PSM_AUTO`.

`containsThai` in the returned result reflects the final OCR text as well as the Stage 1 signal, so a Thai character discovered during the accurate pass is not lost.

## Usage

```dart
import 'package:thai_native_ocr/thai_native_ocr.dart';

final result = await ThaiNativeOcr.recognize('/path/to/image.jpg');

print(result.text);
print(result.containsThai);
print(result.detectedLanguage); // th, en, mixed
print(result.confidence);       // 0.0 - 1.0
```

### Bypass auto-detection

Run the Thai + English accurate pass directly:

```dart
final result = await ThaiNativeOcr.recognize(
  imagePath,
  autoDetectThai: false,
);
```

Or force the language strategy:

```dart
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'th');
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'en');
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'mixed');
```

`forceLanguage` accepts only `th`, `en`, or `mixed`. It takes precedence over `autoDetectThai`.

## Platform requirements

- Flutter 3.10+
- Dart 3.2+
- iOS 13.0+
- Android minSdk 21+

## iOS design rule

The iOS target must remain Vision-only:

- no Tesseract pod
- no Tesseract import
- no `tessdata` resource in the podspec
- no Tesseract file path lookup

This rule is intentional and is part of the package architecture.
