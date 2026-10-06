import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/stickers/dice/dice_webp_frames.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _FrameReference {
  const _FrameReference(
      this.first,
      this.last,
      this.width,
      this.height,
      this.frameCount,
      this.duration,
      this.transparentPixels,
      this.visiblePixels,
      this.frames);
  final String first;
  final String last;
  final int width;
  final int height;
  final int frameCount;
  final Duration duration;
  final int transparentPixels;
  final int visiblePixels;
  // Hashes let playback be compared with every native frame without retaining
  // hundreds of 512-pixel RGBA textures in the test process.
  final List<String> frames;
}

final _references = <int, _FrameReference>{};
String _hash(Uint8List rgba) => sha256.convert(rgba).toString();

class _ControlledCodec implements ui.Codec {
  _ControlledCodec(this._codec, {required this.holdAt});

  final ui.Codec _codec;
  final int holdAt;
  final heldFrame = Completer<void>();
  var calls = 0;
  var disposeCalls = 0;

  @override
  int get frameCount => _codec.frameCount;
  @override
  int get repetitionCount => _codec.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    calls++;
    if (calls == holdAt) await heldFrame.future;
    return _codec.getNextFrame();
  }

  @override
  void dispose() {
    disposeCalls++;
    _codec.dispose();
  }

  void release() {
    if (!heldFrame.isCompleted) heldFrame.complete();
  }
}

class _DeferredBundle extends CachingAssetBundle {
  final requests = <String, Completer<ByteData>>{};

  String asset(int value) =>
      'packages/openim_common/${ChatDiceSticker.assetFor(value).replaceFirst('.webp', '_final.webp')}';

  String originalAsset(int value) =>
      'packages/openim_common/${ChatDiceSticker.assetFor(value)}';

  @override
  Future<ByteData> load(String key) =>
      requests.putIfAbsent(key, Completer<ByteData>.new).future;

  Future<void> complete(WidgetTester tester, int value) async {
    final bytes = await tester.runAsync(() => rootBundle.load(asset(value)));
    requests[asset(value)]!.complete(bytes);
  }
}

Future<_FrameReference> _reference(WidgetTester tester, int value) async {
  if (_references[value] case final cached?) return cached;
  final reference = await tester.runAsync(() async {
    final bytes = await rootBundle
        .load('packages/openim_common/${ChatDiceSticker.assetFor(value)}');
    final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    var duration = Duration.zero;
    String? first;
    String? last;
    var width = 0;
    var height = 0;
    var transparent = 0;
    var visible = 0;
    final hashes = <String>[];
    try {
      for (var index = 0; index < codec.frameCount; index++) {
        final frame = await codec.getNextFrame();
        try {
          duration += frame.duration;
          final pixels = (await frame.image
                  .toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
          final hash = _hash(pixels);
          hashes.add(hash);
          first ??= hash;
          if (index == codec.frameCount - 1) {
            width = frame.image.width;
            height = frame.image.height;
            last = hash;
            for (var alpha = 3; alpha < pixels.length; alpha += 4) {
              if (pixels[alpha] == 0) {
                transparent++;
              } else {
                visible++;
              }
            }
          }
        } finally {
          frame.image.dispose();
        }
      }
      return _FrameReference(first!, last!, width, height, codec.frameCount,
          duration, transparent, visible, List.unmodifiable(hashes));
    } finally {
      codec.dispose();
    }
  });
  return _references[value] = reference!;
}

Finder get _frame => find.descendant(
    of: find.byType(ChatDiceSticker), matching: find.byType(RawImage));

Future<String?> _displayedHash(WidgetTester tester) async {
  if (_frame.evaluate().length != 1) return null;
  final image = tester.widget<RawImage>(_frame).image;
  if (image == null) return null;
  return tester.runAsync<String?>(() async {
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return pixels == null ? null : _hash(pixels.buffer.asUint8List());
  });
}

// Flush the real native codec without advancing the fake playback clock.
Future<String> _waitFrame(WidgetTester tester,
    {bool Function(String hash)? matches}) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    final hash = await _displayedHash(tester);
    if (hash != null && (matches == null || matches(hash))) return hash;
    expect(tester.takeException(), isNull);
  }
  fail('The WebP did not display the expected decoded frame.');
}

Future<void> _flushDecode(WidgetTester tester) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

// Advance animation and real native decoding together; one large fake-clock
// jump cannot run a sequence of asynchronous decoder prefetches in Flutter.
Future<void> _advancePlayback(WidgetTester tester, Duration duration) async {
  var remaining = duration.inMilliseconds;
  while (remaining > 0) {
    final step = remaining < 16 ? remaining : 16;
    await tester.pump(Duration(milliseconds: step));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    remaining -= step;
  }
}

Future<void> _mount(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light,
    bool reduceMotion = false,
    bool tickersEnabled = true}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
              size: const Size(375, 812), disableAnimations: reduceMotion),
          child: TickerMode(
            enabled: tickersEnabled,
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

Message _message(String id,
        {int value = 4,
        bool sent = true,
        int status = MessageStatus.succeeded,
        bool malformed = false}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.custom,
      'sendID': sent ? 'me' : 'peer',
      'recvID': sent ? 'peer' : 'me',
      'senderNickname': sent ? 'Me' : 'Peer',
      'sessionType': ConversationType.single,
      'sendTime': 1700000000000,
      'isRead': true,
      'status': status,
      'customElem': {
        'data': malformed
            ? jsonEncode({
                'customType': CustomMessageType.dice,
                'data': {'version': 99, 'value': 99}
              })
            : DiceMessageData(value: value).encode()
      },
    });

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _flushDecode(tester);
  await tester.pump(const Duration(milliseconds: 1));
  // Recycled animation sessions briefly retain their decoder so rebuilding a
  // sliver can resume it; allow their inactive retention lease to expire.
  await tester.pump(const Duration(seconds: 6));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Duration visibilityInterval;
  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: 'Me');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    visibilityInterval = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(() {
    VisibilityDetectorController.instance.updateInterval = visibilityInterval;
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    for (var value = 1; value <= 6; value++) {
      testWidgets('WebP outcome $value displays its final frame in $brightness',
          (tester) async {
        final reference = await _reference(tester, value);
        expect(ChatDiceSticker.assetFor(value), endsWith('.webp'));
        expect(reference.width, 512);
        expect(reference.height, 512);
        expect(reference.frameCount, 181);
        expect(reference.duration, const Duration(milliseconds: 2896));
        expect(reference.first, isNot(reference.last));
        expect(reference.transparentPixels, greaterThan(0));
        expect(reference.visiblePixels, greaterThan(1000));
        await _mount(
            tester, ChatDiceSticker(value: value, animate: false, size: 64),
            brightness: brightness);
        await _waitFrame(tester, matches: (hash) => hash == reference.last);
        final image = tester.widget<RawImage>(_frame).image!;
        expect(image.width, reference.width);
        expect(image.height, reference.height);
        expect(
            tester.getSize(find.byType(ChatDiceSticker)), const Size(64, 64));
        expect(find.bySemanticsLabel('骰子 $value点'), findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
        await _flushDecode(tester);
        expect(await _displayedHash(tester), reference.last);
        await _unmount(tester);
      });
    }
  }

  testWidgets('six result assets contain six distinct final pictures',
      (tester) async {
    final results = <String>{};
    for (var value = 1; value <= 6; value++) {
      results.add((await _reference(tester, value)).last);
    }
    expect(results, hasLength(6));
  });

  testWidgets('fresh WebP plays at original speed once and never replays',
      (tester) async {
    final reference = await _reference(tester, 5);
    final sentAt = DateTime.now().millisecondsSinceEpoch;
    Widget dice() => ChatDiceSticker(
        value: 5, messageId: 'fresh-webp-once', sentAt: sentAt, size: 100);
    await _mount(tester, dice());
    final first = await _waitFrame(tester);
    expect(first, isNot(reference.last));
    await _advancePlayback(tester, const Duration(milliseconds: 500));
    final rolling = await _waitFrame(tester,
        matches: (hash) => hash != first && hash != reference.last);
    await _mount(tester, dice());
    await _flushDecode(tester);
    expect(await _displayedHash(tester), rolling);
    await _advancePlayback(tester, const Duration(milliseconds: 500));
    await _waitFrame(tester,
        matches: (hash) => hash != rolling && hash != reference.last);
    await _advancePlayback(tester, const Duration(milliseconds: 2100));
    await _waitFrame(tester, matches: (hash) => hash == reference.last);
    await tester.pump(const Duration(seconds: 10));
    await _flushDecode(tester);
    expect(await _displayedHash(tester), reference.last);
    await _unmount(tester);
    await _mount(tester, dice());
    await _waitFrame(tester, matches: (hash) => hash == reference.last);
    await _unmount(tester);
  });

  testWidgets('continuous playback displays each original WebP frame at 16 ms',
      (tester) async {
    final reference = await _reference(tester, 4);
    final sentAt = DateTime.now().millisecondsSinceEpoch;
    Widget dice() => ChatDiceSticker(
        key: const ValueKey('continuous-webp'),
        value: 4,
        messageId: 'continuous-webp-16ms',
        sentAt: sentAt,
        size: 100);
    await _mount(tester, dice());
    await _waitFrame(tester, matches: (hash) => hash == reference.first);
    final state = tester.state(find.byType(ChatDiceSticker));
    // Begin just after the first native ticker callback establishes its clock.
    await tester.pump(const Duration(milliseconds: 1));
    var changes = 0;
    var previous = reference.first;
    for (var index = 1; index < reference.frameCount; index++) {
      await tester.pump(const Duration(milliseconds: 16));
      final shown = await _waitFrame(tester,
          matches: (hash) => hash == reference.frames[index]);
      if (shown != previous) changes++;
      previous = shown;
      if (index == 90) {
        await _mount(tester, dice());
        expect(identical(tester.state(find.byType(ChatDiceSticker)), state),
            isTrue);
        expect(await _displayedHash(tester), reference.frames[index]);
      }
      expect(tester.takeException(), isNull);
    }
    expect(changes, greaterThan(100),
        reason: 'A rolling image must keep changing during ordinary frames.');
    // Last frame begins at 2880 ms; its 16 ms hold ends at exactly 2896 ms.
    await tester.pump(const Duration(milliseconds: 15));
    await _flushDecode(tester);
    expect(await _displayedHash(tester), reference.last);
    await tester.pump(const Duration(seconds: 2));
    await _flushDecode(tester);
    expect(await _displayedHash(tester), reference.last);
    await _unmount(tester);
  });

  testWidgets('a slow decoded frame holds the picture and resumes in order',
      (tester) async {
    final reference = await _reference(tester, 2);
    late _ControlledCodec codec;
    DiceWebpFrames.debugCodecFactory = (bytes) async {
      codec =
          _ControlledCodec(await ui.instantiateImageCodec(bytes), holdAt: 2);
      return codec;
    };
    addTearDown(() {
      DiceWebpFrames.debugCodecFactory = null;
      codec.release();
    });
    await _mount(
        tester,
        ChatDiceSticker(
            value: 2,
            messageId: 'controlled-slow-webp-roll',
            sentAt: DateTime.now().millisecondsSinceEpoch,
            size: 100));
    await _waitFrame(tester, matches: (hash) => hash == reference.first);
    expect(codec.calls, 2);
    for (var interval = 0; interval < 120; interval++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(await _displayedHash(tester), reference.first,
        reason: 'An unavailable next picture must not skip to the result.');
    expect(codec.calls, 2, reason: 'Decoding must remain serial.');
    codec.release();
    await _flushDecode(tester);
    await _waitFrame(tester, matches: (hash) => hash == reference.frames[1]);
    for (var index = 2; index < reference.frameCount; index++) {
      await tester.pump(const Duration(milliseconds: 16));
      await _waitFrame(tester,
          matches: (hash) => hash == reference.frames[index]);
    }
    expect(codec.calls, reference.frameCount,
        reason: 'One roll decodes one pass and never loops the WebP.');
    expect(codec.disposeCalls, 1);
    await tester.pump(const Duration(seconds: 5));
    await _flushDecode(tester);
    expect(await _displayedHash(tester), reference.last);
    expect(codec.calls, reference.frameCount);
    await _unmount(tester);
  });

  testWidgets('recycled state resumes its unfinished roll without jumping',
      (tester) async {
    final reference = await _reference(tester, 3);
    final sentAt = DateTime.now().millisecondsSinceEpoch;
    Widget dice() => ChatDiceSticker(
        value: 3,
        messageId: 'briefly-recycled-webp-roll',
        sentAt: sentAt,
        size: 100);
    await _mount(tester, dice());
    await _waitFrame(tester, matches: (hash) => hash == reference.first);
    await tester.pump(const Duration(milliseconds: 1));
    for (var index = 1; index <= 40; index++) {
      await tester.pump(const Duration(milliseconds: 16));
      await _waitFrame(tester,
          matches: (hash) => hash == reference.frames[index]);
    }
    final previousState = tester.state(find.byType(ChatDiceSticker));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    await _flushDecode(tester);
    await _mount(tester, dice());
    expect(identical(tester.state(find.byType(ChatDiceSticker)), previousState),
        isFalse);
    await _waitFrame(tester, matches: (hash) => hash == reference.frames[40]);
    for (var index = 41; index <= 60; index++) {
      await tester.pump(const Duration(milliseconds: 16));
      await _waitFrame(tester,
          matches: (hash) => hash == reference.frames[index]);
    }
    expect(await _displayedHash(tester), isNot(reference.last));
    await _unmount(tester);
  });

  testWidgets('an expired recycled roll keeps its result and does not restart',
      (tester) async {
    final reference = await _reference(tester, 6);
    final sentAt = DateTime.now().millisecondsSinceEpoch;
    Widget dice() => ChatDiceSticker(
        value: 6,
        messageId: 'expired-recycled-webp-roll',
        sentAt: sentAt,
        size: 100);
    await _mount(tester, dice());
    await _waitFrame(tester, matches: (hash) => hash == reference.first);
    await tester.pump(const Duration(milliseconds: 1));
    for (var index = 1; index <= 20; index++) {
      await tester.pump(const Duration(milliseconds: 16));
      await _waitFrame(tester,
          matches: (hash) => hash == reference.frames[index]);
    }
    await _unmount(tester);
    await _mount(tester, dice());
    await _waitFrame(tester, matches: (hash) => hash == reference.last);
    await _advancePlayback(tester, const Duration(milliseconds: 500));
    expect(await _displayedHash(tester), reference.last,
        reason: 'The short retention lease must not permit a second roll.');
    await _unmount(tester);
  });

  testWidgets('disposing during an awaited decode releases its codec once',
      (tester) async {
    final reference = await _reference(tester, 1);
    late _ControlledCodec codec;
    DiceWebpFrames.debugCodecFactory = (bytes) async {
      codec =
          _ControlledCodec(await ui.instantiateImageCodec(bytes), holdAt: 2);
      return codec;
    };
    addTearDown(() {
      DiceWebpFrames.debugCodecFactory = null;
      codec.release();
    });
    await _mount(
        tester,
        ChatDiceSticker(
            value: 1,
            messageId: 'disposed-during-prefetch',
            sentAt: DateTime.now().millisecondsSinceEpoch,
            size: 100));
    await _waitFrame(tester, matches: (hash) => hash == reference.first);
    expect(codec.calls, 2);
    await _unmount(tester);
    expect(codec.disposeCalls, 0,
        reason: 'The native codec must survive its pending getNextFrame.');
    codec.release();
    await _flushDecode(tester);
    expect(codec.disposeCalls, 1);
    expect(_frame, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history and reduced motion decode directly to the sent result',
      (tester) async {
    final old = await _reference(tester, 2);
    await _mount(tester,
        const ChatDiceSticker(value: 2, messageId: 'old-webp-roll', sentAt: 1));
    await _waitFrame(tester, matches: (hash) => hash == old.last);
    await tester.pump(const Duration(seconds: 1));
    expect(await _displayedHash(tester), old.last);
    await _unmount(tester);
    final reduced = await _reference(tester, 6);
    await _mount(
        tester,
        ChatDiceSticker(
            value: 6,
            messageId: 'reduce-motion-webp-roll',
            sentAt: DateTime.now().millisecondsSinceEpoch),
        reduceMotion: true);
    await _waitFrame(tester, matches: (hash) => hash == reduced.last);
    await tester.pump(const Duration(seconds: 1));
    expect(await _displayedHash(tester), reduced.last);
    await _unmount(tester);
  });

  testWidgets('offscreen and background pause and resume the same WebP roll',
      (tester) async {
    final sentAt = DateTime.now().millisecondsSinceEpoch;
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await _mount(
        tester,
        SizedBox(
            height: 200,
            child: SingleChildScrollView(
                controller: scrollController,
                child: Column(children: [
                  ChatDiceSticker(
                      value: 3,
                      messageId: 'webp-pause-roll',
                      sentAt: sentAt,
                      size: 100),
                  const SizedBox(height: 1000),
                ]))));
    await _waitFrame(tester);
    await tester.pump(const Duration(milliseconds: 250));
    await _flushDecode(tester);
    scrollController.jumpTo(500);
    await tester.pump();
    await tester.pump();
    await _flushDecode(tester);
    final hidden = await _displayedHash(tester);
    await tester.pump(const Duration(seconds: 1));
    await _flushDecode(tester);
    expect(await _displayedHash(tester), hidden);
    scrollController.jumpTo(0);
    await tester.pump();
    await _flushDecode(tester);
    await tester.pump(const Duration(milliseconds: 250));
    await _waitFrame(tester, matches: (hash) => hash != hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await _flushDecode(tester);
    final background = await _displayedHash(tester);
    await tester.pump(const Duration(seconds: 1));
    await _flushDecode(tester);
    expect(await _displayedHash(tester), background);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await _waitFrame(tester, matches: (hash) => hash != background);
    await _unmount(tester);
  });

  testWidgets('disabled tickers hold the initial WebP frame until enabled',
      (tester) async {
    final sentAt = DateTime.now().millisecondsSinceEpoch;
    final reference = await _reference(tester, 1);
    Widget dice() => ChatDiceSticker(
        value: 1, messageId: 'webp-ticker-roll', sentAt: sentAt, size: 100);
    await _mount(tester, dice(), tickersEnabled: false);
    await _waitFrame(tester, matches: (hash) => hash == reference.first);
    await tester.pump(const Duration(seconds: 2));
    await _flushDecode(tester);
    expect(await _displayedHash(tester), reference.first);
    await _mount(tester, dice());
    await tester.pump(const Duration(milliseconds: 250));
    await _waitFrame(tester,
        matches: (hash) => hash != reference.first && hash != reference.last);
    await _unmount(tester);
  });

  testWidgets('source switch discards stale decoded frames and dispose is safe',
      (tester) async {
    final last = (await _reference(tester, 6)).last;
    await _mount(
        tester,
        const ChatDiceSticker(
            key: ValueKey('changing'), value: 1, animate: false));
    await _mount(
        tester,
        const ChatDiceSticker(
            key: ValueKey('changing'), value: 6, animate: false));
    await _waitFrame(tester, matches: (hash) => hash == last);
    await _flushDecode(tester);
    expect(await _displayedHash(tester), last);
    await _mount(
        tester,
        const ChatDiceSticker(
            key: ValueKey('changing'), value: 3, animate: false));
    await _unmount(tester);
    expect(_frame, findsNothing);
  });

  testWidgets('a covered route pauses the WebP and resumes its existing roll',
      (tester) async {
    await _mount(
        tester,
        ChatDiceSticker(
            value: 4,
            messageId: 'webp-route-roll',
            sentAt: DateTime.now().millisecondsSinceEpoch,
            size: 100));
    await _waitFrame(tester);
    await tester.pump(const Duration(milliseconds: 250));
    await _flushDecode(tester);
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    final route = PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => const Center(child: Text('Covered')));
    unawaited(navigator.push(route));
    await tester.pump();
    await _flushDecode(tester);
    final covered = await _displayedHash(tester);
    await tester.pump(const Duration(seconds: 1));
    await _flushDecode(tester);
    expect(await _displayedHash(tester), covered);
    navigator.pop();
    await tester.pump();
    await _flushDecode(tester);
    await tester.pump(const Duration(milliseconds: 250));
    await _waitFrame(tester, matches: (hash) => hash != covered);
    await _unmount(tester);
  });

  testWidgets(
      'delayed asset replacement ignores an older load and late disposal',
      (tester) async {
    final bundle = _DeferredBundle();
    Widget dice(int value) => DefaultAssetBundle(
        bundle: bundle,
        child: ChatDiceSticker(
            key: const ValueKey('delayed'), value: value, animate: false));
    await _mount(tester, dice(1));
    expect(bundle.requests.keys, [bundle.asset(1)]);
    await _mount(tester, dice(6));
    expect(bundle.requests.keys, [bundle.asset(1), bundle.asset(6)]);
    final expected = (await _reference(tester, 6)).last;
    await bundle.complete(tester, 6);
    await _waitFrame(tester, matches: (hash) => hash == expected);
    await bundle.complete(tester, 1);
    await _flushDecode(tester);
    expect(await _displayedHash(tester), expected);
    await _mount(tester, dice(3));
    await _unmount(tester);
    await bundle.complete(tester, 3);
    await _flushDecode(tester);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_frame, findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('asset errors show a readable fallback in $brightness',
        (tester) async {
      final bundle = _DeferredBundle();
      await _mount(
          tester,
          DefaultAssetBundle(
              bundle: bundle,
              child: const ChatDiceSticker(value: 2, animate: false)),
          brightness: brightness);
      bundle.requests[bundle.asset(2)]!
          .completeError(StateError('Injected missing WebP'));
      await _flushDecode(tester);
      bundle.requests[bundle.originalAsset(2)]!
          .completeError(StateError('Injected missing original WebP'));
      await _flushDecode(tester);
      expect(find.text('[骰子]'), findsOneWidget);
      expect(_frame, findsNothing);
      await _unmount(tester);
    });
  }

  testWidgets('invalid dice value retains the localized label', (tester) async {
    await _mount(tester, const ChatDiceSticker(value: 7));
    await _flushDecode(tester);
    expect(find.text('[骰子]'), findsOneWidget);
    expect(_frame, findsNothing);
    await _unmount(tester);
  });

  for (final sent in [true, false]) {
    testWidgets('WebP dice keeps transparent SDK container for sent=$sent',
        (tester) async {
      final reference = await _reference(tester, 4);
      await _mount(
          tester,
          ChatItemView(
              message: _message('webp-container-$sent', sent: sent),
              showLeftNickname: false,
              onTapUserProfile: (_) {}));
      await _waitFrame(tester, matches: (hash) => hash == reference.last);
      expect(find.byType(ChatDiceSticker), findsOneWidget);
      expect(find.byType(ChatImageSticker), findsNothing);
      final container =
          tester.widget<ChatItemContainer>(find.byType(ChatItemContainer));
      expect(container.bareMedia, isTrue);
      expect(container.mediaOverlay, isTrue);
      expect(container.stickerMedia, isTrue);
      expect(container.isBubbleBg, isFalse);
      expect(container.isSending, isFalse);
      expect(container.hasRead, isTrue);
      expect(find.byType(ChatReadReceiptIcon),
          sent ? findsOneWidget : findsNothing);
      await tester.tap(find.byType(ChatDiceSticker));
      await tester.pump();
      expect(find.byType(MediaBrowser), findsNothing);
      await _unmount(tester);
    });
  }

  testWidgets('failed WebP dice retains SDK retry and original point',
      (tester) async {
    final last = (await _reference(tester, 6)).last;
    var retried = false;
    await _mount(
        tester,
        ChatItemView(
            message: _message('failed-webp-dice',
                value: 6, status: MessageStatus.failed),
            onTapUserProfile: (_) {},
            onFailedToResend: () => retried = true));
    await _waitFrame(tester, matches: (hash) => hash == last);
    expect(find.byType(ChatSendFailedView), findsOneWidget);
    await tester.tap(find.byType(ChatSendFailedView));
    await tester.pump();
    expect(retried, isTrue);
    expect(
        tester.widget<ChatDiceSticker>(find.byType(ChatDiceSticker)).value, 6);
    await _unmount(tester);
  });

  testWidgets('unsupported dice version retains localized dice label',
      (tester) async {
    await _mount(
        tester,
        ChatItemView(
            message: _message('malformed-webp-dice', malformed: true),
            onTapUserProfile: (_) {}));
    expect(find.text('[骰子]'), findsOneWidget);
    expect(_frame, findsNothing);
    await _unmount(tester);
  });
}
