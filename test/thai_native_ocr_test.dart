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

  test('recognize maps native result', () async {
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

    final result = await ThaiNativeOcr.recognize('/tmp/image.jpg');

    expect(captured?.method, 'recognize');
    expect(captured?.arguments, <String, Object?>{
      'imagePath': '/tmp/image.jpg',
      'autoDetectThai': true,
      'forceLanguage': null,
    });
    expect(result.text, 'สวัสดี Hello');
    expect(result.containsThai, isTrue);
    expect(result.detectedLanguage, 'mixed');
    expect(result.confidence, 0.91);
  });

  test('forceLanguage is forwarded and bypass validation is strict', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments, <String, Object?>{
        'imagePath': '/tmp/image.jpg',
        'autoDetectThai': true,
        'forceLanguage': 'th',
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

  test('empty imagePath is rejected before channel invocation', () {
    expect(() => ThaiNativeOcr.recognize(''), throwsArgumentError);
  });
}
