import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/message_notification_avatar_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('notification-avatar-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('concurrent resolves share a fetch and produce a small valid PNG',
      () async {
    final source = await _png(directory, 'source.png', 768, 512);
    final download = Completer<File>();
    var fetches = 0;
    final cache = MessageNotificationAvatarCache(fetch: (_) {
      fetches++;
      return download.future;
    });
    final first = cache.resolve('https://example.test/avatar.png');
    final second = cache.resolve('https://example.test/avatar.png');
    expect(identical(first, second), isTrue);
    expect(fetches, 1);
    download.complete(source);
    final paths = await Future.wait([first, second]);
    expect(paths.first, isNotNull);
    expect(paths.first, paths.last);
    expect(paths.first, isNot(source.path));
    final dimensions = await _dimensions(File(paths.first!));
    expect(dimensions.width, inInclusiveRange(1, 128));
    expect(dimensions.height, inInclusiveRange(1, 128));
    expect((await File(paths.first!).readAsBytes()).take(8),
        [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('small avatars remain small instead of being upscaled', () async {
    final source = await _png(directory, 'small.png', 32, 20);
    final cache = MessageNotificationAvatarCache(fetch: (_) async => source);
    final path = await cache.resolve('https://example.test/small.png');
    expect(path, isNotNull);
    final dimensions = await _dimensions(File(path!));
    expect(dimensions.width, lessThanOrEqualTo(32));
    expect(dimensions.height, lessThanOrEqualTo(20));
  });

  test('completed thumbnail is reused and distinct URLs have distinct paths',
      () async {
    final source = await _png(directory, 'shared-source.png', 256, 256);
    final cache = MessageNotificationAvatarCache(fetch: (_) async => source);
    final first = await cache.resolve('https://example.test/first.png');
    final firstFile = File(first!);
    final originalModified = await firstFile.lastModified();
    // A deterministic old timestamp proves a second resolve did not rewrite it.
    final marker = originalModified.subtract(const Duration(days: 1));
    await firstFile.setLastModified(marker);
    final recordedMarker = await firstFile.lastModified();
    final again = await cache.resolve('https://example.test/first.png');
    expect(again, first);
    expect(await firstFile.lastModified(), recordedMarker);
    final other = await cache.resolve('https://example.test/second.png');
    expect(other, isNotNull);
    expect(other, isNot(first));
  });

  test('changed source at the same URL generates an updated thumbnail',
      () async {
    final source = await _png(directory, 'changing.png', 512, 512);
    final cache = MessageNotificationAvatarCache(fetch: (_) async => source);
    const url = 'https://example.test/changing.png';
    final first = await cache.resolve(url);
    expect(first, isNotNull);
    expect((await _dimensions(File(first!))).width, 128);
    final oldModified = await source.lastModified();
    await _png(directory, 'changing.png', 64, 48);
    await source.setLastModified(oldModified.add(const Duration(seconds: 5)));
    final updated = await cache.resolve(url);
    expect(updated, isNotNull);
    expect(updated, isNot(first));
    expect(await _dimensions(File(updated!)), (width: 64, height: 48));
  });

  test('unsupported and malformed URLs fall back without fetching', () async {
    var fetches = 0;
    final cache = MessageNotificationAvatarCache(fetch: (_) async {
      fetches++;
      throw StateError('invalid URL must not be fetched');
    });
    for (final url in <String?>[
      null,
      '',
      'not a URL',
      'file:///tmp/avatar.png',
      'data:image/png;base64,AAA',
      'ftp://example.test/avatar.png',
      'https:///avatar.png',
      'https://[malformed',
    ]) {
      expect(await cache.resolve(url), isNull);
    }
    expect(fetches, 0);
    expect(await directory.list().toList(), isEmpty);
  });

  test('damaged source falls back and a later resolve can retry', () async {
    final damaged = File('${directory.path}/damaged.png');
    await damaged.writeAsString('not PNG bytes');
    var source = damaged;
    final cache = MessageNotificationAvatarCache(fetch: (_) async => source);
    const url = 'https://example.test/retry.png';
    expect(await cache.resolve(url), isNull);
    source = await _png(directory, 'repaired.png', 300, 300);
    final path = await cache.resolve(url);
    expect(path, isNotNull);
    expect((await _dimensions(File(path!))).width, lessThanOrEqualTo(128));
  });

  test('source above four MiB falls back without writing a thumbnail',
      () async {
    final source = File('${directory.path}/oversized.png');
    final writer = await source.open(mode: FileMode.write);
    try {
      await writer.truncate(4 * 1024 * 1024 + 1);
    } finally {
      await writer.close();
    }
    final cache = MessageNotificationAvatarCache(fetch: (_) async => source);
    expect(await cache.resolve('https://example.test/oversized.png'), isNull);
    final entries = await directory.list().toList();
    expect(entries, hasLength(1));
    expect(await FileSystemEntity.identical(entries.single.path, source.path),
        isTrue);
  });

  test('fetch errors and missing files use the platform icon fallback',
      () async {
    final unavailable = MessageNotificationAvatarCache(
        fetch: (_) async => throw const SocketException('fake unavailable'));
    expect(await unavailable.resolve('https://example.test/unavailable.png'),
        isNull);
    final missing = MessageNotificationAvatarCache(
        fetch: (_) async => File('${directory.path}/missing.png'));
    expect(await missing.resolve('https://example.test/missing.png'), isNull);
  });
}

Future<File> _png(
    Directory directory, String name, int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xff2468ac));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return await File('${directory.path}/$name')
        .writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<({int width, int height})> _dimensions(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  try {
    final frame = await codec.getNextFrame();
    try {
      return (width: frame.image.width, height: frame.image.height);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
