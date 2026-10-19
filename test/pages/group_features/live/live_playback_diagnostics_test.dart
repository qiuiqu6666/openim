import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:openim/pages/group_features/live/playback/live_playback_diagnostics.dart';

void main() {
  test(
      'diagnostics redact source, throttle samples and ignore disjoint buffers',
      () {
    var clock = Duration.zero;
    final lines = <String>[];
    final diagnostics = LivePlaybackDiagnostics(
        enabled: true, sink: lines.add, elapsed: () => clock);
    diagnostics
        .opened(Uri.parse('https://private.test/secret.flv?txSecret=token'));
    final value = VideoPlayerValue(
        duration: Duration.zero,
        position: const Duration(seconds: 3),
        buffered: [
          DurationRange(const Duration(seconds: 2), const Duration(seconds: 5)),
          DurationRange(
              const Duration(seconds: 20), const Duration(seconds: 30)),
        ]);
    diagnostics.event('sample', value);
    clock = const Duration(seconds: 1);
    diagnostics.event('sample', value);
    expect(lines, hasLength(2));
    expect(lines.last, contains('"bufferAheadMs":2000'));
    expect(lines.join(), isNot(contains('private')));
    expect(lines.join(), isNot(contains('secret')));
    expect(lines.join(), isNot(contains('token')));
    clock = const Duration(seconds: 5);
    diagnostics.event('sample', value);
    expect(lines, hasLength(3));
    expect(lines.first, contains('"protocol":"flv"'));
  });
  test('disabled diagnostics produce no output', () {
    final lines = <String>[];
    final diagnostics =
        LivePlaybackDiagnostics(enabled: false, sink: lines.add);
    diagnostics.opened(Uri.parse('https://example.test/live.m3u8'));
    diagnostics.event('failure');
    expect(lines, isEmpty);
  });
}
