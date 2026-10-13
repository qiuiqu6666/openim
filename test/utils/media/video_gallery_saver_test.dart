import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/utils/media/video_gallery/video_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

List<int> _video([String brand = 'isom']) =>
    [0, 0, 0, 24, ...ascii.encode('ftyp$brand'), ...List.filled(64, 0)];

class _Download implements HttpClientAdapter {
  int calls = 0;
  String? requested;
  List<int> body = _video();
  bool stalled = false;
  bool canceled = false;
  int status = 200;
  final started = Completer<void>();
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    calls++;
    requested = options.uri.toString();
    if (!started.isCompleted) started.complete();
    if (stalled) {
      await cancelFuture;
      canceled = true;
      throw DioException.requestCancelled(
          requestOptions: options, reason: 'test');
    }
    return ResponseBody.fromBytes(body, status, headers: {
      'content-type': ['application/octet-stream']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File source;
  late _Download download;
  late Dio client;
  final writes = <String>[];
  var allowed = true;
  dynamic nativeResult;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('video-save-test-');
    source = await File('${directory.path}/source.bin').writeAsBytes(_video());
    download = _Download();
    client = Dio()..httpClientAdapter = download;
    writes.clear();
    allowed = true;
    nativeResult = {'isSuccess': true};
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
  });
  VideoGallerySaver saver(
      {Future<bool> Function()? permission,
      Future<dynamic> Function(String)? native,
      Duration timeout = const Duration(seconds: 2),
      Duration nativeTimeout = const Duration(seconds: 1)}) {
    final result = VideoGallerySaver(
        client: client,
        tempDirectory: () async => directory,
        requestPermission: permission ?? () async => allowed,
        saveFile: native ??
            (path) async {
              writes.add(path);
              expect(await File(path).readAsBytes(), _video());
              return nativeResult;
            },
        timeout: timeout,
        nativeTimeout: nativeTimeout);
    addTearDown(result.dispose);
    return result;
  }

  test(
      'local video uses file API with content extension and preserves original',
      () async {
    expect(await saver().save(file: source, isCurrent: () => true),
        VideoGalleryResult.success);
    expect(writes.single, endsWith('.mp4'));
    expect(await File(writes.single).exists(), isFalse);
    expect(await source.readAsBytes(), _video());
    expect(download.calls, 0);
  });
  test('missing local file falls back to signed chunked URL without a total',
      () async {
    const url =
        'https://cdn.example.test/object/video?X-Amz-Signature=a%2Fb&Expires=600';
    final totals = <int>[];
    expect(
        await saver().save(
            file: File('${directory.path}/missing.mp4'),
            url: url,
            isCurrent: () => true,
            onProgress: (_, total) => totals.add(total)),
        VideoGalleryResult.success);
    expect(download.requested, url);
    expect(totals, contains(-1));
    expect(writes, hasLength(1));
  });
  for (final invalid in [
    <int>[],
    ascii.encode('<html>expired token</html>'),
    _video('M4A ')
  ]) {
    test(
        'invalid or audio response is not submitted to gallery (${invalid.length})',
        () async {
      download.body = invalid;
      expect(
          await saver().save(
              url: 'https://cdn.example.test/video', isCurrent: () => true),
          VideoGalleryResult.invalidVideo);
      expect(writes, isEmpty);
    });
  }
  test('denied permission does not download or call the gallery', () async {
    allowed = false;
    expect(
        await saver()
            .save(url: 'https://cdn.example.test/video', isCurrent: () => true),
        VideoGalleryResult.permissionDenied);
    expect(download.calls, 0);
    expect(writes, isEmpty);
  });
  for (final result in [
    null,
    {'isSuccess': false},
    {'filePath': 'not-a-success'}
  ]) {
    test('native result $result is not reported as saved', () async {
      nativeResult = result;
      expect(await saver().save(file: source, isCurrent: () => true),
          VideoGalleryResult.failed);
    });
  }
  test('expired HTTP URL is a download failure and never reaches the gallery',
      () async {
    download.status = 403;
    expect(
        await saver()
            .save(url: 'https://cdn.example.test/video', isCurrent: () => true),
        VideoGalleryResult.downloadFailed);
    expect(writes, isEmpty);
  });
  test('stalled download times out and cancels actual IO', () async {
    download.stalled = true;
    final task = saver(timeout: const Duration(milliseconds: 100));
    expect(
        await task.save(
            url: 'https://cdn.example.test/video', isCurrent: () => true),
        VideoGalleryResult.timedOut);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(download.canceled, isTrue);
    expect(writes, isEmpty);
  });
  test('closing preview cancels its pending download', () async {
    download.stalled = true;
    final task = saver();
    final saving =
        task.save(url: 'https://cdn.example.test/video', isCurrent: () => true);
    await download.started.future;
    task.dispose();
    expect(await saving, VideoGalleryResult.canceled);
    expect(writes, isEmpty);
  });
  test('account change while permission is open cannot save', () async {
    final permission = Completer<bool>();
    var current = true;
    final saving = saver(permission: () => permission.future)
        .save(file: source, isCurrent: () => current);
    current = false;
    permission.complete(true);
    expect(await saving, VideoGalleryResult.canceled);
    expect(writes, isEmpty);
  });
  test('duplicate taps share one operation', () async {
    final permission = Completer<bool>();
    final task = saver(permission: () => permission.future);
    final first = task.save(file: source, isCurrent: () => true);
    final second = task.save(file: source, isCurrent: () => true);
    expect(identical(first, second), isTrue);
    permission.complete(true);
    expect(await first, VideoGalleryResult.success);
    expect(writes, hasLength(1));
  });
  test('native timeout releases UI but preserves file until native completion',
      () async {
    final write = Completer<dynamic>();
    final task = saver(
        nativeTimeout: const Duration(milliseconds: 50),
        native: (path) {
          writes.add(path);
          return write.future;
        });
    expect(await task.save(file: source, isCurrent: () => true),
        VideoGalleryResult.timedOut);
    expect(await File(writes.single).exists(), isTrue);
    expect(await task.save(file: source, isCurrent: () => true),
        VideoGalleryResult.writing);
    expect(writes, hasLength(1));
    write.complete({'isSuccess': true});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(await File(writes.single).exists(), isFalse);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('real plugin adapter saves a file on $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('image_gallery_saver_plus');
      const permissions =
          MethodChannel('flutter.baseflow.com/permissions/methods');
      final permissionIDs = <int>[];
      messenger.setMockMethodCallHandler(permissions, (call) async {
        permissionIDs.addAll(List<int>.from(call.arguments as List));
        return {for (final id in permissionIDs) id: 1};
      });
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'saveFileToGallery');
        expect(call.arguments['isReturnPathOfIOS'], isFalse);
        writes.add(call.arguments['file'] as String);
        return {'isSuccess': true};
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(permissions, null);
      });
      final task = VideoGallerySaver(
          tempDirectory: () async => directory,
          requestPermission:
              platform == TargetPlatform.android ? () async => true : null);
      addTearDown(task.dispose);
      expect(await task.save(file: source, isCurrent: () => true),
          VideoGalleryResult.success);
      expect(writes.single, endsWith('.mp4'));
      if (platform == TargetPlatform.iOS) {
        expect(permissionIDs, [Permission.photosAddOnly.value]);
      }
    });
  }
}
