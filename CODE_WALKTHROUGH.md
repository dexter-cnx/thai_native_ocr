# thai_native_ocr Code Walkthrough

## English

### 1. Entry point

The public Dart API lives in `lib/thai_native_ocr.dart`.

```dart
final result = await ThaiNativeOcr.recognize(imagePath);
```

`ThaiNativeOcr.recognize()` validates the arguments, sends them over `MethodChannel('thai_native_ocr')`, and converts the native map into `ThaiOcrResult`.

The result contains:

- `text`
- `containsThai`
- `detectedLanguage` (`th`, `en`, or `mixed`)
- `confidence` (`0.0..1.0`)

### 2. Channel contract

Flutter calls native method `recognize` with:

```text
imagePath
autoDetectThai
forceLanguage
```

Both platforms return the same map shape, which keeps the Dart-facing API platform-independent.

### 3. Two-stage OCR flow

Default flow:

```text
imagePath
  -> Stage 1 fast OCR
  -> check Thai Unicode U+0E00..U+0E7F
  -> choose language strategy
  -> Stage 2 accurate OCR
  -> normalize language/confidence
  -> ThaiOcrResult
```

One Thai character found by the regular expression `[\u0E00-\u0E7F]` is enough to set the detector signal.

The final `containsThai` also checks Stage 2 output, so Thai discovered only in the accurate pass is not lost.

### 4. iOS: Apple Vision only

Implementation: `ios/Classes/ThaiNativeOcrPlugin.swift`

The iOS implementation imports Vision and UIKit. It deliberately does not use Tesseract.

Stage 1:

```text
VNRecognizeTextRequest
recognitionLevel = .fast
recognitionLanguages = []
automaticallyDetectsLanguage = true
usesLanguageCorrection = false
```

Stage 2 when Thai is detected:

```text
recognitionLanguages = ["th-TH", "en-US"]
recognitionLevel = .accurate
usesLanguageCorrection = true
```

Stage 2 without Thai:

```text
recognitionLanguages = ["en-US"]
recognitionLevel = .accurate
```

OCR work runs on `DispatchQueue.global(qos: .userInitiated)` and returns to Flutter on the main queue.

`runVision(...)` performs the Vision request, collects top candidates, joins recognized lines, and averages confidence values.

### 5. Why iOS contains no tessdata

The architecture intentionally removes the common Flutter+iOS Tesseract resource-path failure.

Flutter assets are normally packaged under a location such as:

```text
App.framework/flutter_assets/
```

Tesseract integrations often search traineddata through a native bundle path such as `Bundle.main`. A mismatch between those two locations causes traineddata initialization failures.

`thai_native_ocr` avoids the problem entirely on iOS by using Apple's built-in Vision framework. There is no Tesseract pod, no tessdata resource, and no Tesseract-specific file lookup.

### 6. Android: tess-two + tessdata_best

Implementation: `android/src/main/kotlin/com/example/thai_native_ocr/ThaiNativeOcrPlugin.kt`

Android uses:

```text
com.rmtheis:tess-two:9.1.0
```

Models are bundled only in the Android plugin:

```text
android/src/main/assets/tessdata/eng.traineddata
android/src/main/assets/tessdata/tha.traineddata
```

On first use, the plugin copies them into:

```text
context.filesDir/tessdata/
```

This is required because tess-two expects filesystem-based Tesseract data.

Stage 1 uses a lightweight English OCR pass and checks its output with the Thai Unicode regex.

Stage 2 uses:

```text
Thai detected: tha+eng, PSM_AUTO
No Thai:       eng, PSM_AUTO
```

The package does not require `osd.traineddata`; this is why the detector uses quick English OCR rather than forcing an OSD mode that would need a third model file.

### 7. Bypass modes

`autoDetectThai: false` skips Stage 1 and directly uses the bilingual accurate strategy.

`forceLanguage` takes precedence over `autoDetectThai`:

- `th` -> Thai strategy
- `en` -> English-only strategy
- `mixed` -> bilingual strategy

### 8. Example app

`example/lib/main.dart` uses `image_picker` to select an image, calls `ThaiNativeOcr.recognize(image.path)`, and displays:

- `containsThai`
- `detectedLanguage`
- `confidence`
- recognized text

This example is also useful as a simple manual device-test harness.

---

## ภาษาไทย

### 1. จุดเริ่มต้นของ API

API ที่แอป Flutter ใช้อยู่ใน `lib/thai_native_ocr.dart`

```dart
final result = await ThaiNativeOcr.recognize(imagePath);
```

หน้าที่ของ `ThaiNativeOcr.recognize()` คือ:

1. ตรวจสอบ `imagePath` และ `forceLanguage`
2. ส่งข้อมูลผ่าน `MethodChannel('thai_native_ocr')`
3. เรียก native method ชื่อ `recognize`
4. รับ Map จาก native
5. แปลงเป็น `ThaiOcrResult`

แอปจึงไม่ต้องรู้ว่า iOS กับ Android ใช้ OCR engine คนละตัว

### 2. ทำไมต้องมี Two-stage OCR

แนวคิดหลักคือไม่เปิด OCR แบบ Thai+English ที่หนักกว่าในทุกภาพตั้งแต่ต้น

เมื่อ `autoDetectThai: true` ซึ่งเป็นค่า default ระบบทำงานดังนี้:

```text
รูปภาพ
  -> Stage 1 OCR แบบเร็ว
  -> ตรวจ Unicode ภาษาไทย
  -> เลือกภาษาให้เหมาะสม
  -> Stage 2 OCR แบบแม่นยำ
  -> ส่งผลกลับ Flutter
```

การตรวจภาษาไทยใช้ช่วง Unicode:

```text
U+0E00 ถึง U+0E7F
```

หรือ regex:

```text
[\u0E00-\u0E7F]
```

ถ้าเจออักษรไทยอย่างน้อย 1 ตัว จะถือว่า `containsThai = true` สำหรับการเลือก engine ใน Stage 2

หลัง Stage 2 จะตรวจข้อความอีกครั้งด้วย ดังนั้นถ้า Stage 1 พลาดภาษาไทย แต่ Stage 2 อ่านเจอ ค่า `containsThai` สุดท้ายก็ยังถูกต้อง

### 3. การทำงานบน iOS

ไฟล์หลักคือ:

```text
ios/Classes/ThaiNativeOcrPlugin.swift
```

iOS ใช้ **Apple Vision เท่านั้น** ไม่มี Tesseract

Stage 1 ใช้ `VNRecognizeTextRequest` แบบ `.fast` และเปิด `automaticallyDetectsLanguage`

ถ้าพบภาษาไทย Stage 2 จะเปลี่ยนเป็น:

```text
th-TH + en-US
.accurate
usesLanguageCorrection = true
```

ถ้าไม่พบภาษาไทย:

```text
en-US
.accurate
```

OCR ทำงานบน background queue ด้วย `DispatchQueue.global(qos: .userInitiated)` เพื่อไม่ให้ UI ค้าง แล้วค่อยส่งผลกลับ Flutter บน main queue

### 4. เหตุผลที่ iOS ห้ามใช้ Tesseract

นี่เป็น design rule ที่สำคัญที่สุดของ package

ปัญหาเดิมที่พบบ่อยใน Flutter+iOS คือ Flutter นำ asset ไปไว้ใต้เส้นทางลักษณะนี้:

```text
App.framework/flutter_assets/
```

แต่ Tesseract native integration หลายแบบพยายามหา `traineddata` จาก native bundle เช่น `Bundle.main`

เมื่อ path ที่คาดไว้ไม่ตรงกับ path ที่ Flutter pack ไฟล์จริง จะเกิด error เช่น:

```text
Tesseract file not found
traineddata not found
failed to initialize Tesseract
```

`thai_native_ocr` แก้ปัญหาที่ต้นเหตุด้วยการ **ไม่ใช้ Tesseract บน iOS เลย**

ดังนั้น iOS จะไม่มี:

- Tesseract pod
- Tesseract import
- `tessdata` ใน podspec
- path lookup ของ Tesseract

Vision เป็น framework ที่มากับ iOS จึงไม่ต้องจัดการ OCR model file เอง

### 5. การทำงานบน Android

ไฟล์หลักคือ:

```text
android/src/main/kotlin/com/example/thai_native_ocr/ThaiNativeOcrPlugin.kt
```

Android ใช้ `tess-two:9.1.0` และ `tessdata_best`

model อยู่เฉพาะ Android:

```text
android/src/main/assets/tessdata/eng.traineddata
android/src/main/assets/tessdata/tha.traineddata
```

เมื่อใช้งานครั้งแรก plugin จะ copy model ไปที่:

```text
context.filesDir/tessdata/
```

เพราะ tess-two ต้องการ path บน filesystem สำหรับ `TessBaseAPI.init()`

Stage 1 ใช้ English OCR แบบเบาเพื่อสร้าง detector signal แล้วตรวจ Thai regex

Stage 2:

```text
พบภาษาไทย    -> tha+eng + PSM_AUTO
ไม่พบภาษาไทย -> eng + PSM_AUTO
```

เราไม่บังคับใช้ `AUTO_OSD` เพราะต้องเพิ่ม `osd.traineddata` อีกไฟล์หนึ่ง ซึ่งไม่จำเป็นกับ architecture ปัจจุบัน

### 6. `autoDetectThai` กับ `forceLanguage`

กรณีทั่วไป:

```dart
ThaiNativeOcr.recognize(imagePath)
```

ระบบจะทำ Stage 1 + Stage 2 อัตโนมัติ

ถ้ารู้อยู่แล้วว่าเอกสารอาจมีทั้งไทยและอังกฤษ:

```dart
ThaiNativeOcr.recognize(
  imagePath,
  autoDetectThai: false,
)
```

จะข้าม Stage 1 แล้วเข้า bilingual accurate OCR ทันที

ถ้าต้องการบังคับภาษา:

```dart
ThaiNativeOcr.recognize(imagePath, forceLanguage: 'th');
ThaiNativeOcr.recognize(imagePath, forceLanguage: 'en');
ThaiNativeOcr.recognize(imagePath, forceLanguage: 'mixed');
```

`forceLanguage` มี priority สูงกว่า `autoDetectThai`

### 7. ความหมายของผลลัพธ์

`ThaiOcrResult.text` คือข้อความจาก accurate OCR pass

`containsThai` บอกว่าพบอักษรไทยจาก detector หรือผล OCR สุดท้ายหรือไม่

`detectedLanguage` ถูก normalize เป็น:

```text
th
en
mixed
```

`confidence` อยู่ในช่วง `0.0..1.0` เพื่อให้ iOS และ Android ใช้ contract เดียวกัน

### 8. จุดที่ควรพัฒนาต่อ

งานต่อยอดที่เหมาะสมคือ:

- native Android build CI
- native iOS build CI
- fixture tests สำหรับภาพไทย / อังกฤษ / mixed
- benchmark เวลา Stage 1 และ Stage 2 บนเครื่องจริง
- test ชุดหมุนภาพ, ภาพเบลอ, ตัวอักษรเล็ก และแสงไม่สม่ำเสมอ

Dart unit test อย่างเดียวไม่สามารถยืนยันพฤติกรรมของ Vision และ Tesseract บนเครื่องจริงได้ จึงควรมี native build validation และ physical-device evidence เพิ่มในระยะถัดไป
