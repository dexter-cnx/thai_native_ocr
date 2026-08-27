# thai_native_ocr Code Walkthrough

## English

### 1. Public Dart API

The public API lives in `lib/thai_native_ocr.dart`:

```dart
ThaiNativeOcr.recognize(imagePath)
ThaiNativeOcr.recognizeFile(file)
ThaiNativeOcr.recognizeBytes(bytes)
```

All entry points share the same controls:

```dart
autoDetectThai: true
forceLanguage: null
preprocess: false
```

The Dart layer validates input, invokes `recognize` over `MethodChannel('thai_native_ocr')`, and maps the native response into `ThaiOcrResult`:

- `text`
- `containsThai`
- `detectedLanguage` (`th`, `en`, `mixed`)
- `confidence` (`0.0..1.0`)

### 2. Input contract

Native receives either `imagePath` or `imageBytes`, plus `autoDetectThai`, `forceLanguage`, and `preprocess`.

`recognizeBytes()` avoids requiring callers to create a temporary image file. On iOS, bytes are decoded directly in memory before Vision OCR.

### 3. OCR execution modes

There are only two final recognition modes:

```text
Thai detected -> Thai + English
No Thai       -> English only
```

There is intentionally no Thai-only recognition mode. `forceLanguage: 'th'` is retained as a compatibility alias for Thai + English.

### 4. iOS flow

Implementation:

```text
ios/Classes/ThaiNativeOcrPlugin.swift
```

iOS uses Apple Vision only:

```text
UIImage / bytes
  -> Stage 1 Vision .fast
  -> Thai Unicode check
  -> choose th-TH+en-US or en-US
  -> optional Core Image preprocessing
  -> Stage 2 Vision .accurate
  -> ThaiOcrResult
```

Stage 1 uses automatic language detection where supported by the OS. Stage 2 uses `["th-TH", "en-US"]` when Thai is detected, otherwise `["en-US"]`.

With `preprocess: true`, Core Image applies grayscale/contrast/brightness normalization before the accurate pass.

### 5. Why iOS is Vision-only

Flutter assets are normally under a path such as `App.framework/flutter_assets`, while native Tesseract integrations commonly expect traineddata through native bundle/filesystem paths. To eliminate that class of deployment failure, the iOS target has no Tesseract dependency and no tessdata resource.

### 6. Android model architecture

Implementation:

```text
android/src/main/kotlin/com/example/thai_native_ocr/ThaiNativeOcrPlugin.kt
```

Android uses Tesseract4Android 4.9.0 / Tesseract 5.5.1.

The plugin bundles four traineddata files and splits them by responsibility:

```text
android/src/main/assets/
├── tessdata_fast/
│   ├── tha.traineddata
│   └── eng.traineddata
└── tessdata_best/
    ├── tha.traineddata
    └── eng.traineddata
```

- Stage 1 detector uses `tessdata_fast`.
- Stage 2 final recognition uses `tessdata_best`.

The host application developer does **not** download, add, or configure traineddata. The models ship with the plugin and are copied automatically on first use into separate private Tesseract data directories under the app's `filesDir`.

Fast and best profiles have separate version markers so package upgrades can refresh either cache safely without mixing model families.

### 7. Android Stage 1 — fast Thai detector

The old English-only detector could miss Thai-only pages because the English model may emit no Thai Unicode at all.

The current detector is:

```text
input bitmap
  -> downscale longest side to <= 960 px
  -> tessdata_fast tha+eng
  -> PSM_SPARSE_TEXT
  -> check [\u0E00-\u0E7F]
```

Stage 1 is not intended to produce final OCR text. It only needs enough signal to answer whether Thai is present.

A direct `OSD_ONLY` script-result approach is not used because the Java wrapper does not expose a simple script-result property equivalent to native Tesseract's orientation/script APIs without adding a custom JNI contract.

### 8. Android Stage 2 — accurate OCR

Stage 2 always uses `tessdata_best` and the full-resolution image:

```text
Thai detected -> tha+eng + tessdata_best + PSM_AUTO
No Thai       -> eng     + tessdata_best + PSM_AUTO
```

This design deliberately trades some Android package size for better final recognition quality, especially for Thai vowels, tone marks, and small combining characters.

### 9. Android preprocessing

With `preprocess: true`:

```text
Bitmap
  -> grayscale
  -> integral-image local mean
  -> adaptive threshold
  -> Stage 2 OCR
```

The integral-image approach keeps local-threshold calculation approximately O(width * height) and avoids repeatedly scanning each neighborhood window.

### 10. Bypass controls

`autoDetectThai: false` skips Stage 1 and goes directly to bilingual Stage 2 recognition.

`forceLanguage` takes precedence:

```text
en    -> English only
mixed -> Thai + English
th    -> Thai + English compatibility alias
```

### 11. Example and validation

The example supports camera capture, gallery selection, preprocessing toggle, Thai/English badge, detected language, confidence, and recognized text. Native build CI compiles the Android debug APK and iOS simulator app, while the pub dry-run workflow validates package publication readiness.

---

## ภาษาไทย

### 1. Public API ฝั่ง Dart

API อยู่ใน `lib/thai_native_ocr.dart`:

```dart
ThaiNativeOcr.recognize(imagePath)
ThaiNativeOcr.recognizeFile(file)
ThaiNativeOcr.recognizeBytes(bytes)
```

ใช้ option ชุดเดียวกัน:

```dart
autoDetectThai: true
forceLanguage: null
preprocess: false
```

ผลลัพธ์คือ `ThaiOcrResult` ซึ่งมี `text`, `containsThai`, `detectedLanguage` และ `confidence`.

### 2. รองรับ Path, File และ Bytes

native รับ `imagePath` หรือ `imageBytes` พร้อม `autoDetectThai`, `forceLanguage`, `preprocess`.

`recognizeBytes()` ช่วยให้ dev ไม่ต้องสร้าง temporary image file เอง และฝั่ง iOS decode bytes ใน memory ก่อนส่งเข้า Vision.

### 3. Final OCR มีเพียง 2 mode

```text
พบไทย    -> ไทย + อังกฤษ
ไม่พบไทย -> อังกฤษล้วน
```

ไม่มี mode ไทยล้วน โดย `forceLanguage: 'th'` เป็น compatibility alias ของไทย+อังกฤษ.

### 4. iOS

ไฟล์หลัก:

```text
ios/Classes/ThaiNativeOcrPlugin.swift
```

iOS ใช้ Apple Vision เท่านั้น:

```text
รูป / bytes
  -> Vision .fast
  -> ตรวจ Unicode ไทย
  -> เลือก th-TH+en-US หรือ en-US
  -> optional Core Image preprocessing
  -> Vision .accurate
  -> ThaiOcrResult
```

ไม่มี Tesseract และไม่มี tessdata บน iOS เพื่อหลีกเลี่ยงปัญหา path ระหว่าง Flutter assets กับ native bundle.

### 5. โครงสร้าง model ฝั่ง Android

Android ใช้ Tesseract4Android 4.9.0 / Tesseract 5.5.1 และ bundle model 4 ไฟล์มากับ plugin:

```text
android/src/main/assets/
├── tessdata_fast/
│   ├── tha.traineddata
│   └── eng.traineddata
└── tessdata_best/
    ├── tha.traineddata
    └── eng.traineddata
```

- Stage 1 ใช้ `tessdata_fast`
- Stage 2 ใช้ `tessdata_best`

**dev ที่นำ package ไปใช้ไม่ต้อง download model, ไม่ต้องเพิ่ม asset ใน host app และไม่ต้อง copy traineddata เอง** เพราะ plugin bundle มาให้และ copy เข้า private `filesDir` อัตโนมัติเมื่อใช้งานครั้งแรก.

fast/best ใช้ cache และ version marker แยกกัน จึงไม่เกิดการปน model ระหว่าง profile และรองรับการ refresh model เมื่ออัปเกรด package.

### 6. Stage 1 — ตรวจไทยแบบเร็ว

```text
รูปต้นฉบับ
  -> ย่อด้านยาว <= 960 px
  -> tessdata_fast tha+eng
  -> PSM_SPARSE_TEXT
  -> ตรวจ [\u0E00-\u0E7F]
```

เป้าหมาย Stage 1 คือแค่ตอบว่ามีภาษาไทยหรือไม่ ไม่ใช่อ่านข้อความให้แม่นที่สุด.

ไม่ใช้ English-only detector เพราะเอกสารไทยล้วนมีโอกาสถูกจัดเป็น English ผิด และไม่ใช้ `OSD_ONLY` script metadata โดยตรงเพราะ Java wrapper ไม่มี API script-result ง่าย ๆ โดยไม่เพิ่ม JNI contract เอง.

### 7. Stage 2 — OCR แบบแม่นยำ

Stage 2 ใช้ภาพ full resolution และ `tessdata_best` เสมอ:

```text
พบไทย    -> tha+eng + tessdata_best + PSM_AUTO
ไม่พบไทย -> eng     + tessdata_best + PSM_AUTO
```

แนวทางนี้ยอมให้ Android package ใหญ่ขึ้นเพื่อแลกกับคุณภาพ OCR รอบสุดท้าย โดยเฉพาะสระ วรรณยุกต์ และ combining marks ภาษาไทย.

### 8. Preprocessing

เมื่อ `preprocess: true`:

```text
Bitmap
  -> grayscale
  -> integral image
  -> adaptive threshold
  -> Stage 2 OCR
```

เหมาะกับภาพแสงไม่สม่ำเสมอ ตัวหนังสือจาง หรือภาพที่สระ/วรรณยุกต์ไทยหายง่าย.

### 9. Bypass controls

`autoDetectThai: false` จะข้าม Stage 1 และเข้า Thai+English Stage 2 โดยตรง.

```text
en    -> อังกฤษล้วน
mixed -> ไทย + อังกฤษ
th    -> ไทย + อังกฤษ (compatibility alias)
```

### 10. Example และ CI

example มีถ่ายรูป, gallery, preprocessing toggle, badge Thai/English, language, confidence และข้อความ OCR. Native CI build ทั้ง Android APK และ iOS simulator ส่วน pub dry-run ใช้ตรวจความพร้อมก่อน publish ขึ้น pub.dev.
