import 'dart:typed_data';

/// Where a document comes from. Engines copy what they need into a private
/// workspace so revoked URI permissions cannot break an open document.
sealed class DocumentSource {
  const DocumentSource({this.fileName});
  final String? fileName;

  const factory DocumentSource.file(String path) = FileSource;
  const factory DocumentSource.bytes(Uint8List bytes, {String? fileName}) =
      BytesSource;
}

class FileSource extends DocumentSource {
  const FileSource(this.path) : super(fileName: path);
  final String path;
}

class BytesSource extends DocumentSource {
  const BytesSource(this.bytes, {super.fileName});
  final Uint8List bytes;
}
