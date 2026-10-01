import 'package:record/record.dart';

class AudioRecorderClass {
  final _recorder = AudioRecorder();
  Future<void> start(RecordConfig config, {required String path}) =>
      _recorder.start(config, path: path);
  Future<String> stop({Function(String)? onWebCallback}) async =>
      await _recorder.stop() ?? '';
  void dispose() {
    _recorder.dispose();
  }
}
