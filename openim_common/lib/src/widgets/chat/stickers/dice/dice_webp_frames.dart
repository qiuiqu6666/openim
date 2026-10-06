import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Decodes forward through a WebP without retaining every decoded image.
/// The caller owns returned images; this object owns only its native codec.
class DiceWebpFrames {
  DiceWebpFrames._(this._codec, this._frameEnds);

  static const _finalCacheLimit = 6;
  static final _finalFrames = <(AssetBundle, String), ui.Image>{};
  static final _finalLoads = <(AssetBundle, String), Future<ui.Image>>{};

  @visibleForTesting
  static Future<ui.Codec> Function(Uint8List bytes)? debugCodecFactory;

  final ui.Codec _codec;
  final List<int> _frameEnds;
  bool _decoding = false;
  bool _closed = false;
  bool _codecDisposed = false;
  int frameIndex = -1;

  int get lastIndex => _frameEnds.length - 1;
  Duration get duration => Duration(milliseconds: _frameEnds.last);

  static Future<DiceWebpFrames> load(AssetBundle bundle, String asset) async {
    final data = await bundle.load(asset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    // Flutter's multi-frame codec decodes animated WebP at its native size.
    // Preserve its original pixels; memory stays bounded by sequential decoding.
    final codec = await (debugCodecFactory ?? ui.instantiateImageCodec)(bytes);
    final durations = _webpDurations(bytes);
    // A still WebP or a decoder without ANMF metadata has one static frame.
    // Animated dice assets always supply their original ANMF frame durations.
    final frameEnds = <int>[];
    var end = 0;
    for (var index = 0; index < codec.frameCount; index++) {
      final milliseconds =
          durations.length == codec.frameCount ? durations[index] : 100;
      end += milliseconds > 0 ? milliseconds : 1;
      frameEnds.add(end);
    }
    return DiceWebpFrames._(codec, frameEnds);
  }

  Duration frameDuration(int index) => Duration(
      milliseconds:
          _frameEnds[index] - (index == 0 ? 0 : _frameEnds[index - 1]));

  /// Call serially. Every decoded animation frame is delivered to its caller.
  Future<ui.Image?> decodeNext() async {
    if (_closed || frameIndex >= lastIndex) return null;
    assert(!_decoding, 'Dice WebP decoding must be serial.');
    _decoding = true;
    try {
      final frame = await _codec.getNextFrame();
      frameIndex++;
      if (_closed) {
        frame.image.dispose();
        return null;
      }
      return frame.image;
    } finally {
      _decoding = false;
      if (_closed) _disposeCodec();
    }
  }

  void close() {
    _closed = true;
    // getNextFrame must finish before disposing its native codec.
    if (!_decoding) _disposeCodec();
  }

  void _disposeCodec() {
    if (_codecDisposed) return;
    _codecDisposed = true;
    _codec.dispose();
  }

  /// Only six final textures are shared, never all 181 animation frames.
  static Future<ui.Image> loadFinal(AssetBundle bundle, String asset) async {
    final key = (bundle, asset);
    final cached = _finalFrames.remove(key);
    if (cached != null) {
      _finalFrames[key] = cached;
      return cached.clone();
    }
    final pending = _finalLoads.putIfAbsent(key, () async {
      final image = await _loadFinalImage(bundle, asset);
      try {
        cacheFinal(bundle, asset, image);
        return image;
      } catch (_) {
        image.dispose();
        rethrow;
      }
    });
    try {
      return (await pending).clone();
    } finally {
      // The load's image is an independent handle from the cached clone.
      // Release it after every waiter has cloned it in this microtask turn.
      if (identical(_finalLoads[key], pending)) {
        _finalLoads.remove(key);
        pending.then((image) {
          scheduleMicrotask(image.dispose);
        }, onError: (Object _, StackTrace __) {});
      }
    }
  }

  static Future<ui.Image> _loadFinalImage(
      AssetBundle bundle, String asset) async {
    try {
      // A precomposited still avoids decoding invisible animation frames
      // for every cold history/thumbnail on the engine's shared IO queue.
      final poster = asset.replaceFirst(RegExp(r'\.webp$'), '_final.webp');
      final data = await bundle.load(poster);
      final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // Older installed resource bundles may contain only the original WebP.
      // Decode its composited last frame once and share the cached result.
      final frames = await load(bundle, asset);
      ui.Image? image;
      try {
        while (frames.frameIndex < frames.lastIndex) {
          final next = await frames.decodeNext();
          if (next == null) throw StateError('Dice WebP has no final frame.');
          image?.dispose();
          image = next;
        }
        if (image == null) throw StateError('Dice WebP has no frames.');
        final result = image;
        image = null;
        return result;
      } finally {
        image?.dispose();
        frames.close();
      }
    }
  }

  static void cacheFinal(AssetBundle bundle, String asset, ui.Image image) {
    final key = (bundle, asset);
    _finalFrames.remove(key)?.dispose();
    _finalFrames[key] = image.clone();
    while (_finalFrames.length > _finalCacheLimit) {
      _finalFrames.remove(_finalFrames.keys.first)?.dispose();
    }
  }

  static List<int> _webpDurations(Uint8List bytes) {
    final result = <int>[];
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WEBP') {
      return result;
    }
    final data = ByteData.sublistView(bytes);
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final length = data.getUint32(offset + 4, Endian.little);
      final payload = offset + 8;
      if (payload + length > bytes.length) return <int>[];
      if (length >= 16 &&
          String.fromCharCodes(bytes.sublist(offset, offset + 4)) == 'ANMF') {
        result.add(bytes[payload + 12] |
            bytes[payload + 13] << 8 |
            bytes[payload + 14] << 16);
      }
      offset = payload + length + (length & 1);
    }
    return result;
  }
}
