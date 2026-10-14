import 'dart:async';
import 'dart:ui' as ui;

// Exercise the vendored plugin's internal decode ownership contract directly.
// ignore: depend_on_referenced_packages
import 'package:extended_image_library/src/network/loading/image_load_scheduler.dart';
// ignore: depend_on_referenced_packages
import 'package:extended_image_library/src/network/loading/prepared_image_codec.dart';
import 'package:flutter_test/flutter_test.dart';

class _Codec implements ui.Codec {
  _Codec(this.frame);
  final Future<ui.FrameInfo> frame;
  int decoded = 0;
  bool disposed = false;
  @override
  int get frameCount => 1;
  @override
  int get repetitionCount => 0;
  @override
  Future<ui.FrameInfo> getNextFrame() {
    decoded++;
    return frame;
  }

  @override
  void dispose() => disposed = true;
}

Future<ui.FrameInfo> _frame() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff123456), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  final codec = await ui.instantiateImageCodec(png!.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prepared first frame is reused without a second pixel decode',
      () async {
    final frame = await _frame();
    final source = _Codec(Future.value(frame));
    final prepared =
        await prepareImageCodec(() async => source, ImageLoadSignal());
    expect(source.decoded, 1);
    expect(await prepared.getNextFrame(), same(frame));
    expect(source.decoded, 1);
    frame.image.dispose();
    prepared.dispose();
    expect(source.disposed, isTrue);
  });

  test(
      'cancellation during a native decode disposes its eventual frame and codec',
      () async {
    final delayed = Completer<ui.FrameInfo>();
    final source = _Codec(delayed.future);
    final signal = ImageLoadSignal();
    final result = prepareImageCodec(() async => source, signal);
    final failure = expectLater(result, throwsA(isA<ImageLoadCancelled>()));
    await Future<void>.delayed(Duration.zero);
    signal.cancel();
    final frame = await _frame();
    delayed.complete(frame);
    await failure;
    expect(source.disposed, isTrue);
    expect(frame.image.debugDisposed, isTrue);
  });

  test('the concurrency slot includes actual first-frame decoding', () async {
    final scheduler = ImageLoadScheduler(maximumActive: 1);
    final delayed = Completer<ui.FrameInfo>();
    final first = _Codec(delayed.future);
    final firstSignal = ImageLoadSignal();
    var secondStarted = false;
    final preparedFirst = scheduler.run(
        firstSignal, () => prepareImageCodec(() async => first, firstSignal));
    final second = scheduler.run(ImageLoadSignal(), () async {
      secondStarted = true;
      return 1;
    });
    await Future<void>.delayed(Duration.zero);
    expect(first.decoded, 1);
    expect(secondStarted, isFalse);
    delayed.complete(await _frame());
    final prepared = await preparedFirst;
    expect(await second, 1);
    prepared.dispose(); // First frame has not been consumed; dispose owns it.
    expect(first.disposed, isTrue);
  });
}
