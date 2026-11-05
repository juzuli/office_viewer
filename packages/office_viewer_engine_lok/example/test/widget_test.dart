import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer_engine_lok_example/main.dart' as app;

void main() {
  testWidgets('placeholder app loads', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.textContaining('Use ../../example'), findsOneWidget);
  });
}
