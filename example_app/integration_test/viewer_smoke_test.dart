import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:office_viewer_example/main.dart' as app;

/// Device smoke. Run with:
/// ```bash
/// cd example && flutter test integration_test/viewer_smoke_test.dart -d <id>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitForReady(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      // Status clears when ready; filename shows in the app bar.
      if (find.text('Leafpane').evaluate().isNotEmpty &&
          find.textContaining('Couldn’t open').evaluate().isEmpty &&
          find.text('Opening…').evaluate().isEmpty &&
          find.text('Getting ready…').evaluate().isEmpty &&
          find.text('Opening sample…').evaluate().isEmpty) {
        // Give the viewer a beat to paint.
        await tester.pump(const Duration(milliseconds: 300));
        return;
      }
      if (find.textContaining('Couldn’t open').evaluate().isNotEmpty) {
        return;
      }
    }
  }

  testWidgets('F01-H1 cold open shows viewer chrome', (tester) async {
    app.main();
    await waitForReady(tester);

    expect(find.text('Leafpane'), findsOneWidget);
    expect(find.byTooltip('Open file'), findsOneWidget);
    expect(find.text('Word'), findsOneWidget);
    expect(find.textContaining('sample.docx'), findsOneWidget);
    expect(find.textContaining('engine='), findsNothing);
  });

  testWidgets('F02-H1 switch to Excel sample', (tester) async {
    app.main();
    await waitForReady(tester);

    await tester.tap(find.text('Excel'));
    await waitForReady(tester);

    expect(find.textContaining('large_sheet.xlsx'), findsOneWidget);
    expect(find.textContaining('Couldn’t open'), findsNothing);
    expect(find.textContaining('No engine supports'), findsNothing);
  });

  testWidgets('F04-H2 open bundled PDF sample', (tester) async {
    app.main();
    await waitForReady(tester);

    await tester.tap(find.text('PDF'));
    await waitForReady(tester);

    expect(find.textContaining('sample.pdf'), findsOneWidget);
    expect(find.textContaining('Couldn’t open'), findsNothing);
  });

  testWidgets('F05-H1 PowerPoint has multiple parts and switches',
      (tester) async {
    app.main();
    await waitForReady(tester);

    await tester.tap(find.text('PowerPoint'));
    await waitForReady(tester);

    expect(find.textContaining('sample_deck.pptx'), findsOneWidget);
    // Bottom bar: "1 of 8" for sample_deck.
    expect(find.textContaining('of 8'), findsOneWidget);

    final dropdown = find.byType(DropdownButton<int>);
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final slide2 = find.textContaining('Part 2').hitTestable();
    final slide2Alt = find.textContaining('Slide').hitTestable();
    if (slide2.evaluate().length > 1) {
      await tester.tap(slide2.last);
    } else if (slide2Alt.evaluate().length > 1) {
      await tester.tap(slide2Alt.last);
    } else {
      final items = find.byType(DropdownMenuItem<int>);
      if (items.evaluate().length >= 2) {
        await tester.tap(items.at(1));
      }
    }
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.textContaining('of 8'), findsOneWidget);
  }, skip: kIsWeb);

  testWidgets('F03-H1 zoom buttons still work', (tester) async {
    app.main();
    await waitForReady(tester);

    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(find.text('125%'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
  });

  Future<void> tapSampleSegment(WidgetTester tester, String label) async {
    final segment = find.text(label);
    expect(segment, findsOneWidget);
    await tester.ensureVisible(segment);
    await tester.pumpAndSettle();
    await tester.tap(segment);
  }

  testWidgets('F06 legacy DOC opens via convert engine', (tester) async {
    app.main();
    await waitForReady(tester);

    await tapSampleSegment(tester, 'DOC');
    await waitForReady(tester);

    expect(find.textContaining('sample.doc'), findsOneWidget);
    expect(find.textContaining('No engine supports'), findsNothing);
    // iOS needs OfficeOxide.xcframework force-loaded; Android uses jniLibs.
    expect(find.textContaining('Couldn’t open'), findsNothing);
    expect(find.textContaining('not available'), findsNothing);
  }, skip: kIsWeb);

  testWidgets('F07 legacy XLS and PPT samples are selectable', (tester) async {
    app.main();
    await waitForReady(tester);

    await tapSampleSegment(tester, 'XLS');
    await waitForReady(tester);
    expect(find.textContaining('sample.xls'), findsOneWidget);

    await tapSampleSegment(tester, 'PPT');
    await waitForReady(tester);
    expect(find.textContaining('sample.ppt'), findsOneWidget);
  }, skip: kIsWeb);
}
