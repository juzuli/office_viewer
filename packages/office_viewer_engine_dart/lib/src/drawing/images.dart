import 'dart:typed_data';
import 'dart:ui' as ui;

import '../paint/cache.dart';

/// Decodes embedded image parts with LRU caching.
class OfficeImageDecoder {
  OfficeImageDecoder({DecodedImageCache? cache})
      : _cache = cache ?? DecodedImageCache(maxBytes: 64 << 20);

  final DecodedImageCache _cache;

  DecodedImageCache get cache => _cache;

  Future<ui.Image?> decode(String cacheKey, Uint8List bytes) async {
    final cached = _cache.get(cacheKey);
    if (cached != null) return cached;

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      _cache.put(cacheKey, image);
      return image;
    } catch (_) {
      return null;
    }
  }

  ui.Image? getCached(String cacheKey) => _cache.get(cacheKey);

  void clear() => _cache.clear();
}
