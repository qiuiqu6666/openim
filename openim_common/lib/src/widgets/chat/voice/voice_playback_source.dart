import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../../config.dart';
import '../../../utils/media/native_media_file.dart';
import '../../../utils/media/openim_media_url.dart';
import 'voice_playback_log.dart';

/// Use the same downloaded audio as waveform extraction, so native players do
/// not need a second streaming connection (or HTTP range support) to play it.
class VoicePlaybackSource {
  const VoicePlaybackSource.file(this.value, {this.fallbackUrl})
      : isFile = true;
  const VoicePlaybackSource.remote(this.value)
      : isFile = false,
        fallbackUrl = null;

  final String value;
  final bool isFile;
  final String? fallbackUrl;

  static Future<VoicePlaybackSource> load(Message message,
      {Future<File> Function(String url)? download,
      String? imApiUrl,
      Duration downloadTimeout = const Duration(seconds: 8)}) async {
    final sound = message.soundElem;
    if (sound == null) throw StateError('Missing audio');
    final raw = sound.sourceUrl?.trim() ?? '';
    final uri = Uri.tryParse(raw);
    final url = uri != null &&
            uri.hasAuthority &&
            (uri.scheme == 'https' || uri.scheme == 'http')
        ? OpenIMMediaUrl.resolve(raw, imApiUrl: imApiUrl ?? Config.imApiUrl)
        : null;
    final path = sound.soundPath?.trim();
    if (path != null && path.isNotEmpty) {
      final file =
          path.startsWith('file:') ? File.fromUri(Uri.parse(path)) : File(path);
      if (await _usable(file)) {
        final playable = await NativeMediaFile.prepare(file);
        return VoicePlaybackSource.file(playable.path, fallbackUrl: url);
      }
    }
    if (url == null) throw StateError('Missing audio URL');
    try {
      VoicePlaybackLog.write('download_start');
      final file = await (download ?? DefaultCacheManager().getSingleFile)(url)
          .timeout(downloadTimeout);
      if (await _usable(file)) {
        VoicePlaybackLog.write('download_ready');
        final playable = await NativeMediaFile.prepare(file);
        return VoicePlaybackSource.file(playable.path, fallbackUrl: url);
      }
      throw StateError('Empty downloaded audio');
    } catch (error) {
      // A failed or slow cache download must not prevent a direct stream from
      // working. Late downloads may populate the shared cache, never playback.
      VoicePlaybackLog.write('download_fallback', error: error);
      return VoicePlaybackSource.remote(url);
    }
  }

  static Future<bool> _usable(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } on FileSystemException {
      return false;
    }
  }
}
