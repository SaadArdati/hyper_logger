import 'dart:collection';

/// A simple least-recently-used cache with a fixed [maxSize].
///
/// Backed by a [LinkedHashMap] in insertion order. On a cache hit,
/// the entry is moved to the tail (most-recent). When the cache
/// exceeds [maxSize], the head (least-recent) entry is evicted.
class LruCache<K, V> {
  LruCache(this.maxSize) : assert(maxSize > 0);

  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  /// Returns the cached value for [key], promoting it to most-recent.
  /// If [key] is absent, inserts the result of [ifAbsent] and evicts
  /// the least-recently-used entry when the cache is full.
  V putIfAbsent(K key, V Function() ifAbsent) {
    if (_map.containsKey(key)) {
      final value = _map.remove(key) as V;
      _map[key] = value;
      return value;
    }
    final value = ifAbsent();
    _map[key] = value;
    if (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
    return value;
  }

  void clear() => _map.clear();
}
