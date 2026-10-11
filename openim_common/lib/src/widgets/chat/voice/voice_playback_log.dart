import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show HttpExceptionWithStatus;
import 'package:just_audio/just_audio.dart';

/// Do not include signed media URLs, local paths or native exception messages.
class VoicePlaybackLog {
  static void write(String stage, {Object? error, int? attempt}) {
    if (!kDebugMode) return;
    debugPrint('[语音播放] ${jsonEncode({
          'stage': stage,
          'platform': defaultTargetPlatform.name,
          if (attempt != null) 'attempt': attempt,
          if (error != null) 'errorType': error.runtimeType.toString(),
          if (error is PlayerException) 'playerCode': error.code,
          if (error is HttpExceptionWithStatus) 'httpStatus': error.statusCode,
          if (error is TimeoutException) 'timeout': true,
        })}');
  }
}
