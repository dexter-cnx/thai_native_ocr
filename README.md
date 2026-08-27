# thai_native_ocr

Hybrid native Thai OCR for Flutter.

- **iOS:** Apple Vision only — no Tesseract and no `tessdata` bundle.
- **Android:** Tesseract 5 via Tesseract4Android.
- **Two-stage Android model strategy:** Stage 1 uses `tessdata_fast`; Stage 2 accurate OCR uses `tessdata_best`.
- **Two-stage detection:** fast Thai detection first, then one of two accurate modes: **Thai + English** or **English only**.
- Supports image paths, `File`, and in-memory `Uint8List` bytes.
- Optional OCR-oriented preprocessing for difficult document images.

> ภาษาไทยอยู่ด้านล่าง — [อ่าน README ภาษาไทย](#ภาษาไทย)

## Why iOS uses Apple Vision

Flutter assets are normally packaged under `App.framework/flutter_assets`, while many native Tesseract integrations expect traineddata under a native bundle path such as `Bundle.main`. That mismatch can cause `traineddata not found` or Tesseract initialization errors on iOS.

`thai_native_ocr` removes that failure mode entirely on iOS by using `VNRecognizeTextRequest`. The iOS target intentionally contains no Tesseract dependency, no tessdata resource, and no Tesseract-specific file-path handling.

## OCR strategy

### Stage 1 — fast Thai detector

When `autoDetectThai` is enabled and `forceLanguage` is not set:

- **iOS:** Vision `.fast` recognition with automatic language detection when supported by the OS.
- **Android:** the image is downscaled to at most 960 px on its longest side, then a lightweight `tha+eng` Tesseract pass runs with `PSM_SPARSE_TEXT` using **`tessdata_fast`**.
- The detector checks the OCR output for Thai Unicode characters (`U+0E00..U+0E7F`).

Android deliberately uses a bilingual detector instead of an English-only detector so Thai-only documents do not fall through to English mode simply because the English model emitted no Thai characters.

### Stage 2 — accurate OCR

There are only two execution modes:

| Detection | iOS | Android |
| --- | --- | --- |
| Thai detected | `th-TH` + `en-US`, `.accurate` | `tha+eng`, `PSM_AUTO`, **`tessdata_best`** |
| No Thai detected | `en-US`, `.accurate` | `eng`, `PSM_AUTO`, **`tessdata_best`** |

There is intentionally no Thai-only mode. `forceLanguage: 'th'` is retained only as a backward-compatible alias for the bilingual Thai + English mode.

This split keeps the detector responsive while letting the final OCR pass prioritize Thai recognition quality, including combining marks and diacritics.

## Usage

### Image path

```dart
final result = await ThaiNativeOcr.recognize('/path/to/image.jpg');
```

### File

```dart
import 'dart:io';

final result = await ThaiNativeOcr.recognizeFile(
  File('/path/to/image.jpg'),
);
```

### In-memory bytes

```dart
import 'dart:typed_data';

final Uint8List bytes = ...;
final result = await ThaiNativeOcr.recognizeBytes(bytes);
```

On iOS, byte input is decoded directly in memory; the plugin does not write a temporary image file before passing the image to Vision.

### Preprocessing

```dart
final result = await ThaiNativeOcr.recognize(
  imagePath,
  preprocess: true,
);
```

Preprocessing is opt-in because it is not always beneficial for clean images.

- **Android:** grayscale + local adaptive thresholding before the accurate pass.
- **iOS:** grayscale/contrast/brightness normalization using Core Image before the accurate Vision pass.

This can help low-contrast or unevenly lit document photos where Thai combining marks are easily lost.

### Force OCR strategy

```dart
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'en');
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'mixed');
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'th'); // alias of mixed
```

`forceLanguage` takes precedence over `autoDetectThai`.

## Result

```dart
print(result.text);
print(result.containsThai);
print(result.detectedLanguage); // th, en, mixed
print(result.confidence);       // 0.0 - 1.0
```

## Android model layout

The Android plugin bundles four traineddata files, split by responsibility:

```text
android/src/main/assets/
├── tessdata_fast/
│   ├── tha.traineddata
│   └── eng.traineddata
└── tessdata_best/
    ├── tha.traineddata
    └── eng.traineddata
```

At runtime the plugin copies each profile into a separate private Tesseract data directory. Stage 1 always initializes the fast profile; Stage 2 always initializes the best profile.

The model assets are Android-native assets only and are never bundled into the iOS plugin.

## Example

The example app includes:

- camera capture
- gallery selection
- preprocessing toggle
- `containsThai` result badge
- detected language
- confidence
- recognized text

Run it with:

```bash
cd example
flutter pub get
flutter run
```

## Platform requirements

- Flutter 3.10+
- Dart 3.2+
- iOS 13.0+
- Android minSdk 21+

## License

MIT. Bundled/linked third-party components retain their respective licenses; see `THIRD_PARTY_NOTICES.md`.

For implementation details, see [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md).

---

# ภาษาไทย

`thai_native_ocr` คือ Flutter plugin สำหรับ OCR ภาษาไทย/อังกฤษ โดยเลือก native engine ที่เหมาะกับแต่ละ platform

- **iOS:** ใช้ Apple Vision เท่านั้น ไม่มี Tesseract และไม่มี `tessdata`
- **Android:** ใช้ Tesseract 5 ผ่าน Tesseract4Android
- **Stage 1 Android ใช้ `tessdata_fast`**, ส่วน **Stage 2 OCR จริงใช้ `tessdata_best`**
- **ตรวจภาษาไทย 2 Stage:** ตรวจแบบเร็วก่อน แล้วเลือก OCR แบบแม่นยำเพียง 2 แบบ คือ **ไทย+อังกฤษ** หรือ **อังกฤษล้วน**
- รองรับ path, `File` และ `Uint8List`
- เปิด preprocessing ได้สำหรับภาพเอกสารที่มืดหรือ contrast ไม่สม่ำเสมอ

## ทำไม iOS ใช้ Apple Vision

Flutter มัก pack asset ไว้ใต้ `App.framework/flutter_assets` แต่ Tesseract integration หลายแบบพยายามหา traineddata ผ่าน native bundle path เช่น `Bundle.main` ทำให้เกิดปัญหา `traineddata not found` ได้ง่าย

package นี้ตัดปัญหานั้นออกจาก iOS โดยตรง เพราะใช้ `VNRecognizeTextRequest` ของระบบและไม่พึ่ง Tesseract เลย

## Stage 1 — ตรวจไทยแบบเร็ว

เมื่อใช้ `autoDetectThai: true`:

- **iOS:** Vision `.fast` + automatic language detection เมื่อ OS รองรับ
- **Android:** ย่อภาพให้ด้านยาวไม่เกิน 960 px แล้วใช้ `tha+eng` กับ `PSM_SPARSE_TEXT` และ **`tessdata_fast`**
- ตรวจผลด้วยช่วง Unicode ภาษาไทย `U+0E00..U+0E7F`

Android ไม่ใช้ `eng` ล้วนเป็น detector แล้ว เพราะเอกสารไทยล้วนมีโอกาสที่ English model จะไม่สร้างอักษรไทยออกมาเลยและทำให้เลือก mode ผิด

## Stage 2 — OCR แบบแม่นยำ

Stage 2 ฝั่ง Android ใช้ **`tessdata_best`** เสมอ:

- พบไทย → iOS `th-TH + en-US`; Android `tha+eng + tessdata_best`
- ไม่พบไทย → iOS `en-US`; Android `eng + tessdata_best`

ไม่มีโหมดไทยล้วน โดย `forceLanguage: 'th'` ยังคงรับไว้เพื่อ compatibility แต่ทำงานเหมือน `mixed` คือไทย+อังกฤษ

แนวทางนี้ทำให้ detector ยังเร็วจาก `tessdata_fast` แต่ OCR รอบสุดท้ายเน้นความแม่นยำ โดยเฉพาะสระและวรรณยุกต์ภาษาไทย

## วิธีใช้

```dart
final result = await ThaiNativeOcr.recognize('/path/to/image.jpg');
```

จาก `File`:

```dart
final result = await ThaiNativeOcr.recognizeFile(File(imagePath));
```

จาก bytes:

```dart
final result = await ThaiNativeOcr.recognizeBytes(bytes);
```

บน iOS การส่ง bytes จะ decode ใน memory โดยตรง ไม่ต้องสร้างไฟล์ภาพชั่วคราวก่อนส่งเข้า Vision

## Preprocessing

```dart
final result = await ThaiNativeOcr.recognize(
  imagePath,
  preprocess: true,
);
```

- Android: grayscale + adaptive threshold แบบ local
- iOS: grayscale + ปรับ contrast/brightness ด้วย Core Image

เหมาะกับรูปเอกสารที่แสงไม่สม่ำเสมอ ตัวหนังสือจาง หรือมีโอกาสทำให้สระ/วรรณยุกต์ไทยหาย

## Android model

model แยกเป็น 2 ชุด:

```text
android/src/main/assets/
├── tessdata_fast/   # Stage 1 detector
│   ├── tha.traineddata
│   └── eng.traineddata
└── tessdata_best/   # Stage 2 accurate OCR
    ├── tha.traineddata
    └── eng.traineddata
```

runtime จะ copy สอง profile ไปไว้คนละ private Tesseract data directory เพื่อไม่ให้ model fast/best ปนกัน

## Example

example มีปุ่มถ่ายรูป, เลือกรูปจาก gallery, toggle preprocessing, badge `Thai detected` / `English only`, confidence และข้อความ OCR

```bash
cd example
flutter pub get
flutter run
```

## Requirement

- Flutter 3.10+
- Dart 3.2+
- iOS 13.0+
- Android minSdk 21+

License หลักของ package เป็น MIT และรายละเอียด third-party อยู่ใน `THIRD_PARTY_NOTICES.md`
