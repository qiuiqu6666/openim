import 'media_source.dart';

/// Grid order is independent of the stable indexes used by preview actions.
List<int> newestMediaFirst(List<MediaSource> sources) {
  final indexes = List.generate(sources.length, (index) => index);
  indexes.sort((a, b) {
    final time = (sources[b].sentAt?.millisecondsSinceEpoch ?? 0)
        .compareTo(sources[a].sentAt?.millisecondsSinceEpoch ?? 0);
    return time == 0 ? a.compareTo(b) : time;
  });
  return indexes;
}
