import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openim/pages/chat/media/preview/chat_top_picture_preview.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final previews = <ChatTopPicturePreview>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('top-picture-test-');
  });
  tearDown(() async {
    for (final preview in previews) {
      await preview.dispose();
    }
    previews.clear();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<File> write(String name, List<int> bytes) =>
      File('${directory.path}/$name').writeAsBytes(bytes, flush: true);

  Future<ChatTopPicturePreview?> prepare(File file,
      {bool Function()? isCancelled}) async {
    final preview = await ChatTopPicturePreview.create(file.path,
        isCancelled: isCancelled ?? () => false);
    if (preview != null) previews.add(preview);
    return preview;
  }

  img.Image solid(int width, int height, img.Color color) =>
      img.fill(img.Image(width: width, height: height, numChannels: 4),
          color: color);

  test('real color bands prove the derivative is a top crop within its budget',
      () async {
    final original = solid(720, 3600, img.ColorRgba8(0, 0, 255, 255));
    img.fillRect(original,
        x1: 0, y1: 0, x2: 359, y2: 1295, color: img.ColorRgb8(255, 0, 0));
    img.fillRect(original,
        x1: 360, y1: 0, x2: 719, y2: 1295, color: img.ColorRgb8(0, 255, 0));
    final originalBytes = img.encodePng(original);
    final file = await write('long.png', originalBytes);
    final preview = await prepare(file);
    expect(preview, isNotNull);
    final result = preview!;
    expect(result.path, isNot(file.path));
    expect(result.width, ChatPicturePreviewMetadata.maxWidth);
    expect(result.height, 864);
    expect(result.width * result.height, lessThanOrEqualTo(480 * 864));
    final bytes = await File(result.path).readAsBytes();
    expect(result.length, bytes.length);
    final decoded = img.decodePng(bytes)!;
    expect([decoded.width, decoded.height], [result.width, result.height]);
    for (final y in [20, 430, 840]) {
      final left = decoded.getPixel(20, y);
      final right = decoded.getPixel(460, y);
      expect([left.r, left.g, left.b, left.a], [255, 0, 0, 255]);
      expect([right.r, right.g, right.b, right.a], [0, 255, 0, 255]);
    }
    expect(await file.readAsBytes(), orderedEquals(originalBytes));
    final outputParent = File(result.path).parent;
    await result.dispose();
    expect(await File(result.path).exists(), isFalse);
    expect(await outputParent.exists(), isFalse);
    expect(await file.exists(), isTrue,
        reason: 'Disposal never owns the source');
  });

  test('small transparent long images retain alpha and are never upscaled',
      () async {
    final source = solid(80, 600, img.ColorRgba8(40, 80, 120, 128));
    img.fillRect(source,
        x1: 0,
        y1: 0,
        x2: 39,
        y2: 143,
        alphaBlend: false,
        color: img.ColorRgba8(0, 0, 0, 0));
    final preview =
        await prepare(await write('alpha.png', img.encodePng(source)));
    expect(preview, isNotNull);
    expect([preview!.width, preview.height], [80, 144]);
    final decoded = img.decodePng(await File(preview.path).readAsBytes())!;
    expect(decoded.getPixel(10, 10).a, 0);
    final translucent = decoded.getPixel(60, 100);
    expect([translucent.r, translucent.g, translucent.b, translucent.a],
        [40, 80, 120, 128]);
  });

  test('JPEG orientation is applied before choosing the visible top', () async {
    final source = solid(1200, 200, img.ColorRgba8(0, 0, 255, 255));
    img.fillRect(source,
        x1: 0, y1: 0, x2: 359, y2: 199, color: img.ColorRgb8(255, 0, 0));
    source.exif.imageIfd.orientation = 6;
    final preview =
        await prepare(await write('rotated.jpg', img.encodeJpg(source)));
    expect(preview, isNotNull);
    expect([preview!.width, preview.height], [200, 360]);
    final decoded = img.decodePng(await File(preview.path).readAsBytes())!;
    for (final y in [20, 170, 330]) {
      final pixel = decoded.getPixel(100, y);
      expect(pixel.r, greaterThan(240));
      expect(pixel.b, lessThan(15));
    }
  });

  test('derivative drops textual metadata while leaving the original untouched',
      () async {
    final source = solid(80, 600, img.ColorRgb8(40, 80, 120));
    source.textData = {
      'Comment': 'private fixture metadata',
      'Author': 'fixture'
    };
    final bytes = img.encodePng(source);
    final file = await write('metadata.png', bytes);
    final preview = await prepare(file);
    expect(preview, isNotNull);
    final decoded = img.decodePng(await File(preview!.path).readAsBytes())!;
    expect(decoded.textData ?? <String, String>{}, isEmpty);
    expect(await file.readAsBytes(), orderedEquals(bytes));
    expect(img.decodePng(await file.readAsBytes())!.textData!['Comment'],
        'private fixture metadata');
  });

  for (final size in [(200, 360), (400, 200), (200, 200)]) {
    test('non-long source $size does not create a derivative', () async {
      final bytes =
          img.encodePng(solid(size.$1, size.$2, img.ColorRgb8(1, 2, 3)));
      final file = await write('ordinary.png', bytes);
      expect(await prepare(file), isNull);
      expect(await file.readAsBytes(), orderedEquals(bytes));
    });
  }

  for (final frames in [1, 2]) {
    test('$frames-frame GIF content is skipped even with a PNG filename',
        () async {
      final encoder = img.GifEncoder();
      for (var i = 0; i < frames; i++) {
        encoder.addFrame(solid(40, 240, img.ColorRgb8(i * 255, 80, 120)));
      }
      final bytes = encoder.finish()!;
      final file = await write('mislabelled.png', bytes);
      expect(await prepare(file), isNull);
      expect(await file.readAsBytes(), orderedEquals(bytes));
    });
  }

  test('missing, malformed, and oversized files leave the source path usable',
      () async {
    expect(await prepare(File('${directory.path}/missing.png')), isNull);
    final broken = await write('broken.png', [1, 2, 3, 4]);
    expect(await prepare(broken), isNull);
    expect(await broken.readAsBytes(), [1, 2, 3, 4]);
    final large = File('${directory.path}/oversized.png');
    final handle = await large.open(mode: FileMode.write);
    await handle.truncate(32 * 1024 * 1024 + 1);
    await handle.close();
    expect(await prepare(large), isNull);
    expect(await large.length(), 32 * 1024 * 1024 + 1);
  });

  test('cancelled preparation releases the shared lane for the next image',
      () async {
    final file = await write(
        'long.png', img.encodePng(solid(80, 600, img.ColorRgb8(30, 40, 50))));
    expect(await prepare(file, isCancelled: () => true), isNull);
    var checks = 0;
    expect(await prepare(file, isCancelled: () => ++checks > 1), isNull);
    expect(checks, 2, reason: 'Cancellation is rechecked after isolate work');
    expect(await prepare(file), isNotNull);
    expect(await file.exists(), isTrue);
  });
}
