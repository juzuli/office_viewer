import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Compound File Binary (OLE / legacy Office) magic.
bool isCfbHeader(Uint8List head) {
  if (head.length < 8) return false;
  return head[0] == 0xD0 &&
      head[1] == 0xCF &&
      head[2] == 0x11 &&
      head[3] == 0xE0 &&
      head[4] == 0xA1 &&
      head[5] == 0xB1 &&
      head[6] == 0x1A &&
      head[7] == 0xE1;
}

bool _isZipLocalHeader(Uint8List head) {
  if (head.length < 4) return false;
  return head[0] == 0x50 && head[1] == 0x4B;
}

/// True when the package is OLE-only (legacy .doc/.xls/.ppt), not OOXML zip.
bool isLegacyOlePackage(Uint8List bytes) =>
    bytes.isNotEmpty && isCfbHeader(bytes) && !_isZipLocalHeader(bytes);

/// Encrypted OOXML stores `EncryptionInfo` + `EncryptedPackage` at zip root.
class EncryptionDetection {
  const EncryptionDetection({
    required this.encrypted,
    required this.legacyOle,
  });

  final bool encrypted;
  final bool legacyOle;
}

EncryptionDetection detectEncryption(Uint8List bytes) {
  if (bytes.isEmpty) {
    return const EncryptionDetection(encrypted: false, legacyOle: false);
  }
  if (isLegacyOlePackage(bytes)) {
    return const EncryptionDetection(encrypted: false, legacyOle: true);
  }
  if (!_isZipLocalHeader(bytes)) {
    return const EncryptionDetection(encrypted: false, legacyOle: false);
  }
  try {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    var hasInfo = false;
    var hasPackage = false;
    for (final f in archive) {
      final name = f.name.replaceAll('\\', '/').toLowerCase();
      if (name == 'encryptioninfo' || name.endsWith('/encryptioninfo')) {
        hasInfo = true;
      }
      if (name == 'encryptedpackage' || name.endsWith('/encryptedpackage')) {
        hasPackage = true;
      }
    }
    if (hasInfo || hasPackage) {
      return const EncryptionDetection(encrypted: true, legacyOle: false);
    }
  } catch (_) {
    // Not a decryptable zip; open path will classify as corrupt.
  }
  return const EncryptionDetection(encrypted: false, legacyOle: false);
}
