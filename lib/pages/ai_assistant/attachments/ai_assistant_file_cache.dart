import 'dart:typed_data';

/// Bounds page-owned AI previews without retaining arbitrarily large downloads.
bool cacheAiAssistantFile(
    Map<String, Uint8List> cache, String id, Uint8List bytes) {
  const budget = 32 * 1024 * 1024;
  if (bytes.length > budget) return false;
  while (cache.isNotEmpty &&
      cache.values.fold<int>(0, (sum, item) => sum + item.length) +
              bytes.length >
          budget) {
    cache.remove(cache.keys.first);
  }
  cache[id] = bytes;
  return true;
}
