import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/device_sync/models/device_sync_models.dart';

void main() {
  test('accepts COS uploads and legacy OSS resume grants without rewriting',
      () {
    for (final host in [
      '99chat-1416337673.cos.ap-hongkong.myqcloud.com',
      '99chat.oss-cn-hongkong.aliyuncs.com',
      '99chat-openim-media.oss-cn-hongkong.aliyuncs.com',
    ]) {
      final url = 'https://$host/cos/device-sync/image.jpg'
          '?q-signature=abc&partNumber=2&uploadId=a%2Bb';
      expect(deviceSyncOSSUri(url).toString(), url);
    }
  });

  test('rejects CDN upload destinations and lookalike or unsafe hosts', () {
    for (final url in [
      'https://oss.99chat.vip/image.jpg',
      'https://99chat-1416337673.cos.ap-hongkong.myqcloud.com.evil.test/a',
      'http://99chat-1416337673.cos.ap-hongkong.myqcloud.com/a',
      'https://user@99chat-1416337673.cos.ap-hongkong.myqcloud.com/a',
      'https://99chat-1416337673.cos.ap-hongkong.myqcloud.com:8443/a',
      'https://99chat-1416337673.cos.ap-hongkong.myqcloud.com/a#fragment',
    ]) {
      expect(() => deviceSyncOSSUri(url), throwsFormatException);
    }
  });
}
