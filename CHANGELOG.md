## 0.1.0

- Initial hybrid OCR implementation.
- Apple Vision-only OCR on iOS with two-stage Thai auto-detection.
- Tesseract `tess-two` OCR on Android with bundled Thai and English `tessdata_best` models.
- Added `autoDetectThai` and `forceLanguage` controls.
- Added `containsThai`, detected language, and normalized confidence result fields.
- Added `image_picker` example app.
