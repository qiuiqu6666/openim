import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/scanning/contact_qr_result.dart';

void main() {
  test('recognizes current, encoded and legacy group links', () {
    for (final value in [
      'https://99chat.vip?group=@123456',
      'https://99chat.vip/?group=%40123456',
      '  https://99chat.vip?group=@123456  ',
    ]) {
      expect(parseContactQrResult(value), {'groupID': '@123456'});
    }
    expect(parseContactQrResult('io.openim.app/joinGroup/123456'),
        {'groupID': '123456'});
  });

  test('retains friend invitation fields and their original source', () {
    for (final source in ['qrcode', 'link']) {
      for (final scheme in ['chat99', 'openim']) {
      expect(
        parseContactQrResult(
            '$scheme://user/peer?source=$source&inviteCode=fi_test'),
        {'userID': 'peer', 'inviteCode': 'fi_test', 'source': source},
      );
      }
    }
  });

  test('ignores unrelated, ambiguous and malformed payloads without throwing',
      () {
    for (final value in [
      '',
      '123456',
      'https://example.com?group=@123456',
      'https://99chat.vip?group=@123&group=@456',
      'https://99chat.vip?group=@',
      'https://99chat.vip?group=%FF',
      'https://99chat.vip?group=bad%20id',
      'openim://user/peer',
      'chat99://user/peer',
      'chat99://user/peer?source=card&inviteCode=fi_test',
      'chat99://user/peer?source=qrcode&inviteCode=%FF',
      'openim://user/peer?source=qrcode&inviteCode=%FF',
    ]) {
      expect(parseContactQrResult(value), isNull, reason: value);
    }
  });
}
