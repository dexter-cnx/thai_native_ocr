# thai_native_ocr

Native OCR for Flutter with a hybrid platform implementation:

- **iOS:** Apple Vision only. No Tesseract dependency and no `tessdata` bundle.
- **Android:** Tesseract via `tess-two`, with Thai + English `tessdata_best` models.
- **Two-stage Thai auto-detection:** run a lightweight detector first, then select one of two accurate OCR modes: Thai + English or English only.

> ภาษาไทยอยู่ด้านล่าง — [อ่าน README ภาษาไทย](#ภาษาไทย)

## Why this fixes the iOS Tesseract file-not-found bug

A common Flutter/Tesseract failure on iOS is caused by resource lookup differences. Flutter assets are packaged under `App.framework/flutter_assets`, while native Tesseract integrations commonly expect `tessdata` under `Bundle.main` (or a manually configured native bundle path). That mismatch can surface as a classic `Tesseract file not found` / traineddata initialization error.

`thai_native_ocr` removes that failure mode entirely on iOS. The iOS implementation uses Apple's built-in Vision framework (`VNRecognizeTextRequest`) and has **no Tesseract import, pod dependency, tessdata resource, or Tesseract file path handling**.

Android intentionally uses Tesseract and keeps its models in the Android plugin asset bundle at `android/src/main/assets/tessdata/`.

## Two-stage OCR

### Stage 1 — fast Thai detector

When `autoDetectThai` is `true` and `forceLanguage` is not set:

- **iOS:** `VNRecognizeTextRequest`, `.fast`, `automaticallyDetectsLanguage = true`, no explicit recognition language.
- **Android:** quick English Tesseract OCR with `PSM_AUTO`.
- The resulting text is checked for at least one character in the Thai Unicode range `U+0E00..U+0E7F`.

This stage exists to cheaply determine which accurate OCR mode should be used.

### Stage 2 — accurate OCR

There are only two execution modes.

If Thai was detected:

- iOS: `th-TH` + `en-US`, `.accurate`, language correction enabled.
- Android: `tha+eng`, `PSM_AUTO`, using `tessdata_best`.

Otherwise:

- iOS: `en-US`, `.accurate`.
- Android: `eng`, `PSM_AUTO`.

There is intentionally **no Thai-only OCR mode**. Whenever Thai recognition is enabled, English recognition remains enabled as well.

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
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'en');    // English only
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'mixed'); // Thai + English
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'th');    // backward-compatible alias for Thai + English
```

`forceLanguage` accepts `th`, `en`, or `mixed`. `th` is retained for backward compatibility but behaves exactly like `mixed`; it does not enable a Thai-only OCR pass. `forceLanguage` takes precedence over `autoDetectThai`.

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

For implementation details, see [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md).

---

# ภาษาไทย

`thai_native_ocr` คือ Flutter plugin สำหรับ OCR ที่ใช้ native engine ให้เหมาะกับแต่ละ platform โดย API ฝั่ง Dart ยังคงเหมือนกันทั้งหมด

- **iOS:** ใช้ Apple Vision เท่านั้น ไม่มี Tesseract และไม่มี `tessdata`
- **Android:** ใช้ Tesseract ผ่าน `tess-two` พร้อมโมเดลภาษาไทยและอังกฤษจาก `tessdata_best`
- **ตรวจภาษาไทยแบบ 2 Stage:** ตรวจแบบเร็วรอบแรก แล้วเลือก OCR แบบแม่นยำเพียง 2 แบบ คือ **ไทย+อังกฤษ** หรือ **อังกฤษล้วน**

## ทำไม package นี้แก้ปัญหา Tesseract file not found บน iOS ได้

ปัญหาที่พบบ่อยเวลาใช้ Flutter ร่วมกับ Tesseract บน iOS คือ path ของ resource ไม่ตรงกัน

Flutter มัก pack asset ไว้ใต้เส้นทางลักษณะนี้:

```text
App.framework/flutter_assets/
```

แต่ Tesseract native integration หลายแบบพยายามหา `traineddata` ผ่าน `Bundle.main` หรือ native bundle path ที่กำหนดเอง

เมื่อ path ที่ Tesseract คาดไว้ไม่ตรงกับตำแหน่งที่ Flutter ใส่ไฟล์จริง จะเกิด error เช่น:

```text
Tesseract file not found
traineddata not found
failed to initialize Tesseract
```

`thai_native_ocr` ตัดปัญหานี้ออกไปจาก iOS โดยตรง เพราะ **iOS ไม่ใช้ Tesseract เลย** แต่ใช้ Apple Vision (`VNRecognizeTextRequest`) ซึ่งมากับระบบปฏิบัติการอยู่แล้ว

ดังนั้นฝั่ง iOS จะไม่มี:

- Tesseract pod
- Tesseract import
- `tessdata` resource ใน podspec
- Tesseract file path lookup

ส่วน Android ยังใช้ Tesseract ตามปกติ และเก็บ model ไว้เฉพาะที่:

```text
android/src/main/assets/tessdata/
```

## ระบบตรวจภาษาไทยแบบ 2 Stage

### Stage 1 — ตรวจภาษาไทยแบบเร็ว

เมื่อใช้ค่า default:

```dart
autoDetectThai: true
```

และไม่ได้กำหนด `forceLanguage` ระบบจะทำ detector pass ก่อน

- **iOS:** `VNRecognizeTextRequest` แบบ `.fast` เปิด `automaticallyDetectsLanguage`
- **Android:** quick OCR ด้วย English Tesseract และ `PSM_AUTO`
- จากนั้นตรวจว่าข้อความมีอักขระในช่วง Unicode ภาษาไทย `U+0E00..U+0E7F` หรือไม่

regex ที่ใช้มีแนวคิดเทียบเท่ากับ:

```text
[\u0E00-\u0E7F]
```

ถ้าเจออักษรไทยอย่างน้อย 1 ตัว จะเลือก bilingual OCR สำหรับ Stage 2

### Stage 2 — OCR แบบแม่นยำ

ระบบมี execution mode จริงเพียง 2 แบบ

ถ้าพบภาษาไทย:

- iOS: `th-TH` + `en-US`, `.accurate`, เปิด language correction
- Android: `tha+eng`, `PSM_AUTO`, ใช้ `tessdata_best`

ถ้าไม่พบภาษาไทย:

- iOS: `en-US`, `.accurate`
- Android: `eng`, `PSM_AUTO`

**ไม่มีโหมดไทยล้วน** เมื่อเปิดการอ่านภาษาไทย ระบบจะเปิดอังกฤษควบคู่ไปด้วยเสมอ เพื่อรองรับเอกสารไทยที่มีตัวเลข คำอังกฤษ ชื่อแบรนด์ รหัส หรือข้อความสองภาษาอยู่ในภาพเดียวกัน

ค่า `containsThai` สุดท้ายไม่ได้อิงแค่ Stage 1 แต่ตรวจผล Stage 2 ด้วย ดังนั้นถ้า detector รอบแรกพลาด แต่ accurate OCR อ่านเจอภาษาไทย ผลลัพธ์สุดท้ายก็ยังเป็น `true`

## วิธีใช้งาน

```dart
import 'package:thai_native_ocr/thai_native_ocr.dart';

final result = await ThaiNativeOcr.recognize('/path/to/image.jpg');

print(result.text);
print(result.containsThai);
print(result.detectedLanguage); // th, en, mixed
print(result.confidence);       // 0.0 - 1.0
```

ค่าที่ได้จาก `ThaiOcrResult`:

- `text` — ข้อความจาก accurate OCR pass
- `containsThai` — พบอักษรไทยหรือไม่
- `detectedLanguage` — `th`, `en` หรือ `mixed`
- `confidence` — confidence ที่ normalize เป็น `0.0..1.0`

## ข้ามระบบ Auto-detect

ถ้ารู้อยู่แล้วว่าเอกสารอาจมีทั้งไทยและอังกฤษ สามารถข้าม Stage 1 ได้:

```dart
final result = await ThaiNativeOcr.recognize(
  imagePath,
  autoDetectThai: false,
);
```

ระบบจะเข้า accurate bilingual OCR โดยตรง

หรือบังคับ strategy ด้วย `forceLanguage`:

```dart
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'en');    // อังกฤษล้วน
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'mixed'); // ไทย + อังกฤษ
await ThaiNativeOcr.recognize(imagePath, forceLanguage: 'th');    // alias เดิมของไทย + อังกฤษ
```

`th` ถูกเก็บไว้เพื่อ backward compatibility เท่านั้น และทำงานเหมือน `mixed` ทุกประการ ไม่ได้เรียก OCR แบบไทยล้วน ส่วน `forceLanguage` มี priority สูงกว่า `autoDetectThai`

## Requirement ของ Platform

- Flutter 3.10+
- Dart 3.2+
- iOS 13.0+
- Android minSdk 21+

## กฎสำคัญของ iOS

ฝั่ง iOS ต้องคง architecture แบบ Vision-only:

- ห้ามเพิ่ม Tesseract pod
- ห้าม import Tesseract
- ห้ามเพิ่ม `tessdata` เข้า podspec
- ห้ามเพิ่ม Tesseract-specific file path handling

เงื่อนไขนี้ไม่ใช่ข้อจำกัดชั่วคราว แต่เป็นส่วนหนึ่งของ architecture เพื่อป้องกันปัญหา traineddata path บน iOS โดยตรง

ดูรายละเอียดเส้นทางการทำงานของโค้ดเพิ่มเติมได้ที่ [`CODE_WALKTHROUGH.md`](CODE_WALKTHROUGH.md) ซึ่งมีทั้งภาษาอังกฤษและภาษาไทย
