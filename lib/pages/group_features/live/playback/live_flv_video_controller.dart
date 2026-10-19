import 'dart:async';
import 'package:video_player/video_player.dart';
import 'live_flv_engine.dart';

/// Adapts iOS FLV to the existing live owner, without registering a global
/// video_player backend or changing ordinary video playback.
class LiveFlvVideoController extends VideoPlayerController {
  LiveFlvVideoController(super.url, {LiveFlvEngine Function()? engineFactory})
      : _engineFactory = engineFactory ?? MediaKitLiveFlvEngine.new,
        super.networkUrl();

  final LiveFlvEngine Function() _engineFactory;
  LiveFlvEngine? engine;
  final _initialized = Completer<void>();
  Future<void>? _initializing;
  bool _closed = false;

  void _changed() {
    if (_closed) return;
    value = engine!.value;
    if ((value.isInitialized || value.hasError) && !_initialized.isCompleted) {
      _initialized.complete();
    }
  }

  @override
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (_closed) return;
    final current = engine = _engineFactory();
    current.addListener(_changed);
    await current.open(Uri.parse(dataSource));
    if (_closed) return;
    _changed();
    await _initialized.future;
    if (!_closed && value.hasError) throw StateError('FLV playback failed');
  }

  @override
  Future<void> play() async {
    if (!_closed) await engine?.play();
  }

  @override
  Future<void> pause() async {
    if (!_closed) await engine?.pause();
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_closed) await engine?.setVolume(volume);
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    if (!_initialized.isCompleted) _initialized.complete();
    engine?.removeListener(_changed);
    try {
      await engine?.close();
    } finally {
      await super.dispose();
    }
  }
}
