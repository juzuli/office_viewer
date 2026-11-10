import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_lok/office_viewer_engine_lok.dart';
import 'package:office_viewer_engine_pdf/office_viewer_engine_pdf.dart';

import 'leafpane_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final registry = OfficeEngineRegistry.instance..clear();
  // PDF first (pdfrx) so LOK never opens PDFs.
  if (!kIsWeb) {
    registry.register(PdfOfficeEngine());
  }
  final useLok = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (useLok) {
    registry.register(LokOfficeEngine());
  } else {
    registry.register(FakeOfficeEngine(partCount: 3, kind: PartKind.page));
  }
  runApp(const OfficeViewerExampleApp());
}

class OfficeViewerExampleApp extends StatelessWidget {
  const OfficeViewerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leafpane',
      debugShowCheckedModeBanner: false,
      theme: leafpaneTheme(),
      home: const ViewerPage(),
    );
  }
}

enum _SampleDoc { docx, largeSheet, deck, pdf }

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  late final OfficeDocumentController _controller;
  _SampleDoc _doc = _SampleDoc.docx;
  String? _pickedFileName;
  String? _status;
  bool _busy = false;

  static const _officeExtensions = [
    'docx',
    'doc',
    'odt',
    'rtf',
    'xlsx',
    'xls',
    'ods',
    'csv',
    'pptx',
    'ppt',
    'odp',
    'pdf',
  ];

  @override
  void initState() {
    super.initState();
    _controller = OfficeDocumentController();
    _controller.addListener(_onController);
    _status = 'Getting ready…';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _status = 'Opening sample…');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      try {
        await _openSelected();
      } catch (e, st) {
        debugPrint('Open failed: $e\n$st');
        if (mounted) {
          setState(() => _status = 'Couldn’t open this file');
        }
      }
    });
  }

  void _onController() {
    if (!mounted) return;
    setState(() {
      switch (_controller.state) {
        case OfficeLoadState.loading:
          _busy = true;
          _status ??= 'Opening…';
        case OfficeLoadState.ready:
          _busy = false;
          _status = null;
        case OfficeLoadState.failed:
          _busy = false;
          _status = _controller.error?.message ?? 'Couldn’t open this file';
        case OfficeLoadState.idle:
          _busy = false;
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _controller.dispose();
    super.dispose();
  }

  String _fileNameFor(_SampleDoc doc) => switch (doc) {
        _SampleDoc.docx => 'sample.docx',
        _SampleDoc.largeSheet => 'large_sheet.xlsx',
        _SampleDoc.deck => 'sample_deck.pptx',
        _SampleDoc.pdf => 'sample.pdf',
      };

  String _labelFor(_SampleDoc doc) => switch (doc) {
        _SampleDoc.docx => 'Word',
        _SampleDoc.largeSheet => 'Excel',
        _SampleDoc.deck => 'PowerPoint',
        _SampleDoc.pdf => 'PDF',
      };

  String _assetFor(_SampleDoc doc) => 'assets/${_fileNameFor(doc)}';

  String get _displayName => _pickedFileName ?? _fileNameFor(_doc);

  Future<void> _openBytes(
    Uint8List bytes,
    String fileName, {
    String? password,
  }) async {
    setState(() {
      _busy = true;
      _status = 'Opening…';
    });
    await _controller.load(
      DocumentSource.bytes(bytes, fileName: fileName),
      options: OpenOptions(password: password),
    );
    if (_controller.state == OfficeLoadState.ready) {
      if (mounted) setState(() => _status = null);
      return;
    }

    final err = _controller.error;
    if (err is PasswordRequiredError && mounted) {
      final entered = await _askPassword(
        fileName: fileName,
        wrongPassword: password != null,
      );
      if (entered == null) {
        setState(() => _status = 'Password needed to view this file');
        return;
      }
      await _openBytes(bytes, fileName, password: entered);
      return;
    }

    if (mounted) {
      setState(() => _status = err?.message ?? 'Couldn’t open this file');
    }
  }

  Future<String?> _askPassword({
    required String fileName,
    bool wrongPassword = false,
  }) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PasswordUnlockDialog(
        fileName: fileName,
        wrongPassword: wrongPassword,
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  Future<void> _openSelected() async {
    setState(() => _pickedFileName = null);
    final bytes = Uint8List.sublistView(await rootBundle.load(_assetFor(_doc)));
    await _openBytes(bytes, _fileNameFor(_doc));
  }

  Future<void> _pickAndOpen() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _officeExtensions,
      dialogTitle: 'Choose a file to view',
    );
    if (file == null) return;

    setState(() {
      _pickedFileName = file.name;
      _status = 'Opening…';
    });
    try {
      final bytes = await file.readAsBytes();
      await _openBytes(bytes, file.name);
    } catch (e) {
      setState(() => _status = 'Couldn’t open this file');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: LeafpaneColors.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leafpane',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              _displayName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: LeafpaneColors.inkMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open file',
            onPressed: _busy ? null : _pickAndOpen,
            icon: const Icon(Icons.upload_file_outlined),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              return Row(
                children: [
                  IconButton(
                    tooltip: 'Zoom out',
                    onPressed: _controller.state == OfficeLoadState.ready
                        ? () =>
                            _controller.setZoom(_controller.tileZoom - 0.25)
                        : null,
                    icon: const Icon(Icons.zoom_out),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(_controller.zoom * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zoom in',
                    onPressed: _controller.state == OfficeLoadState.ready
                        ? () =>
                            _controller.setZoom(_controller.tileZoom + 0.25)
                        : null,
                    icon: const Icon(Icons.zoom_in),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _Toolbar(
            doc: _doc,
            picked: _pickedFileName != null,
            busy: _busy,
            onDocChanged: (d) {
              setState(() => _doc = d);
              _openSelected();
            },
            labelFor: _labelFor,
          ),
          if (_status != null)
            Material(
              color: LeafpaneColors.surfaceRaised,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    if (_busy) ...[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        _status!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _controller.state == OfficeLoadState.failed
                              ? theme.colorScheme.error
                              : LeafpaneColors.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ColoredBox(
              color: LeafpaneColors.canvas,
              child: OfficeDocumentView(controller: _controller),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.state != OfficeLoadState.ready) {
            return const SizedBox.shrink();
          }
          final parts = _controller.parts;
          if (parts.length <= 1) return const SizedBox.shrink();
          return Material(
            elevation: 2,
            color: LeafpaneColors.surfaceCard,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      '${_controller.currentPart + 1} of ${parts.length}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: LeafpaneColors.inkMuted,
                      ),
                    ),
                    const Spacer(),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _controller.currentPart
                            .clamp(0, parts.length - 1),
                        items: [
                          for (final p in parts)
                            DropdownMenuItem(
                              value: p.index,
                              child: Text(p.name ?? 'Page ${p.index + 1}'),
                            ),
                        ],
                        onChanged: (i) {
                          if (i != null) _controller.goToPart(i);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.doc,
    required this.picked,
    required this.busy,
    required this.onDocChanged,
    required this.labelFor,
  });

  final _SampleDoc doc;
  final bool picked;
  final bool busy;
  final ValueChanged<_SampleDoc> onDocChanged;
  final String Function(_SampleDoc) labelFor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LeafpaneColors.surfaceCard,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_SampleDoc>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              for (final d in _SampleDoc.values)
                ButtonSegment(
                  value: d,
                  label: Text(labelFor(d)),
                  enabled: !busy,
                ),
            ],
            selected: picked ? <_SampleDoc>{} : {doc},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) onDocChanged(s.first);
            },
          ),
        ),
      ),
    );
  }
}

class _PasswordUnlockDialog extends StatefulWidget {
  const _PasswordUnlockDialog({
    required this.fileName,
    required this.wrongPassword,
  });

  final String fileName;
  final bool wrongPassword;

  @override
  State<_PasswordUnlockDialog> createState() => _PasswordUnlockDialogState();
}

class _PasswordUnlockDialogState extends State<_PasswordUnlockDialog> {
  late final TextEditingController _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _field.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.wrongPassword ? 'Try another password' : 'This file is locked',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.wrongPassword
                ? 'That password didn’t open “${widget.fileName}”. Try again.'
                : '“${widget.fileName}” needs a password before you can view it.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _field,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('View file'),
        ),
      ],
    );
  }
}
