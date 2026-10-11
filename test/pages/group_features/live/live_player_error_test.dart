import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/models/live_errors.dart';

void main() {
  test('native playback failure does not expose stack or signed stream URL', () {
    final message = liveErrorMessage(PlatformException(
        code: 'VideoError',
        message: 'MediaCodecVideoRenderer https://example.test/live?token=secret'));
    expect(message, '直播播放失败，请重新连接或稍后重试');
    expect(message, isNot(contains('secret')));
  });
}
