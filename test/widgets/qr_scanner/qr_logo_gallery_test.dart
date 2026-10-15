import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:openim/pages/contacts/scanning/contact_qr_result.dart';
import 'package:openim/widgets/qr_scanner/qr_gallery_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = QrGalleryService();
  const nativeTests = bool.fromEnvironment('QR_NATIVE_TESTS');
  // Keep personal contact cards and invitation tokens outside the repository.
  const regressionImage = String.fromEnvironment('QR_GALLERY_REGRESSION_IMAGE');

  test('recognizes the reported contact card after native detection misses it',
      () async {
    final result = await service.scan(regressionImage);
    expect(result.status, QrGalleryStatus.success);
    expect(result.codes, hasLength(1));
    expect(parseContactQrResult(result.codes.single.text), contains('userID'));
    expect(result.width, 1080);
    expect(result.height, 1280);
    if (nativeTests) expect(result.engine, 'zxing-cpp+zxing-dart');
  }, skip: regressionImage.isEmpty);

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qr-logo-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('retains high-correction contact QR codes with central overlays',
      () async {
    final payload =
        'openim://user/test-peer?inviteCode=fi_${'a' * 96}&source=qrcode';
    for (final size in [11, 15, 19]) {
      final bitmap = _contactCard(payload, size);
      final file = File('${directory.path}/logo.png');
      await file.writeAsBytes(image.encodePng(bitmap));
      final result = await service.scan(file.path);
      expect(result.status, QrGalleryStatus.success, reason: 'overlay $size');
      expect(result.codes.map((code) => code.text), [payload]);
      expect(parseContactQrResult(result.codes.single.text), {
        'userID': 'test-peer',
        'inviteCode': 'fi_${'a' * 96}',
        'source': 'qrcode',
      });
    }
  });

  test('both detectors leave a blank image unrecognized', () async {
    final bitmap = image.Image(width: 240, height: 240, numChannels: 1);
    image.fill(bitmap, color: image.ColorRgb8(255, 255, 255));
    final file = File('${directory.path}/blank.png');
    await file.writeAsBytes(image.encodePng(bitmap));
    final result = await service.scan(file.path);
    expect(result.status, QrGalleryStatus.noCode);
    expect(result.codes, isEmpty);
    if (nativeTests) expect(result.engine, 'zxing-cpp+zxing-dart');
  });
}

image.Image _contactCard(String payload, int overlayModules) {
  final qr = QrImage(
      QrCode.fromData(data: payload, errorCorrectLevel: QrErrorCorrectLevel.H));
  final bitmap = image.Image(width: 1080, height: 1280, numChannels: 1);
  final white = image.ColorRgb8(255, 255, 255);
  final black = image.ColorRgb8(0, 0, 0);
  image.fill(bitmap, color: white);
  const scale = 9, left = 247, top = 322;
  for (var y = 0; y < qr.moduleCount; y++) {
    for (var x = 0; x < qr.moduleCount; x++) {
      if (qr.isDark(y, x)) {
        image.fillRect(bitmap,
            x1: left + x * scale,
            y1: top + y * scale,
            x2: left + (x + 1) * scale - 1,
            y2: top + (y + 1) * scale - 1,
            color: black);
      }
    }
  }
  final cx = left + qr.moduleCount * scale ~/ 2;
  final cy = top + qr.moduleCount * scale ~/ 2;
  final half = overlayModules * scale ~/ 2;
  image.fillRect(bitmap,
      x1: cx - half, y1: cy - half, x2: cx + half, y2: cy + half, color: white);
  return bitmap;
}
