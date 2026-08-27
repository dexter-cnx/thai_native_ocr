import 'package:flutter_test/flutter_test.dart';
import 'package:thai_native_ocr_example/main.dart';

void main() {
  testWidgets('renders OCR example shell', (tester) async {
    await tester.pumpWidget(const ThaiNativeOcrExampleApp());

    expect(find.text('thai_native_ocr example'), findsOneWidget);
    expect(find.text('Pick image and recognize'), findsOneWidget);
  });
}
