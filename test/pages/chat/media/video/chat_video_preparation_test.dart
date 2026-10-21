import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/video/chat_video_preparation.dart';
import 'package:video_compress/video_compress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('video_compress');
  late Directory dir;
  late File source, output;
  final calls = <MethodCall>[];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('video-quality-');
    source =
        await File('${dir.path}/source.mp4').writeAsBytes(List.filled(100, 1));
    output =
        await File('${dir.path}/small.mp4').writeAsBytes(List.filled(20, 1));
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return jsonEncode({'path': output.path});
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });
  test('standard selects 720p preset, 30 fps, keeps source and audio',
      () async {
    expect((await prepareChatVideo(source, ChatVideoQuality.standard)).path,
        output.path);
    final args = calls.single.arguments as Map;
    expect(args['quality'], VideoQuality.Res1280x720Quality.index);
    expect(args['frameRate'], 30);
    expect(args['deleteOrigin'], false);
    expect(args['includeAudio'], true);
    expect(await source.exists(), true);
  });
  test('original bypasses encoder', () async {
    expect(await prepareChatVideo(source, ChatVideoQuality.original), source);
    expect(calls, isEmpty);
  });
  test('encoder timeout cancels owned operation and ignores late output',
      () async {
    final release = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'compressVideo') return release.future;
      return null;
    });
    await expectLater(
        prepareChatVideo(source, ChatVideoQuality.standard,
            compressionTimeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()));
    expect(calls.map((c) => c.method), ['compressVideo', 'cancelCompression']);
    release.complete(jsonEncode({'path': output.path}));
    await Future<void>.delayed(Duration.zero);
    expect(VideoCompress.isCompressing, isFalse);
    expect(await source.exists(), isTrue);
  });

  test('busy timeout does not cancel another operation', () async {
    final release = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return release.future;
    });
    final first = prepareChatVideo(source, ChatVideoQuality.standard);
    await Future<void>.delayed(Duration.zero);
    try {
      await expectLater(
          prepareChatVideo(source, ChatVideoQuality.standard,
              busyTimeout: Duration.zero),
          throwsA(isA<TimeoutException>()));
      expect(calls.map((c) => c.method), ['compressVideo']);
    } finally {
      release.complete(jsonEncode({'path': output.path}));
      await first;
    }
  });
  test('empty output fails rather than silently uploading the original',
      () async {
    await output.writeAsBytes([]);
    await expectLater(
        prepareChatVideo(source, ChatVideoQuality.standard), throwsStateError);
  });
  test('overlapping standard sends both go through compressor', () async {
    final release = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return calls.length == 1
          ? release.future
          : jsonEncode({'path': output.path});
    });
    final first = prepareChatVideo(source, ChatVideoQuality.standard);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = prepareChatVideo(source, ChatVideoQuality.standard);
    expect(calls, hasLength(1));
    release.complete(jsonEncode({'path': output.path}));
    final results = await Future.wait([first, second]);
    expect(calls, hasLength(2));
    expect(results.map((file) => file.path), everyElement(output.path));
  });
  test('healthy encoder can outlast another video queue budget', () async {
    final release = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'compressVideo') return release.future;
      return null;
    });
    final first = prepareChatVideo(source, ChatVideoQuality.standard);
    await Future<void>.delayed(Duration.zero);
    try {
      await expectLater(
          prepareChatVideo(source, ChatVideoQuality.standard,
              busyTimeout: const Duration(milliseconds: 20)),
          throwsA(isA<TimeoutException>()));
      expect(VideoCompress.isCompressing, isTrue);
      expect(calls.map((c) => c.method), ['compressVideo']);
    } finally {
      release.complete(jsonEncode({'path': output.path}));
      expect((await first).path, output.path);
    }
  });

  test('cancel acknowledgement does not release a missing encoder callback',
      () async {
    final release = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'compressVideo') return release.future;
      return null;
    });
    try {
      await expectLater(
          prepareChatVideo(source, ChatVideoQuality.standard,
              compressionTimeout: const Duration(milliseconds: 20)),
          throwsA(isA<TimeoutException>()));
      expect(VideoCompress.isCompressing, isTrue);
      await expectLater(
          prepareChatVideo(source, ChatVideoQuality.standard,
              busyTimeout: Duration.zero),
          throwsStateError);
      expect(
          calls.map((c) => c.method), ['compressVideo', 'cancelCompression']);
      expect(await prepareChatVideo(source, ChatVideoQuality.original), source);
    } finally {
      release.complete(jsonEncode({'path': output.path}));
      await Future<void>.delayed(Duration.zero);
    }
  });

  test('default queue waits for healthy previous compression', () async {
    final release = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'compressVideo' && calls.length == 1) {
        return release.future;
      }
      return jsonEncode({'path': output.path});
    });
    final first = prepareChatVideo(source, ChatVideoQuality.standard);
    await Future<void>.delayed(Duration.zero);
    final second = prepareChatVideo(source, ChatVideoQuality.standard);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(calls, hasLength(1));
    release.complete(jsonEncode({'path': output.path}));
    expect((await Future.wait([first, second])).map((f) => f.path),
        everyElement(output.path));
    expect(calls, hasLength(2));
  });

  test('cancel queued video never cancels active encoder', () async {
    final release = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return release.future;
    });
    final first = prepareChatVideo(source, ChatVideoQuality.standard);
    await Future<void>.delayed(Duration.zero);
    var cancelled = false;
    final second = prepareChatVideo(source, ChatVideoQuality.standard,
        isCancelled: () => cancelled);
    cancelled = true;
    await expectLater(second, throwsStateError);
    expect(calls.map((c) => c.method), ['compressVideo']);
    release.complete(jsonEncode({'path': output.path}));
    await first;
  });
}
