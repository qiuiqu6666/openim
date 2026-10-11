import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/src/widgets/chat/voice/voice_playback_log.dart';

void main() {
  test('diagnostics retain error codes without signed URLs or native details',
      () {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    addTearDown(() => debugPrint = previous);
    VoicePlaybackLog.write('download_fallback',
        error: HttpExceptionWithStatus(403, 'URL token=secret',
            uri: Uri.parse('https://cdn.test/audio?token=secret')));
    VoicePlaybackLog.write('load_file_failed',
        error: PlayerException(2004, 'signed URL token=secret /local/audio', 0),
        attempt: 3);
    final log = lines.join('\n');
    expect(log, contains('"httpStatus":403'));
    expect(log, contains('"playerCode":2004'));
    expect(log, contains('"attempt":3'));
    expect(log, isNot(contains('secret')));
    expect(log, isNot(contains('/local/audio')));
    expect(log, isNot(contains('cdn.test')));
  });
}
