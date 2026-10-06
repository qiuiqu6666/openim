import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/selection/date_availability/chat_date_day_image.dart';

import 'support/date_day_images_test_support.dart';

void main() {
  ChatDateDayImage? projection(Message message,
          {bool Function(Message)? removed}) =>
      ChatDateDayImage.fromMessage(message,
          day: imageDay, isRemoved: removed ?? (_) => false);

  test('thumbnail URL precedence is snapshot then big then source', () {
    final message = dayPicture('real-picture');
    expect(projection(message)!.url, 'https://media.example/snapshot.webp');
    message.pictureElem!.snapshotPicture!.url = '  ';
    expect(projection(message)!.url, 'https://media.example/big.webp');
    message.pictureElem!.bigPicture!.url = null;
    expect(projection(message)!.url, 'https://media.example/source.webp');
    expect(projection(message)!.messageID, 'real-picture');
  });

  test('invalid remote URLs are skipped while a normal local path is supported',
      () {
    final message = dayPicture('local-image',
        snapshot: 'data:image/png;base64,sensitive',
        big: '/not-an-absolute-url',
        original: 'https://',
        path: ' /storage/emulated/0/99chat/image.png ');
    final image = projection(message)!;
    expect(image.url, isNull);
    expect(image.localPath, '/storage/emulated/0/99chat/image.png');
    message.pictureElem!.sourcePath = '';
    expect(projection(message), isNull);
  });

  test('file URIs are normalized without reading or writing file bytes', () {
    final message = dayPicture('file-uri', path: 'file:///storage/photo.png');
    expect(projection(message)!.localPath, '/storage/photo.png');
    message.pictureElem!.sourcePath = r'E:\Pictures\photo.png';
    expect(projection(message)!.localPath, r'E:\Pictures\photo.png');
    message.pictureElem!.sourcePath = 'https://media.example/not-a-file';
    expect(projection(message)!.localPath, isNull);
  });

  test('private and expired pictures never become calendar background data',
      () {
    final message = dayPicture('private-picture', private: true);
    expect(projection(message), isNull);
    message.attachedInfoElem!
      ..hasReadTime = 1
      ..burnDuration = 1;
    expect(projection(message), isNull);
  });

  test('deleted/removed rows, invalid IDs and unsupported types are rejected',
      () {
    final message = dayPicture('gone');
    expect(projection(message, removed: (_) => true), isNull);
    message.status = MessageStatus.deleted;
    expect(projection(message), isNull);
    message.status = MessageStatus.succeeded;
    message.clientMsgID = ' ';
    expect(projection(message), isNull);
    message.clientMsgID = 'gone';
    message.contentType = MessageType.video;
    expect(projection(message), isNull);
  });

  test(
      'half-open day boundaries retain the last millisecond, not next midnight',
      () {
    final next = DateTime(imageDay.year, imageDay.month, imageDay.day + 1);
    expect(projection(dayPicture('at-start', time: imageDay)), isNotNull);
    expect(
        projection(dayPicture('at-last',
            time: next.subtract(const Duration(milliseconds: 1)))),
        isNotNull);
    expect(projection(dayPicture('next-day', time: next)), isNull);
    expect(
        projection(dayPicture('before-day',
            time: imageDay.subtract(const Duration(milliseconds: 1)))),
        isNull);
    final message = dayPicture('no-time')..sendTime = null;
    expect(projection(message), isNull);
  });
}
