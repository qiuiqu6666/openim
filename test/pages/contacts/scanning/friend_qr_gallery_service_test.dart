import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:openim/pages/contacts/scanning/friend_qr_gallery_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = FriendQrGalleryService();
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('friend_qr_gallery_test_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<String> save(image.Image source, String name) async {
    final file = File('${temp.path}/$name');
    await file.writeAsBytes(image.encodePng(source));
    return file.path;
  }

  test('reads an actual exported user QR without interpreting its payload',
      () async {
    const payload = 'https://99chat.example/user/im_internal_001?source=qr';
    final path = await save(_qrPixels(payload), 'user.png');
    expect(await service.readCode(path), payload);
  });

  test('retains UTF-8 text from a group QR', () async {
    const payload = '{"type":"group","id":"group_001","name":"秋的群聊"}';
    final path = await save(_qrPixels(payload), 'group.png');
    expect(await service.readCode(path), payload);
  });

  test('recognizes the QR in every phone image orientation', () async {
    const payload = 'https://99chat.example/invite/orientation';
    final source = _qrPixels(payload);
    for (final angle in [0, 90, 180, 270]) {
      final path = await save(
        image.copyRotate(source, angle: angle),
        'rotated_$angle.png',
      );
      expect(await service.readCode(path), payload, reason: '$angle degrees');
    }
  });

  test('recognizes a light QR on a dark background', () async {
    const payload = 'https://99chat.example/invite/dark';
    final source = image.invert(_qrPixels(payload));
    expect(await service.readCode(await save(source, 'dark.png')), payload);
  });

  test('recognizes an exported QR with a transparent quiet zone', () async {
    const payload = 'https://99chat.example/invite/transparent';
    final source = _qrPixels(payload);
    for (final pixel in source) {
      if (pixel.r == 255) pixel.a = 0;
    }
    expect(
        await service.readCode(await save(source, 'transparent.png')), payload);
  });

  test('recognizes a QR in a large album screenshot', () async {
    const payload = 'https://99chat.example/invite/large-image';
    final source = image.Image(width: 2600, height: 1800, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(245, 245, 245, 255));
    image.compositeImage(source, _qrPixels(payload), dstX: 1100, dstY: 500);
    expect(await service.readCode(await save(source, 'large.png')), payload);
  });

  test('returns null for a blank image', () async {
    final blank = image.Image(width: 240, height: 240);
    image.fill(blank, color: image.ColorRgb8(255, 255, 255));
    expect(await service.readCode(await save(blank, 'blank.png')), isNull);
  });

  test('returns null for an empty path, missing file, and invalid image',
      () async {
    final bad = File('${temp.path}/invalid.png');
    await bad.writeAsBytes([0, 1, 2, 3]);
    expect(await service.readCode('  '), isNull);
    expect(await service.readCode('${temp.path}/missing.png'), isNull);
    expect(await service.readCode(bad.path), isNull);
  });
}

// Generate independently with the same QR encoder used by the app's QR pages.
image.Image _qrPixels(String data) {
  final qr = QrImage(QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  ));
  const scale = 6;
  const border = 4;
  final side = (qr.moduleCount + border * 2) * scale;
  final output = image.Image(width: side, height: side, numChannels: 4);
  image.fill(output, color: image.ColorRgba8(255, 255, 255, 255));
  for (var y = 0; y < qr.moduleCount; y++) {
    for (var x = 0; x < qr.moduleCount; x++) {
      if (!qr.isDark(y, x)) continue;
      image.fillRect(
        output,
        x1: (x + border) * scale,
        y1: (y + border) * scale,
        x2: (x + border + 1) * scale - 1,
        y2: (y + border + 1) * scale - 1,
        color: image.ColorRgba8(0, 0, 0, 255),
      );
    }
  }
  return output;
}
