import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/media_browser/media_grid_order.dart';
import 'package:openim_common/src/widgets/media_browser/media_source.dart';

void main() {
  test(
      'newest first across initial and appended pages without changing action indexes',
      () {
    final sources = [
      MediaSource(thumbnail: '', tag: 'old', sentAt: DateTime(2020)),
      MediaSource(thumbnail: '', tag: 'new', sentAt: DateTime(2026)),
      MediaSource(thumbnail: '', tag: 'middle', sentAt: DateTime(2024)),
    ];
    expect(newestMediaFirst(sources), [1, 2, 0]);
    sources
        .add(MediaSource(thumbnail: '', tag: 'older', sentAt: DateTime(2010)));
    expect(newestMediaFirst(sources), [1, 2, 0, 3]);
    expect(sources[1].tag, 'new');
  });
  test('equal or missing timestamps preserve stable order', () {
    final sources = List.generate(3, (_) => MediaSource(thumbnail: ''));
    expect(newestMediaFirst(sources), [0, 1, 2]);
  });
}
