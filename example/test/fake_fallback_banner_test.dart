import 'package:flutter_test/flutter_test.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_example/main.dart';

void main() {
  setUp(() {
    OfficeEngineRegistry.instance
      ..clear()
      ..register(FakeOfficeEngine(partCount: 1, kind: PartKind.page));
  });

  tearDown(() {
    OfficeEngineRegistry.instance.clear();
  });

  testWidgets('example shows Leafpane chrome and opens a sample', (tester) async {
    await tester.pumpWidget(const OfficeViewerExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Leafpane'), findsOneWidget);
    expect(find.byTooltip('Open file'), findsOneWidget);
    expect(find.text('Word'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    // Dev metrics must not appear on the user-facing example.
    expect(find.textContaining('engine='), findsNothing);
    expect(find.textContaining('Bench'), findsNothing);
    expect(find.textContaining('firstTile'), findsNothing);
  });
}
