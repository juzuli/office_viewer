import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_convert/office_viewer_engine_convert.dart';
import 'package:office_viewer_engine_dart/office_viewer_engine_dart.dart';
import 'package:office_viewer_engine_pdf/office_viewer_engine_pdf.dart';

/// Set false (or omit the convert dependency) if you only need PDF / OOXML.
const bool kRegisterConvertEngine = true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final registry = OfficeEngineRegistry.instance..clear();
  // PDF → Convert (optional DOC/XLS/PPT) → Dart OOXML.
  registry.register(PdfOfficeEngine());
  if (kRegisterConvertEngine && !kIsWeb) {
    registry.register(ConvertOfficeEngine());
  }
  if (!kIsWeb) {
    registry.register(DartOfficeEngine());
  }
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ViewerExamplePage(),
    );
  }
}

enum _Sample {
  pdf('sample.pdf', 'PDF'),
  docx('sample.docx', 'DOCX'),
  xlsx('large_sheet.xlsx', 'XLSX'),
  pptx('sample_deck.pptx', 'PPTX'),
  doc('sample.doc', 'DOC (convert)');

  const _Sample(this.asset, this.label);
  final String asset;
  final String label;
}

class ViewerExamplePage extends StatefulWidget {
  const ViewerExamplePage({super.key});

  @override
  State<ViewerExamplePage> createState() => _ViewerExamplePageState();
}

class _ViewerExamplePageState extends State<ViewerExamplePage> {
  late final OfficeDocumentController _controller = OfficeDocumentController();
  _Sample _sample = _Sample.pdf;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _open();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    final data = await rootBundle.load('assets/${_sample.asset}');
    await _controller.load(
      DocumentSource.bytes(
        data.buffer.asUint8List(),
        fileName: _sample.asset,
      ),
    );
  }

  Future<void> _select(_Sample sample) async {
    if (sample == _sample) return;
    setState(() => _sample = sample);
    await _open();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('office_viewer example'),
        actions: [
          PopupMenuButton<_Sample>(
            initialValue: _sample,
            onSelected: _select,
            itemBuilder: (context) => [
              for (final s in _Sample.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
        ],
      ),
      body: switch (_controller.state) {
        OfficeLoadState.idle || OfficeLoadState.loading => const Center(
            child: CircularProgressIndicator(),
          ),
        OfficeLoadState.failed => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _controller.error?.message ?? 'Could not open file',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        OfficeLoadState.ready => OfficeDocumentView(controller: _controller),
      },
    );
  }
}
