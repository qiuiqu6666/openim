import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/utils/media/openim_media_url.dart';

void main() {
  const original = 'https://99chat-openim-media.oss-cn-hongkong.aliyuncs.com/'
      'openim%2Fdata%2Fhash%2Fimage';
  const resized = '$original?x-oss-process=image/resize,m_lfit,w_960,h_960';
  test('owned OSS direct thumbnails use real OSS processing', () {
    expect(
        OpenIMMediaUrl.thumbnail(original, width: 960, height: 960), resized);
    expect(
        OpenIMMediaUrl.thumbnail('$original?width=640&height=640&type=image',
            width: 960, height: 960),
        resized);
  });
  test('persisted thumbnail is repaired at image consumption, not original',
      () {
    expect(
        OpenIMMediaUrl.resolve('$original?width=960&height=960&type=image',
            imApiUrl: 'https://im.test'),
        resized);
    expect(OpenIMMediaUrl.repairThumbnail(original), original);
    expect(OpenIMMediaUrl.repairThumbnail(resized), resized);
  });
  test('signatures, existing transforms, GIF and ambiguous queries survive',
      () {
    for (final url in [
      '$original?width=960&height=960&type=image&Signature=secret',
      '$original?width=960&height=960&type=image&Expires=123',
      '$original?x-oss-process=image/crop,w_100,h_100',
      '$original.gif?width=960&height=960&type=image',
      '$original?width=960&height=960&type=image&download=1',
      '$original?width=960&width=320&height=960&type=image',
      '$original?width=-1&height=960&type=image',
      '$original?width=%FF&height=960&type=image',
      '${original.replaceFirst('.aliyuncs.com', '.aliyuncs.com.evil.test')}'
          '?width=960&height=960&type=image',
    ]) {
      expect(OpenIMMediaUrl.repairThumbnail(url), url, reason: url);
    }
  });
  test('real thumbnail and original have different cache identities', () {
    expect(OpenIMMediaUrl.repairThumbnail(original), isNot(resized));
    expect(
        OpenIMMediaUrl.thumbnail('https://im.test/object/a',
            width: 960, height: 960),
        'https://im.test/object/a?height=960&width=960&type=image');
  });
}
