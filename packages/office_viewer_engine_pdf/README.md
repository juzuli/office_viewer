# office_viewer_engine_pdf

PDFium-backed PDF engine for [`office_viewer`](https://pub.dev/packages/office_viewer)
via [pdfrx](https://pub.dev/packages/pdfrx).

## Install

```bash
flutter pub add office_viewer office_viewer_engine_pdf
```

```dart
import 'package:office_viewer/office_viewer.dart';
import 'package:office_viewer_engine_pdf/office_viewer_engine_pdf.dart';

OfficeEngineRegistry.instance.register(PdfOfficeEngine());

final controller = OfficeDocumentController();
await controller.load(DocumentSource.bytes(bytes, fileName: 'a.pdf'));
OfficeDocumentView(controller: controller);
```

Register this engine **before** any Office/LOK engine so PDFs never hit the
native Office stack.

Supports `OfficeFormat.pdf` on **Android and iOS** only.
