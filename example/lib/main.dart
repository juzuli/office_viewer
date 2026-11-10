import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_pdf/office_viewer_engine_pdf.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OfficeEngineRegistry.instance
    ..clear()
    ..register(PdfOfficeEngine());
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PdfExamplePage(),
    );
  }
}

/// Loads the bundled sample PDF and shows [OfficeDocumentView].
class PdfExamplePage extends StatefulWidget {
  const PdfExamplePage({super.key});

  @override
  State<PdfExamplePage> createState() => _PdfExamplePageState();
}

class _PdfExamplePageState extends State<PdfExamplePage> {
  late final OfficeDocumentController _controller = OfficeDocumentController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _open();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open({String? password}) async {
    final data = await rootBundle.load('assets/sample.pdf');
    await _controller.load(
      DocumentSource.bytes(
        data.buffer.asUint8List(),
        fileName: 'sample.pdf',
      ),
      options: OpenOptions(password: password),
    );
    if (_controller.error is PasswordRequiredError && mounted) {
      // Sample is not encrypted; shown so hosts can copy the pattern.
      debugPrint('Password required: ${_controller.error}');
    }
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
      appBar: AppBar(title: const Text('office_viewer PDF example')),
      body: switch (_controller.state) {
        OfficeLoadState.idle || OfficeLoadState.loading => const Center(
            child: CircularProgressIndicator(),
          ),
        OfficeLoadState.failed => Center(
            child: Text(_controller.error?.message ?? 'Could not open file'),
          ),
        OfficeLoadState.ready => OfficeDocumentView(controller: _controller),
      },
    );
  }
}
