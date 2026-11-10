import 'dart:ui';

import '../model/display_list.dart';

/// Simple byte-budget LRU cache.
class LruByteCache<K> {
  LruByteCache({required this.maxBytes});

  final int maxBytes;
  final _map = <K, _Entry>{};
  int _used = 0;

  V? get<V>(K key) {
    final e = _map.remove(key);
    if (e == null) return null;
    _map[key] = e;
    return e.value as V;
  }

  void put(K key, Object value, int bytes) {
    if (bytes > maxBytes) return;
    _removeKey(key);
    while (_used + bytes > maxBytes && _map.isNotEmpty) {
      final first = _map.keys.first;
      _removeKey(first);
    }
    _map[key] = _Entry(value, bytes);
    _used += bytes;
  }

  void _removeKey(K key) {
    final old = _map.remove(key);
    if (old != null) _used -= old.bytes;
  }

  void clear() {
    _map.clear();
    _used = 0;
  }
}

class _Entry {
  _Entry(this.value, this.bytes);
  final Object value;
  final int bytes;
}

class DisplayListCache {
  DisplayListCache({required int maxBytes}) : _cache = LruByteCache(maxBytes: maxBytes);

  final LruByteCache<int> _cache;

  DisplayList? get(int partIndex) => _cache.get(partIndex);

  void put(int partIndex, DisplayList list) {
    final est = (list.size.width * list.size.height * 4).round();
    _cache.put(partIndex, list, est.clamp(1, 1 << 30));
  }

  void clear() => _cache.clear();
}

/// LRU for decoded [Image] bitmaps (named to avoid Flutter's painting.ImageCache).
class DecodedImageCache {
  DecodedImageCache({required int maxBytes})
      : _cache = LruByteCache<String>(maxBytes: maxBytes);

  final LruByteCache<String> _cache;

  Image? get(String key) => _cache.get(key);

  void put(String key, Image image) {
    final bytes = image.width * image.height * 4;
    _cache.put(key, image, bytes);
  }

  void clear() => _cache.clear();
}

@Deprecated('Use DecodedImageCache')
typedef ImageCache = DecodedImageCache;
