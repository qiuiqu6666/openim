import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/stickers/dice/dice_webp_frames.dart';
import 'package:openim_common/src/widgets/chat/stickers/dice/dice_webp_playback.dart';

String _asset(int value) =>
    'packages/openim_common/assets/chat/dice/dice_$value.webp';
String _poster(int value) =>
    'packages/openim_common/assets/chat/dice/dice_${value}_final.webp';

class _OriginalOnlyBundle extends CachingAssetBundle {
  _OriginalOnlyBundle(this.value, this.original, {this.corruptPoster = false});

  final int value;
  final ByteData? original;
  final bool corruptPoster;
  final requests = <String>[];

  @override
  Future<ByteData> load(String key) async {
    requests.add(key);
    if (key == _asset(value) && original != null) return original!;
    if (key == _poster(value) && corruptPoster) return ByteData(16);
    throw FlutterError('Injected unavailable bundled asset: $key');
  }
}

class _ObservedCodec implements ui.Codec {
  _ObservedCodec(this.delegate);
  final ui.Codec delegate;
  var frames = 0;
  var disposals = 0;

  @override
  int get frameCount => delegate.frameCount;
  @override
  int get repetitionCount => delegate.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() {
    frames++;
    return delegate.getNextFrame();
  }

  @override
  void dispose() {
    disposals++;
    delegate.dispose();
  }
}

Future<String> _hash(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return sha256
      .convert(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))
      .toString();
}

Future<({ByteData bytes, String finalHash})> _reference(
    WidgetTester tester, int value) async {
  return (await tester.runAsync(() async {
    final bytes = await rootBundle.load(_asset(value));
    final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    try {
      for (var index = 0; index < codec.frameCount; index++) {
        final frame = await codec.getNextFrame();
        try {
          if (index == codec.frameCount - 1) {
            return (bytes: bytes, finalHash: await _hash(frame.image));
          }
        } finally {
          frame.image.dispose();
        }
      }
      throw StateError('The supplied dice animation has no frames.');
    } finally {
      codec.dispose();
    }
  }))!;
}

Future<void> _flushNative(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => DiceWebpFrames.debugCodecFactory = null);

  for (final corruptPoster in [false, true]) {
    testWidgets(
        'original WebP keeps its final picture when poster '
        'is ${corruptPoster ? 'corrupt' : 'missing'}', (tester) async {
      final reference = await _reference(tester, 4);
      final bundle =
          _OriginalOnlyBundle(4, reference.bytes, corruptPoster: corruptPoster);
      final codecs = <_ObservedCodec>[];
      DiceWebpFrames.debugCodecFactory = (bytes) async {
        final codec = _ObservedCodec(await ui.instantiateImageCodec(bytes));
        codecs.add(codec);
        return codec;
      };
      final first = (await tester
          .runAsync(() => DiceWebpFrames.loadFinal(bundle, _asset(4))))!;
      try {
        expect(await tester.runAsync(() => _hash(first)), reference.finalHash);
        expect(first.width, 512);
        expect(first.height, 512);
        expect(bundle.requests, [_poster(4), _asset(4)]);
        expect(codecs, hasLength(1));
        expect(codecs.single.frames, 181);
        expect(codecs.single.disposals, 1);
      } finally {
        first.dispose();
      }
      // A recycled history row owns a new handle even after the first caller
      // has disposed its handle. No asset read or second animation decode.
      final second = (await tester
          .runAsync(() => DiceWebpFrames.loadFinal(bundle, _asset(4))))!;
      try {
        expect(await tester.runAsync(() => _hash(second)), reference.finalHash);
        expect(bundle.requests, [_poster(4), _asset(4)]);
        expect(codecs, hasLength(1));
      } finally {
        second.dispose();
      }
    });
  }

  testWidgets('completed playback survives disposal without poster or redecode',
      (tester) async {
    final reference = await _reference(tester, 6);
    final bundle = _OriginalOnlyBundle(6, reference.bytes);
    final codecs = <_ObservedCodec>[];
    DiceWebpFrames.debugCodecFactory = (bytes) async {
      final codec = _ObservedCodec(await ui.instantiateImageCodec(bytes));
      codecs.add(codec);
      return codec;
    };
    final playback =
        DiceWebpPlayback.acquire(bundle, _asset(6), 'completed-final-cache');
    var released = false;
    try {
      for (var attempt = 0;
          attempt < 100 && playback.image == null;
          attempt++) {
        await _flushNative(tester);
      }
      expect(playback.image, isNotNull);
      for (var frame = 1; frame < 181; frame++) {
        await _flushNative(tester);
        final previous = playback.image;
        playback.advance(const Duration(milliseconds: 16));
        for (var attempt = 0;
            attempt < 100 && identical(previous, playback.image);
            attempt++) {
          await _flushNative(tester);
          playback.advance(Duration.zero);
        }
        expect(identical(previous, playback.image), isFalse,
            reason: 'Frame $frame must be delivered before the next one.');
      }
      expect(playback.completed, isTrue);
      expect(playback.failed, isFalse);
      expect(await tester.runAsync(() => _hash(playback.image!)),
          reference.finalHash);
      expect(codecs, hasLength(1));
      expect(codecs.single.frames, 181);
      expect(codecs.single.disposals, 1);
      playback.release();
      released = true;
      await tester.pump();
      final result = (await tester
          .runAsync(() => DiceWebpFrames.loadFinal(bundle, _asset(6))))!;
      try {
        expect(await tester.runAsync(() => _hash(result)), reference.finalHash);
        expect(bundle.requests, [_asset(6)],
            reason: 'The completed image must cover an absent poster.');
        expect(codecs, hasLength(1),
            reason: 'A recycled row must not decode the same roll again.');
      } finally {
        result.dispose();
      }
    } finally {
      if (!released) playback.release();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'concurrent original-only history loads share decode and own images',
      (tester) async {
    final reference = await _reference(tester, 2);
    final bundle = _OriginalOnlyBundle(2, reference.bytes);
    final codecs = <_ObservedCodec>[];
    DiceWebpFrames.debugCodecFactory = (bytes) async {
      final codec = _ObservedCodec(await ui.instantiateImageCodec(bytes));
      codecs.add(codec);
      return codec;
    };
    final images = (await tester.runAsync(() => Future.wait([
          DiceWebpFrames.loadFinal(bundle, _asset(2)),
          DiceWebpFrames.loadFinal(bundle, _asset(2)),
        ])))!;
    expect(images, hasLength(2));
    expect(identical(images[0], images[1]), isFalse);
    images[0].dispose();
    try {
      expect(
          await tester.runAsync(() => _hash(images[1])), reference.finalHash);
      expect(bundle.requests, [_poster(2), _asset(2)]);
      expect(codecs, hasLength(1));
      expect(codecs.single.frames, 181);
      expect(codecs.single.disposals, 1);
    } finally {
      images[1].dispose();
    }
  });

  testWidgets('missing poster and original still report an asset error',
      (tester) async {
    final bundle = _OriginalOnlyBundle(3, null);
    Object? failure;
    await tester.runAsync(() async {
      try {
        final image = await DiceWebpFrames.loadFinal(bundle, _asset(3));
        image.dispose();
      } catch (error) {
        failure = error;
      }
    });
    expect(failure, isA<FlutterError>());
    expect(bundle.requests, [_poster(3), _asset(3)]);
  });
}
