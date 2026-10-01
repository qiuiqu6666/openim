import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/utils/group_qr_link.dart';

void main() {
  test('accepts current and legacy group invitations', () {
    expect(parseGroupQrLink('https://99chat.vip?group=@8F28WoJm5wPv'), '@8F28WoJm5wPv');
    expect(parseGroupQrLink('https://99chat.vip/?group=%408F28WoJm5wPv'), '@8F28WoJm5wPv');
    expect(parseGroupQrLink('io.openim.app/joinGroup/12345'), '12345');
  });
  test('rejects unrelated, ambiguous and malformed codes', () {
    for (final value in [
      'https://example.com?group=@123',
      'https://99chat.vip?group=@123&group=@456',
      'https://99chat.vip?group=@',
      'https://99chat.vip?group=%FF',
      'https://99chat.vip?group=bad%20id',
      'https://99chat.vip/other?group=@123',
      'plain text',
    ]) {
      expect(parseGroupQrLink(value), isNull, reason: value);
    }
  });
}
