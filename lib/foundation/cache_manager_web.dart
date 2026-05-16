import 'dart:typed_data';

class _CacheEntry {
  final Uint8List data;
  final int expiresAt;

  _CacheEntry(this.data, this.expiresAt);

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
}

class _MemoryCacheFile {
  final Uint8List _data;
  _MemoryCacheFile(this._data);
  Future<Uint8List> readAsBytes() async => _data;
}

class CacheManager {
  static CacheManager? instance;
  static const int _maxCacheBytes = 100 * 1024 * 1024;

  final _cache = <String, _CacheEntry>{};
  int _currentBytes = 0;

  factory CacheManager() => instance ??= CacheManager._();
  CacheManager._();

  int get currentSize => _currentBytes;

  void setLimitSize(int size) {}

  Future<void> writeCache(
    String key,
    List<int> data, [
    int duration = 7 * 24 * 60 * 60 * 1000,
  ]) async {
    if (data.isEmpty) return;
    await delete(key);
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final expiresAt = DateTime.now().millisecondsSinceEpoch + duration;
    _cache[key] = _CacheEntry(bytes, expiresAt);
    _currentBytes += bytes.length;
    _evictIfNeeded();
  }

  Future<dynamic> findCache(String key) async {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      _currentBytes -= entry.data.length;
      return null;
    }
    return _MemoryCacheFile(entry.data);
  }

  void checkCacheIfRequired() {}

  Future<void> checkCache() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = <String>[];
    for (final entry in _cache.entries) {
      if (entry.value.expiresAt < now) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _currentBytes -= _cache[key]!.data.length;
      _cache.remove(key);
    }
  }

  Future<void> delete(String key) async {
    final entry = _cache.remove(key);
    if (entry != null) {
      _currentBytes -= entry.data.length;
    }
  }

  Future<void> clear() async {
    _cache.clear();
    _currentBytes = 0;
  }

  void _evictIfNeeded() {
    while (_currentBytes > _maxCacheBytes && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      _currentBytes -= _cache[oldest]!.data.length;
      _cache.remove(oldest);
    }
  }
}