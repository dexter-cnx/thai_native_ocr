import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:thai_native_ocr/thai_native_ocr.dart';

void main() {
  runApp(const ThaiNativeOcrExampleApp());
}

/// Camera/gallery example for `thai_native_ocr`.
class ThaiNativeOcrExampleApp extends StatelessWidget {
  /// Creates the example application.
  const ThaiNativeOcrExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'thai_native_ocr',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const OcrPage(),
    );
  }
}

/// Page that captures or picks an image and displays OCR output.
class OcrPage extends StatefulWidget {
  /// Creates the OCR example page.
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  final _picker = ImagePicker();
  ThaiOcrResult? _result;
  bool _busy = false;
  bool _preprocess = true;
  String? _error;

  Future<void> _pickAndRecognize(ImageSource source) async {
    final image = await _picker.pickImage(source: source, imageQuality: 95);
    if (image == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await ThaiNativeOcr.recognizeFile(
        File(image.path),
        preprocess: _preprocess,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('thai_native_ocr example')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed:
                    _busy ? null : () => _pickAndRecognize(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take photo'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => _pickAndRecognize(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Pick image'),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('OCR preprocessing'),
            subtitle: const Text('Grayscale / contrast / adaptive threshold'),
            value: _preprocess,
            onChanged:
                _busy ? null : (value) => setState(() => _preprocess = value),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?) ...[
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (result != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                backgroundColor:
                    result.containsThai ? Colors.green.shade50 : null,
                side: result.containsThai
                    ? BorderSide(color: Colors.green.shade300)
                    : null,
                avatar: Icon(
                  result.containsThai ? Icons.check_circle : Icons.language,
                  size: 18,
                  color: result.containsThai ? Colors.green.shade700 : null,
                ),
                label: Text(
                  result.containsThai ? 'Thai detected' : 'English only',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('detectedLanguage: ${result.detectedLanguage}'),
            Text('confidence: ${result.confidence.toStringAsFixed(3)}'),
            const Divider(height: 32),
            SelectableText(result.text),
          ],
        ],
      ),
    );
  }
}
