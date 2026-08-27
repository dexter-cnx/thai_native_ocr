import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_native_ocr/thai_native_ocr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('thai_native_ocr');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('recognize maps native result and forwards preprocess', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return <String, Object?>{
        'text': 'สวัสดี Hello',
        'containsThai': true,
        'detectedLanguage': 'mixed',
        'confidence': 0.91,
      };
    });

    final result = await ThaiNativeOcr.recognize(
      '/tmp/image.jpg',
      preprocess: true,
    );

    expect(captured?.method, 'recognize');
    expect(captured?.arguments, <String, Object?>{
      'imagePath': '/tmp/image.jpg',
      'autoDetectThai': true,
      'forceLanguage': null,
      'preprocess': true,
    });
    expect(result.text, 'สวัสดี Hello');
    expect(result.containsThai, isTrue);
    expect(result.detectedLanguage, 'mixed');
    expect(result.confidence, 0.91);
  });

  test('recognizeFile forwards file path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments, <String, Object?>{
        'imagePath': '/tmp/file.jpg',
        'autoDetectThai': true,
        'forceLanguage': null,
        'preprocess': false,
      });
      return <String, Object?>{
        'text': 'Hello',
        'containsThai': false,
        'detectedLanguage': 'en',
        'confidence': 0.8,
      };
    });

    final result = await ThaiNativeOcr.recognizeFile(File('/tmp/file.jpg'));
    expect(result.detectedLanguage, 'en');
  });

  test('recognizeBytes forwards Uint8List without a path', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments['imagePath'], isNull);
      expect(arguments['imageBytes'], bytes);
      expect(arguments['preprocess'], isFalse);
      return <String, Object?>{
        'text': 'ภาษาไทย',
        'containsThai': true,
        'detectedLanguage': 'th',
        'confidence': 0.9,
      };
    });

    final result = await ThaiNativeOcr.recognizeBytes(bytes);
    expect(result.containsThai, isTrue);
  });

  test('forceLanguage is forwarded and validation is strict', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments, <String, Object?>{
        'imagePath': '/tmp/image.jpg',
        'autoDetectThai': true,
        'forceLanguage': 'th',
        'preprocess': false,
      });
      return <String, Object?>{
        'text': 'ภาษาไทย',
        'containsThai': true,
        'detectedLanguage': 'th',
        'confidence': 1.0,
      };
    });

    final result = await ThaiNativeOcr.recognize(
      '/tmp/image.jpg',
      forceLanguage: 'th',
    );
    expect(result.detectedLanguage, 'th');

    expect(
      () => ThaiNativeOcr.recognize('/tmp/image.jpg', forceLanguage: 'jp'),
      throwsArgumentError,
    );
  });

  test('empty inputs are rejected before channel invocation', () {
    expect(() => ThaiNativeOcr.recognize(''), throwsArgumentError);
    expect(
      () => ThaiNativeOcr.recognizeBytes(Uint8List(0)),
      throwsArgumentError,
    );
  });
}
