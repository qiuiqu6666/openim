import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/services/media_recognition/media_image_recognition_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('99chat/qr_image_decoder');
  const address = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';
  late String ocrPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    ocrPath = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'recognizeText');
      ocrPath = call.arguments['path'] as String;
      expect(await File(ocrPath).exists(), isTrue);
      return 'TRON: $address';
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('decodes real QR, combines OCR, and removes only temporary image', () async {
    final request = recognizePreviewImage(MediaSource(
        thumbnail: '', bytes: _qr('https://99chat.vip?group=@123456')));
    final result = await request.result;
    expect(result.targets.map((e) => e.value),
        ['https://99chat.vip?group=@123456', address]);
    expect(result.targets.first.open, isNotNull);
    expect(result.targets.first.openLabel, 'Recognize group QR code');
    expect(result.targets.last.open, isNull);
    expect(result.partial, isFalse);
    expect(await File(ocrPath).exists(), isFalse);
  });
  test('unavailable OCR preserves QR and exposes retry', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw MissingPluginException();
    });
    final request = recognizePreviewImage(
        MediaSource(thumbnail: '', bytes: _qr('https://example.com')));
    final result = await request.result;
    expect(result.targets.single.value, 'https://example.com');
    expect(result.partial, isTrue);
  });
}

Uint8List _qr(String value) {
  final qr = QrImage(QrCode.fromData(
      data: value, errorCorrectLevel: QrErrorCorrectLevel.M));
  const scale = 6, border = 4;
  final side = (qr.moduleCount + border * 2) * scale;
  final output = image.Image(width: side, height: side, numChannels: 4);
  image.fill(output, color: image.ColorRgba8(255, 255, 255, 255));
  for (var y = 0; y < qr.moduleCount; y++) {
    for (var x = 0; x < qr.moduleCount; x++) {
      if (qr.isDark(y, x)) {
        image.fillRect(output,
            x1: (x + border) * scale, y1: (y + border) * scale,
            x2: (x + border + 1) * scale - 1,
            y2: (y + border + 1) * scale - 1,
            color: image.ColorRgba8(0, 0, 0, 255));
      }
    }
  }
  return Uint8List.fromList(image.encodePng(output));
}
