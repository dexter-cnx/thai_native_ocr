import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:thai_native_ocr/thai_native_ocr.dart';

void main() {
  runApp(const ThaiNativeOcrExampleApp());
}

class ThaiNativeOcrExampleApp extends StatelessWidget {
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

class OcrPage extends StatefulWidget {
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  final _picker = ImagePicker();
  ThaiOcrResult? _result;
  bool _busy = false;
  String? _error;

  Future<void> _pickAndRecognize() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await ThaiNativeOcr.recognize(image.path);
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
    return Scaffold(
      appBar: AppBar(title: const Text('thai_native_ocr example')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _pickAndRecognize,
            icon: const Icon(Icons.image_search),
            label: Text(_busy ? 'Recognizing…' : 'Pick image and recognize'),
          ),
          const SizedBox(height: 24),
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?) ...[
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_result case final result?) ...[
            Text('containsThai: ${result.containsThai}'),
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
