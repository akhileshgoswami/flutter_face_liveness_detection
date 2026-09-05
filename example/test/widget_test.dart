import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_face_liveness_detection_example/main.dart';

void main() {
  testWidgets('Home page shows the verify button', (WidgetTester tester) async {
    await tester.pumpWidget(const DemoApp());

    expect(find.text('Verify face'), findsOneWidget);
    expect(find.text('Liveness demo'), findsWidgets);
  });
}
