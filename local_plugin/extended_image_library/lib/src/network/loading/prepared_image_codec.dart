import 'dart:ui' as ui;

import 'image_load_scheduler.dart';

/// Codec construction may be lazy. Keep the initial pixel decode inside the
/// scheduler slot, then hand that same first frame to Flutter without decoding
/// it twice. Subsequent animation frames remain owned by Flutter's completer.
Future<ui.Codec> prepareImageCodec(
  Future<ui.Codec> Function() load,
  ImageLoadSignal signal,
) async {
  final codec = await load();
  ui.FrameInfo? first;
  try {
    signal.check();
    first = await codec.getNextFrame();
    signal.check();
    return _PreparedImageCodec(codec, first);
  } catch (_) {
    first?.image.dispose();
    codec.dispose();
    rethrow;
  }
}

class _PreparedImageCodec implements ui.Codec {
  _PreparedImageCodec(this._codec, this._first);
  final ui.Codec _codec;
  ui.FrameInfo? _first;

  @override
  int get frameCount => _codec.frameCount;
  @override
  int get repetitionCount => _codec.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() {
    final first = _first;
    _first = null;
    return first == null ? _codec.getNextFrame() : Future.value(first);
  }

  @override
  void dispose() {
    _first?.image.dispose();
    _first = null;
    _codec.dispose();
  }
}
