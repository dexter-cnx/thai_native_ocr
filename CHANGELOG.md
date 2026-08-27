## 0.2.0

- Added `ThaiNativeOcr.recognizeBytes(Uint8List)` for in-memory OCR.
- Added `ThaiNativeOcr.recognizeFile(File)` convenience API.
- Added optional `preprocess` OCR image enhancement.
- Hardened Android Thai detection with a downscaled bilingual `tha+eng` detector pass using `PSM_SPARSE_TEXT`.
- Switched Android from legacy `tess-two` to Tesseract4Android 4.9.0 / Tesseract 5.5.1.
- Switched bundled Android language models from `tessdata_best` to smaller `tessdata_fast` models.
- Kept only two accurate OCR execution modes: Thai + English and English-only.
- Improved the example app and native build validation for Android and iOS.

## 0.1.0

- Initial hybrid OCR implementation.
- Apple Vision-only OCR on iOS with two-stage Thai auto-detection.
- Tesseract OCR on Android with bundled Thai and English models.
- Added `autoDetectThai` and `forceLanguage` controls.
- Added `containsThai`, detected language, and normalized confidence result fields.
- Added `image_picker` example app.
