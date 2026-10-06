import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'dice_webp_frames.dart';

/// One forward pass, with only the displayed frame and one decoded next frame.
/// A short retention window preserves a roll when the chat slivers recycle it.
class DiceWebpPlayback extends ChangeNotifier {
  DiceWebpPlayback._(this._key) {
    unawaited(_load());
  }

  static final _sessions = <(AssetBundle, String, String), DiceWebpPlayback>{};
  static const _inactiveLimit = 6;
  static const _retention = Duration(seconds: 5);

  static bool hasInProgress(
      AssetBundle bundle, String asset, String messageId) {
    final playback = _sessions[(bundle, asset, messageId)];
    return playback != null && !playback._completed && !playback._failed;
  }

  static DiceWebpPlayback acquire(
      AssetBundle bundle, String asset, String messageId) {
    final key = (bundle, asset, messageId);
    final playback = _sessions.putIfAbsent(key, () => DiceWebpPlayback._(key));
    playback._expiry?.cancel();
    playback._expiry = null;
    playback._users++;
    return playback;
  }

  final (AssetBundle, String, String) _key;
  DiceWebpFrames? _frames;
  ui.Image? _image;
  ui.Image? _nextImage;
  Duration _remaining = Duration.zero;
  Timer? _expiry;
  int _users = 0;
  int _frameIndex = -1;
  bool _decoding = false;
  bool _disposed = false;
  bool _completed = false;
  bool _failed = false;

  ui.Image? get image => _image;
  bool get completed => _completed;
  bool get failed => _failed;

  /// The UI supplies only visible, foreground elapsed time.
  /// A late decode holds its current picture, then resumes in frame order;
  /// it never seeks past the rolling pictures to meet a total-duration clock.
  void advance(Duration delta) {
    final frames = _frames;
    if (_disposed ||
        _completed ||
        _failed ||
        _image == null ||
        frames == null) {
      return;
    }
    _remaining -= delta;
    if (_remaining > Duration.zero || _nextImage == null) return;
    final next = _nextImage!;
    _nextImage = null;
    _frameIndex++;
    _remaining = frames.frameDuration(_frameIndex);
    final previous = _image;
    _image = next;
    _retire(previous);
    if (_frameIndex == frames.lastIndex) {
      DiceWebpFrames.cacheFinal(_key.$1, _key.$2, next);
      _completed = true;
      _removeSession();
      frames.close();
    }
    notifyListeners();
    if (!_completed) unawaited(_prefetch());
  }

  Future<void> _load() async {
    try {
      final frames = await DiceWebpFrames.load(_key.$1, _key.$2);
      if (_disposed) {
        frames.close();
        return;
      }
      _frames = frames;
      final first = await frames.decodeNext();
      if (_disposed) {
        first?.dispose();
        return;
      }
      if (first == null) throw StateError('The dice image is unavailable.');
      _image = first;
      _frameIndex = 0;
      _remaining = frames.frameDuration(0);
      if (frames.lastIndex == 0) {
        DiceWebpFrames.cacheFinal(_key.$1, _key.$2, first);
        _completed = true;
        _removeSession();
        frames.close();
      }
      notifyListeners();
      if (!_completed) unawaited(_prefetch());
    } catch (_) {
      _fail();
    }
  }

  Future<void> _prefetch() async {
    final frames = _frames;
    if (_disposed || _completed || _failed || _decoding || frames == null) {
      return;
    }
    _decoding = true;
    try {
      final next = await frames.decodeNext();
      if (_disposed) {
        next?.dispose();
        return;
      }
      _nextImage = next;
      if (next == null) throw StateError('The next dice frame is unavailable.');
    } catch (_) {
      _fail();
    } finally {
      _decoding = false;
    }
  }

  void _fail() {
    if (_disposed) return;
    _failed = true;
    _frames?.close();
    _removeSession();
    notifyListeners();
  }

  void release() {
    assert(_users > 0);
    _users--;
    if (_users != 0) return;
    if (_completed || _failed) {
      dispose();
      return;
    }
    // A replacement State can acquire this same decoder in the next frame.
    _expiry = Timer(_retention, dispose);
    final inactive =
        _sessions.values.where((value) => value._users == 0).toList();
    for (final playback in inactive.take(
        (inactive.length - _inactiveLimit).clamp(0, _inactiveLimit + 1))) {
      playback.dispose();
    }
  }

  void _removeSession() {
    if (identical(_sessions[_key], this)) _sessions.remove(_key);
  }

  static void _retire(ui.Image? image) {
    if (image == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _expiry?.cancel();
    _removeSession();
    _frames?.close();
    _retire(_image);
    _nextImage?.dispose();
    _image = null;
    _nextImage = null;
    super.dispose();
  }
}
