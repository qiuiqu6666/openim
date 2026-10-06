import '../pages/storage_media_repository.dart';

/// Projection rebuilt only when source revision, ordering or day changes.
class StorageMediaCatalog {
  StorageMediaCatalog({
    required List<StorageMediaItem> source,
    required String conversationID,
    required StorageMediaType? type,
    required bool oldestFirst,
    required DateTime now,
  }) {
    day = DateTime(now.year, now.month, now.day);
    final thisWeek = day.subtract(Duration(days: day.weekday - 1));
    items = source
        .where((item) =>
            item.conversationID == conversationID &&
            (type == null || item.type == type))
        .toList();
    items.sort((a, b) =>
        oldestFirst ? a.time.compareTo(b.time) : b.time.compareTo(a.time));
    for (final item in items) {
      byID[item.id] = item;
      totalBytes += item.bytes;
      final key = item.time.isAfter(day)
          ? 'today'
          : item.time.isAfter(thisWeek)
              ? 'week'
              : '${item.time.year}.${item.time.month.toString().padLeft(2, '0')}';
      sections.putIfAbsent(key, () => []).add(item);
    }
  }

  late final DateTime day;
  late final List<StorageMediaItem> items;
  final Map<String, StorageMediaItem> byID = {};
  final Map<String, List<StorageMediaItem>> sections = {};
  int totalBytes = 0;
}
