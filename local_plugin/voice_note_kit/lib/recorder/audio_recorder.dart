import 'package:record/record.dart';

class AudioRecorderClass {
  AudioRecorder? _recorder = AudioRecorder();
  bool _needsRelease = false;
  bool _disposed = false;

  Future<void> start(RecordConfig config, {required String path}) async {
    if (_disposed) throw StateError('The recorder has been disposed');
    // A failed native release must not leave an old microphone session alive
    // while a retry creates a second recorder.
    if (_needsRelease) {
      await _recorder?.dispose();
      _recorder = null;
      _needsRelease = false;
    }
    final recorder = _recorder ??= AudioRecorder();
    await recorder.start(config, path: path);
  }

  Future<String> stop({Function(String)? onWebCallback}) async =>
      await _recorder?.stop() ?? '';

  Stream<Amplitude> get amplitude =>
      _recorder?.onAmplitudeChanged(const Duration(milliseconds: 100)) ??
      const Stream<Amplitude>.empty();

  /// Stops an unclaimed recording, releasing the microphone even when native
  /// stop fails. Returns the original failure for the widget's existing error
  /// callback; successful normal cleanup still performs exactly one stop.
  Future<Object?> discard() async {
    final recorder = _recorder;
    if (recorder == null) return null;
    try {
      await recorder.stop();
      return null;
    } catch (stopError) {
      // record_platform_interface 1.4.0 does not await its method-channel
      // cancel call. Its returned Future cannot confirm native completion or
      // catch a failure, so release this recorder directly instead. The widget
      // remains responsible for deleting its unclaimed temporary file.
      try {
        await recorder.dispose();
        _recorder = null;
        _needsRelease = false;
        return stopError;
      } catch (releaseError) {
        _needsRelease = true;
        return StateError(
            'Unable to release the microphone: $releaseError; $stopError');
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _recorder?.dispose();
    _recorder = null;
  }
}
