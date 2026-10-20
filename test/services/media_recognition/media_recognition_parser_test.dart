import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/tron_address_validator.dart';
import 'package:openim/services/media_recognition/media_recognition_parser.dart';

void main() {
  const tron = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';
  test('checks checksum, deduplicates QR and OCR addresses', () {
    expect(TronAddressValidator.isValid(tron), isTrue);
    final found = parseImageRecognition([tron, tron], '地址：$tron');
    expect(found.single.kind, RecognizedImageKind.tron);
    expect(found.single.value, tron);
    expect(parseImageRecognition([], '${tron.substring(0, 33)}1'), isEmpty);
    expect(parseImageRecognition([], 'a${tron}b'), isEmpty);
  });
  test('accepts wrapped OCR address without correcting characters', () {
    expect(
        parseImageRecognition(
                [], '${tron.substring(0, 17)}\n${tron.substring(17)}')
            .single
            .value,
        tron);
    expect(parseImageRecognition([], tron.replaceFirst('J', 'I')), isEmpty);
  });
  test('platform targets preserve invitation fields', () {
    final results = parseImageRecognition([
      'https://99chat.vip?group=@123456',
      'openim://user/peer?source=qrcode&inviteCode=fi_test',
    ], '');
    expect(results[0].kind, RecognizedImageKind.group);
    expect(results[0].contact, {'groupID': '@123456'});
    expect(results[1].kind, RecognizedImageKind.friend);
    expect(results[1].contact!['inviteCode'], 'fi_test');
  });
  test('multiple codes retained; unknown schemes never become links', () {
    final results = parseImageRecognition([
      'https://example.com/a',
      'https://example.com/b',
      'javascript:alert(1)',
      'openim://invalid',
    ], '');
    expect(results.map((r) => r.kind), [
      RecognizedImageKind.url,
      RecognizedImageKind.url,
      RecognizedImageKind.text,
      RecognizedImageKind.text,
    ]);
  });
}
