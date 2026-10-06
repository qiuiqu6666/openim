import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/message_notification_sound.dart';

void main() {
  test('legacy and unknown sound choices fall back to the existing default',
      () {
    for (final value in [
      null,
      '',
      'default',
      'system',
      '../x',
      'https://sound'
    ]) {
      expect(MessageNotificationSoundIds.normalizedId(value), 'preview000');
    }
    expect(MessageNotificationSoundIds.normalizedId(' soft '), 'soft');
  });

  for (final id in MessageNotificationSoundIds.optionIds) {
    test('$id has matching native PCM resources registered in the iOS target',
        () {
      final filename = MessageNotificationSoundIds.darwinFilename(id);
      final android =
          File('android/app/src/main/res/raw/$filename').readAsBytesSync();
      final ios =
          File('ios/Runner/Notifications/Sounds/$filename').readAsBytesSync();
      expect(ios, orderedEquals(android));
      expect(String.fromCharCodes(android.take(4)), 'RIFF');
      expect(String.fromCharCodes(android.sublist(8, 12)), 'WAVE');
      final data = ByteData.sublistView(android);
      // Locate fmt/data chunks, allowing FFmpeg's optional metadata chunk.
      var offset = 12;
      var duration = 0.0;
      var bytesPerSecond = 0;
      while (offset + 8 <= android.length) {
        final chunk = String.fromCharCodes(android.sublist(offset, offset + 4));
        final size = data.getUint32(offset + 4, Endian.little);
        if (chunk == 'fmt ') {
          expect(data.getUint16(offset + 8, Endian.little), 1); // PCM.
          expect(data.getUint16(offset + 22, Endian.little), 16);
          bytesPerSecond = data.getUint32(offset + 16, Endian.little);
        } else if (chunk == 'data') {
          expect(bytesPerSecond, greaterThan(0));
          duration = size / bytesPerSecond;
        }
        offset += 8 + size + (size.isOdd ? 1 : 0);
      }
      expect(duration, greaterThan(0));
      expect(duration, lessThan(30));
      final project =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(project, contains('$filename in Resources'));
    });
  }
}
