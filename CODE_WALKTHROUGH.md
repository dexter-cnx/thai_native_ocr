# thai_native_ocr Code Walkthrough

## English

### 1. Public Dart API

The public API is in `lib/thai_native_ocr.dart`.

```dart
ThaiNativeOcr.recognize(imagePath)
ThaiNativeOcr.recognizeFile(file)
ThaiNativeOcr.recognizeBytes(bytes)
```

All three methods accept the same OCR controls:

```dart
autoDetectThai: true
forceLanguage: null
preprocess: false
```

The Dart layer validates arguments, sends one `recognize` call over `MethodChannel('thai_native_ocr')`, then converts the native result map into `ThaiOcrResult`.

The result contract is platform-independent:

- `text`
- `containsThai`
- `detectedLanguage` (`th`, `en`, `mixed`)
- `confidence` (`0.0..1.0`)

### 2. Platform-channel contract

Native receives either:

```text
imagePath
```

or:

```text
imageBytes
```

plus:

```text
autoDetectThai
forceLanguage
preprocess
```

`recognizeBytes` does not require a temporary image path. iOS decodes the provided bytes directly in memory.

### 3. OCR execution modes

There are only two accurate OCR modes:

```text
Thai detected -> Thai + English
No Thai       -> English only
```

There is intentionally no Thai-only mode. `forceLanguage: 'th'` is retained as a compatibility alias of the bilingual mode.

### 4. iOS flow

Implementation:

```text
ios/Classes/ThaiNativeOcrPlugin.swift
```

iOS uses Apple Vision only.

Default flow:

```text
UIImage / image bytes
  -> Stage 1 Vision .fast
  -> Thai Unicode check
  -> choose th-TH+en-US or en-US
  -> optional Core Image preprocessing
  -> Stage 2 Vision .accurate
  -> ThaiOcrResult
```

Stage 1 uses no explicit recognition language and enables automatic language detection on OS versions where Vision exposes it.

Stage 2:

```text
Thai detected -> ["th-TH", "en-US"] + .accurate
No Thai       -> ["en-US"] + .accurate
```

When `preprocess: true`, the image is normalized with Core Image using grayscale, additional contrast, and a small brightness adjustment before the accurate pass.

OCR work runs on a user-initiated background queue and returns results to Flutter on the main queue.

### 5. Why iOS is Vision-only

Flutter commonly stores assets under a location such as:

```text
App.framework/flutter_assets/
```

Native Tesseract integrations often expect traineddata through a native bundle/filesystem path. That mismatch can lead to traineddata initialization failures.

The iOS implementation therefore has:

- no Tesseract pod
- no Tesseract import
- no tessdata resource
- no Tesseract-specific bundle lookup

### 6. Android flow

Implementation:

```text
android/src/main/kotlin/com/example/thai_native_ocr/ThaiNativeOcrPlugin.kt
```

Android uses Tesseract4Android 4.9.0, which embeds Tesseract 5.5.1 and supports current v4+ traineddata files.

Bundled models:

```text
android/src/main/assets/tessdata/eng.traineddata
android/src/main/assets/tessdata/tha.traineddata
```

The default models come from `tessdata_fast` to reduce package size and improve runtime speed compared with `tessdata_best`.

On first use for a model revision, they are copied to:

```text
context.filesDir/tessdata/
```

A small model-version marker prevents copying them again on every OCR call while still allowing package upgrades to refresh the cached files.

### 7. Android Stage 1 detector

The old design used an English-only full OCR pass. That is weak for Thai-only documents because an English model may emit no Thai characters at all.

The 0.2.0 detector instead does:

```text
input bitmap
  -> downscale longest side to <= 960 px
  -> Tesseract tha+eng
  -> PSM_SPARSE_TEXT
  -> check [\u0E00-\u0E7F]
```

This is still OCR-based rather than direct OSD script metadata because the original `tess-two`-style Java API exposes the OSD page-segmentation constants but does not expose a simple `baseApi.osd` script-result property. The bilingual downscaled pass is therefore a practical detector that avoids the Thai-only false-negative problem without adding a custom JNI layer.

### 8. Android preprocessing

When `preprocess: true`, Android performs:

```text
ARGB bitmap
  -> grayscale
  -> integral-image local mean
  -> adaptive threshold
  -> Stage 2 OCR
```

The integral-image implementation keeps local threshold calculation O(width * height) instead of repeatedly scanning each threshold window.

The goal is to improve recognition on uneven lighting, low contrast, and small Thai combining marks.

### 9. Bypass controls

```dart
ThaiNativeOcr.recognize(
  imagePath,
  autoDetectThai: false,
)
```

skips Stage 1 and directly uses Thai + English.

`forceLanguage` takes precedence:

```text
en    -> English only
mixed -> Thai + English
th    -> Thai + English compatibility alias
```

### 10. Example app

The example supports:

- taking a photo
- selecting a gallery image
- toggling preprocessing
- Thai-detected / English-only badge
- language and confidence display
- recognized text display

The example is also used by native build CI to verify Android and iOS plugin compilation.

---

## ภาษาไทย

### 1. Public API ฝั่ง Dart

API หลักอยู่ใน `lib/thai_native_ocr.dart`

```dart
ThaiNativeOcr.recognize(imagePath)
ThaiNativeOcr.recognizeFile(file)
ThaiNativeOcr.recognizeBytes(bytes)
```

ทั้ง 3 แบบใช้ option ชุดเดียวกัน:

```dart
autoDetectThai: true
forceLanguage: null
preprocess: false
```

Dart จะตรวจ argument แล้วส่ง native method ชื่อ `recognize` ผ่าน `MethodChannel('thai_native_ocr')`

ผลลัพธ์ทุก platform ใช้ contract เดียวกัน:

- `text`
- `containsThai`
- `detectedLanguage` (`th`, `en`, `mixed`)
- `confidence` (`0.0..1.0`)

### 2. รองรับ Path, File และ Bytes

native จะได้รับอย่างใดอย่างหนึ่ง:

```text
imagePath
```

หรือ:

```text
imageBytes
```

พร้อม `autoDetectThai`, `forceLanguage`, `preprocess`

กรณี `recognizeBytes()` ฝั่ง iOS จะ decode จาก memory โดยตรง ไม่ต้องสร้างไฟล์ภาพชั่วคราวก่อนเข้า Vision

### 3. OCR มีแค่ 2 mode

ระบบ accurate OCR มีจริงเพียง:

```text
พบไทย    -> ไทย + อังกฤษ
ไม่พบไทย -> อังกฤษล้วน
```

ไม่มี mode ไทยล้วน

`forceLanguage: 'th'` ยังรับไว้เพื่อ backward compatibility แต่ทำงานเหมือน `mixed`

### 4. iOS

ไฟล์หลัก:

```text
ios/Classes/ThaiNativeOcrPlugin.swift
```

iOS ใช้ Apple Vision เท่านั้น

flow default:

```text
รูป / bytes
  -> Vision .fast
  -> ตรวจ Unicode ไทย
  -> เลือก th-TH+en-US หรือ en-US
  -> optional preprocessing
  -> Vision .accurate
  -> ThaiOcrResult
```

ถ้า `preprocess: true` จะใช้ Core Image ปรับเป็น grayscale เพิ่ม contrast และ brightness เล็กน้อยก่อน accurate pass

สาเหตุที่ iOS ไม่ใช้ Tesseract คือเพื่อกำจัดปัญหา path ของ `traineddata` ระหว่าง Flutter asset กับ native bundle ตั้งแต่ architecture level

### 5. Android

ไฟล์หลัก:

```text
android/src/main/kotlin/com/example/thai_native_ocr/ThaiNativeOcrPlugin.kt
```

Android ใช้ Tesseract4Android 4.9.0 ซึ่งใช้ Tesseract 5.5.1 และรองรับ traineddata รุ่นปัจจุบัน

model default เปลี่ยนเป็น `tessdata_fast`:

```text
eng.traineddata
tha.traineddata
```

เก็บใน Android asset แล้ว copy ครั้งแรกของแต่ละ model revision ไปที่:

```text
context.filesDir/tessdata/
```

มี marker version เพื่อไม่ให้ copy model ซ้ำทุก OCR call

### 6. Stage 1 บน Android

เดิมใช้ English OCR อย่างเดียว ซึ่งมีโอกาสพลาดเอกสารไทยล้วน เพราะ `eng` อาจไม่สร้าง Unicode ไทยออกมาเลย

ตอนนี้ Stage 1 ทำแบบนี้:

```text
รูปต้นฉบับ
  -> ย่อด้านยาว <= 960 px
  -> tha+eng
  -> PSM_SPARSE_TEXT
  -> ตรวจ [\u0E00-\u0E7F]
```

เหตุผลที่ไม่ได้ใช้ `baseApi.osd` ตาม pseudo-code ทั่วไป คือ Java wrapper สาย `tess-two`/Tesseract4Android ไม่มี property แบบนั้นให้เรียกตรง ๆ แม้จะมี `PSM_OSD_ONLY` constant อยู่ก็ตาม ถ้าจะอ่าน script metadata แบบ native OSD จริงต้องเพิ่ม JNI contract เอง

แนวทาง downscaled bilingual detector จึงแก้ false-negative ภาษาไทยได้โดยไม่เพิ่ม JNI layer ใหม่

### 7. Preprocessing บน Android

เมื่อ `preprocess: true`:

```text
Bitmap
  -> grayscale
  -> integral image
  -> adaptive threshold แบบ local
  -> OCR Stage 2
```

การใช้ integral image ทำให้คำนวณ local threshold ต่อ pixel ได้เร็วกว่า loop scan window ซ้ำ ๆ

เป้าหมายคือช่วยรูปที่แสงไม่สม่ำเสมอ ตัวอักษรจาง และสระ/วรรณยุกต์ไทยที่หายง่าย

### 8. Example

example ตอนนี้มี:

- ปุ่มถ่ายรูป
- ปุ่มเลือกจาก gallery
- toggle preprocessing
- badge `Thai detected` / `English only`
- language/confidence
- ข้อความ OCR

จึงใช้เป็น manual device-test harness ได้ทันทีทั้ง Android และ iOS
