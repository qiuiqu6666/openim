import 'package:characters/characters.dart';

/// User-facing operations use extended grapheme clusters. SDK/Flutter offsets
/// remain UTF-16 offsets; these helpers only align edits and display boundaries.
String graphemePrefix(String text, int count) =>
    text.characters.take(count < 0 ? 0 : count).toString();

String graphemeSuffix(String text, int count) {
  final clusters = text.characters;
  final length = clusters.length;
  return clusters.skip(length - count.clamp(0, length)).toString();
}

/// Unlike String.trim, never removes the base of a combining sequence.
String graphemeTrim(String text) => text.characters
    .skipWhile((cluster) => cluster.trim().isEmpty)
    .toList()
    .reversed
    .skipWhile((cluster) => cluster.trim().isEmpty)
    .toList()
    .reversed
    .join();

/// Display-only single-line summaries collapse complete whitespace clusters.
/// A whitespace base carrying a combining mark remains untouched.
String graphemeCollapseWhitespace(String text) {
  final result = StringBuffer();
  var whitespace = false;
  for (final cluster in text.characters) {
    if (cluster.trim().isEmpty) {
      if (!whitespace) result.write(' ');
      whitespace = true;
    } else {
      result.write(cluster);
      whitespace = false;
    }
  }
  return result.toString();
}

List<int> graphemeBoundaries(String text) {
  final offsets = <int>[0];
  var offset = 0;
  for (final cluster in text.characters) {
    offset += cluster.length;
    offsets.add(offset);
  }
  return offsets;
}

int graphemeBoundaryBefore(String text, int offset, {List<int>? boundaries}) {
  final bounded = offset.clamp(0, text.length);
  if (boundaries != null) {
    return _boundaryIn(boundaries, bounded, after: false);
  }
  var previous = 0;
  for (final cluster in text.characters) {
    final next = previous + cluster.length;
    if (next > bounded) return previous;
    previous = next;
  }
  return text.length;
}

int graphemeBoundaryAfter(String text, int offset, {List<int>? boundaries}) {
  final bounded = offset.clamp(0, text.length);
  if (boundaries != null) {
    return _boundaryIn(boundaries, bounded, after: true);
  }
  if (bounded == 0) return 0;
  var end = 0;
  for (final cluster in text.characters) {
    end += cluster.length;
    if (end >= bounded) return end;
  }
  return text.length;
}

({int start, int end}) graphemeSafeRange(String text, int start, int end,
    {List<int>? boundaries}) {
  final first = start < end ? start : end;
  final last = start < end ? end : start;
  return (
    start: graphemeBoundaryBefore(text, first, boundaries: boundaries),
    end: graphemeBoundaryAfter(text, last, boundaries: boundaries),
  );
}

int _boundaryIn(List<int> boundaries, int offset, {required bool after}) {
  var low = 0, high = boundaries.length - 1;
  while (low <= high) {
    final middle = (low + high) ~/ 2;
    final value = boundaries[middle];
    if (value == offset) return value;
    if (value < offset) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return boundaries[after ? low : high];
}
