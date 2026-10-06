import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// A localized, deliberately sanitized error. Provider responses and credentials
/// must never become user-visible errors or logs.
class VoiceToTextException implements Exception {
  const VoiceToTextException(this.messageKey);
  final String messageKey;

  @override
  String toString() => messageKey;
}

/// Sends audio to our authenticated proxy; Tencent credentials stay server-side.
class VoiceToTextService {
  VoiceToTextService({
    Dio? client,
    Dio? downloadClient,
    String? endpoint,
    String? businessUrl,
    String? Function()? tokenProvider,
    Future<Directory> Function()? temporaryDirectory,
    void Function(String message)? logSink,
  })  : _client = client ?? _newClient(),
        _downloadClient = downloadClient ?? _newClient(),
        _ownsClient = client == null,
        _ownsDownloadClient = downloadClient == null,
        _endpoint = endpoint,
        _businessUrl = businessUrl,
        _tokenProvider = tokenProvider ?? (() => DataSp.chatToken),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _logSink = logSink ?? _consoleLog;

  static const maxAudioBytes = 100 * 1024 * 1024;
  static const maxDurationSeconds = 2 * 60 * 60;
  static const _configuredEndpoint = String.fromEnvironment('ASR_PROXY_URL');
  final Dio _client;
  // Downloads use a separate client, so chat authentication never goes to OSS.
  final Dio _downloadClient;
  final bool _ownsClient;
  final bool _ownsDownloadClient;
  final String? _endpoint;
  final String? _businessUrl;
  final String? Function() _tokenProvider;
  final Future<Directory> Function() _temporaryDirectory;
  final Set<CancelToken> _pending = {};
  final Map<CancelToken, _AsrDiagnostic> _diagnostics = {};
  final void Function(String message) _logSink;
  bool _disposed = false;

  static void _consoleLog(String message) {
    // developer.log alone is a VM service event and may be absent from logcat
    // and flutter run output. Also emit the already sanitized line to stdout.
    debugPrint(message);
    Logger.print(message, onlyConsole: true);
  }

  void _log(CancelToken token, String event,
      [Map<String, Object?> details = const {}]) {
    final diagnostic = _diagnostics[token];
    if (diagnostic == null) return;
    try {
      _logSink('[ASR] ${jsonEncode({
            'event': event,
            'operationID': diagnostic.operationID,
            'stage': diagnostic.stage,
            'elapsedMs': diagnostic.clock.elapsedMilliseconds,
            ...details,
          })}');
    } catch (_) {
      // Diagnostics must never interrupt recognition or cancellation.
    }
  }

  static String _safeEndpoint(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return 'invalid';
    // Never log URL credentials, signed queries, fragments or arbitrary paths.
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path == '/chat/asr/transcribe' ? uri.path : '/[custom-path]',
    ).toString();
  }

  static Map<String, Object?> _responseDiagnostic(Response<dynamic>? response) {
    final body = response?.data;
    final code = body is Map ? body['errorCode'] : null;
    final errCode = body is Map ? body['errCode'] : null;
    final data = body is Map ? body['data'] : null;
    final requestId = data is Map ? data['requestId'] : null;
    final contentTypes = response?.headers[Headers.contentTypeHeader];
    final mime = contentTypes?.isNotEmpty == true
        ? contentTypes!.first.split(';').first.trim().toLowerCase()
        : null;
    return {
      'httpStatus': response?.statusCode,
      'bodyType': body == null
          ? 'empty'
          : body is Map
              ? 'json'
              : 'non-json',
      if (['application/json', 'text/html', 'text/plain'].contains(mime))
        'contentType': mime,
      if (errCode is int && errCode >= 0 && errCode <= 9999) 'errCode': errCode,
      if (code is String && _knownProxyErrors.containsKey(code))
        'errorCode': code,
      if (requestId is String &&
          RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$')
              .hasMatch(requestId))
        'requestId': requestId,
    };
  }

  static Dio _newClient() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ));

  String get _url =>
      _endpoint ??
      (_configuredEndpoint.isNotEmpty
          ? _configuredEndpoint
          : Uri.parse(_businessUrl ?? Config.appAuthUrl)
              .resolve('/chat/asr/transcribe')
              .toString());

  Future<String> transcribeFile(File file,
          {num? duration, CancelToken? cancelToken}) =>
      _run(cancelToken, (token) => _transcribeFile(file, duration, token),
          source: 'file');

  Future<String> transcribeMessage(Message message,
          {CancelToken? cancelToken}) =>
      _run(cancelToken, (token) async {
        final sound = message.soundElem;
        if (sound == null) {
          throw const VoiceToTextException('voiceToTextMissingAudio');
        }
        // Older messages can omit duration or use zero for an unknown value.
        final duration = sound.duration == 0 ? null : sound.duration;
        _validateDuration(duration);
        final local = sound.soundPath;
        if (local != null && local.isNotEmpty) {
          final file = File(local);
          if (await file.exists()) {
            _log(token, 'audio_source', {'source': 'local'});
            return _transcribeFile(file, duration, token);
          }
        }
        final remote = Uri.tryParse(sound.sourceUrl ?? '');
        if (remote == null ||
            !remote.hasAuthority ||
            (remote.scheme != 'https' && remote.scheme != 'http')) {
          throw const VoiceToTextException('voiceToTextMissingAudio');
        }
        if ((sound.dataSize ?? 0) > maxAudioBytes) {
          throw const VoiceToTextException('voiceToTextTooLarge');
        }
        _checkActive(token);
        final directory = await _temporaryDirectory();
        _checkActive(token);
        // Keep the extension only for raw PCM (which has no magic header).
        final extension = path.extension(remote.path).toLowerCase();
        final temporary = File(path.join(directory.path,
            'asr-${const Uuid().v4()}${extension == '.pcm' ? '.pcm' : ''}'));
        try {
          _log(token, 'audio_source', {'source': 'remote'});
          await _download(remote, temporary, token);
          return await _transcribeFile(temporary, duration, token);
        } finally {
          try {
            if (await temporary.exists()) await temporary.delete();
          } on FileSystemException {
            // A cleanup error must not hide the original cancellation/failure.
          }
        }
      }, source: 'message');

  Future<String> _run(CancelToken? external,
      Future<String> Function(CancelToken token) operation,
      {required String source}) async {
    final token = CancelToken();
    _diagnostics[token] = _AsrDiagnostic();
    if (external != null) {
      if (external.isCancelled) token.cancel();
      unawaited(external.whenCancel.then((_) => token.cancel()));
    }
    _pending.add(token);
    _log(token, 'start', {'source': source});
    try {
      _checkActive(token);
      final text = await operation(token);
      _log(token, 'success');
      return text;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        _log(token, 'cancelled');
        rethrow;
      }
      final timedOut = error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout;
      final messageKey = timedOut
          ? 'voiceToTextTimeout'
          : _proxyErrorMessageKey(
              error.response?.data,
              status: error.response?.statusCode,
              fallback: 'voiceToTextNetworkFailed',
            );
      _log(token, 'failure', {
        'transport': error.type.name,
        'messageKey': messageKey,
        ..._responseDiagnostic(error.response),
      });
      token.cancel();
      throw VoiceToTextException(messageKey);
    } on VoiceToTextException catch (error) {
      _log(token, 'failure', {'messageKey': error.messageKey});
      rethrow;
    } on FileSystemException {
      _log(token, 'failure', {'messageKey': 'voiceToTextMissingAudio'});
      token.cancel();
      throw const VoiceToTextException('voiceToTextMissingAudio');
    } catch (_) {
      _log(token, 'failure', {'messageKey': 'voiceToTextFailed'});
      rethrow;
    } finally {
      _pending.remove(token);
      _diagnostics.remove(token);
    }
  }

  static String _proxyErrorMessageKey(dynamic body,
      {int? status, String fallback = 'voiceToTextFailed'}) {
    if (status == 401 || status == 403) return 'voiceToTextAuthFailed';
    // Translate only stable proxy codes. Diagnostic text and provider details
    // must never become user-visible errors, even for unknown responses.
    final code = body is Map ? (body['errorCode'] ?? body['errCode']) : null;
    final translated = code is String ? _knownProxyErrors[code] : null;
    if (translated != null) return translated;
    switch (status) {
      case 400:
        return 'voiceToTextFailed';
      case 413:
        return 'voiceToTextTooLarge';
      case 415:
        return 'voiceToTextUnsupportedFormat';
      case 429:
        return 'voiceToTextRateLimited';
      case 504:
        return 'voiceToTextTimeout';
      case 404:
      case 502:
      case 503:
        return 'voiceToTextUnavailable';
      default:
        return fallback;
    }
  }

  static const _knownProxyErrors = {
    'BAD_REQUEST': 'voiceToTextFailed',
    'BAD_FORMAT': 'voiceToTextUnsupportedFormat',
    'BAD_DURATION': 'voiceToTextInvalidDuration',
    'EMPTY_AUDIO': 'voiceToTextMissingAudio',
    'UNKNOWN_PARAM': 'voiceToTextFailed',
    'AUTH_INVALID_TOKEN': 'voiceToTextAuthFailed',
    'PAYLOAD_TOO_LARGE': 'voiceToTextTooLarge',
    'UNSUPPORTED_MEDIA': 'voiceToTextUnsupportedFormat',
    'NO_SPEECH': 'voiceToTextEmpty',
    'AUDIO_TOO_LONG': 'voiceToTextTooLong',
    'RATE_LIMITED': 'voiceToTextRateLimited',
    'UPSTREAM_ERROR': 'voiceToTextUnavailable',
    'AUTH_UNAVAILABLE': 'voiceToTextUnavailable',
    'TIMEOUT': 'voiceToTextTimeout',
    // Compatibility with earlier proxy deployments.
    'AUDIO_TOO_LARGE': 'voiceToTextTooLarge',
    'UNSUPPORTED_AUDIO_FORMAT': 'voiceToTextUnsupportedFormat',
    'AUDIO_DECODE_FAILED': 'voiceToTextUnsupportedFormat',
  };

  void _validateDuration(num? duration) {
    if (duration == null) return;
    if (!duration.isFinite || duration <= 0) {
      throw const VoiceToTextException('voiceToTextInvalidDuration');
    }
    if (duration > maxDurationSeconds) {
      throw const VoiceToTextException('voiceToTextTooLong');
    }
  }

  void _checkActive(CancelToken token) {
    if (_disposed) token.cancel();
    if (token.isCancelled) throw token.cancelError!;
  }

  Future<String> _transcribeFile(
      File file, num? duration, CancelToken token) async {
    _diagnostics[token]?.stage = 'validate_audio';
    _validateDuration(duration);
    _checkActive(token);
    final size = await file.length();
    if (size <= 0) {
      throw const VoiceToTextException('voiceToTextMissingAudio');
    }
    if (size > maxAudioBytes) {
      throw const VoiceToTextException('voiceToTextTooLarge');
    }
    final handle = await file.open();
    late Uint8List header;
    try {
      header = await handle.read(256);
    } finally {
      await handle.close();
    }
    final format = sniffAudioFormat(header, file.path);
    if (format == null) {
      throw const VoiceToTextException('voiceToTextUnsupportedFormat');
    }
    final authToken = _tokenProvider();
    if (authToken == null || authToken.isEmpty) {
      throw const VoiceToTextException('voiceToTextAuthFailed');
    }
    _checkActive(token);
    final url = _url;
    _diagnostics[token]?.stage = 'transcribe';
    _log(token, 'request', {
      'endpoint': _safeEndpoint(url),
      'voiceFormat': format,
      'audioBytes': size,
      if (duration != null) 'duration': duration,
    });
    final response = await _client.post<dynamic>(url,
        onSendProgress: (sent, total) {
      final diagnostic = _diagnostics[token];
      if (total > 0 && sent == total && diagnostic?.uploadLogged == false) {
        diagnostic!.uploadLogged = true;
        _log(token, 'upload_complete', {'audioBytes': sent});
        diagnostic.stage = 'recognize';
      }
    },
        // Read only as the transport consumes data; never buffer a large audio.
        data: file.openRead(0, size).map((chunk) {
          _checkActive(token);
          return chunk;
        }),
        queryParameters: {
          'voiceFormat': format,
          if (duration != null) 'duration': duration,
        },
        cancelToken: token,
        options: Options(
          contentType: 'application/octet-stream',
          responseType: ResponseType.json,
          headers: {
            'token': authToken,
            'operationID': _diagnostics[token]!.operationID,
            Headers.contentLengthHeader: size,
          },
        ));
    _checkActive(token);
    _log(token, 'response', _responseDiagnostic(response));
    final body = response.data;
    if (body is! Map || body['errCode'] is! int) {
      throw const VoiceToTextException('voiceToTextFailed');
    }
    if (body['errCode'] != 0) {
      // errMsg can contain provider diagnostics; never display it verbatim.
      throw VoiceToTextException(
          _proxyErrorMessageKey(body, status: response.statusCode));
    }
    final data = body['data'];
    if (data is! Map || data['text'] is! String) {
      throw const VoiceToTextException('voiceToTextFailed');
    }
    final text = (data['text'] as String).trim();
    if (text.isEmpty) {
      throw const VoiceToTextException('voiceToTextEmpty');
    }
    return text;
  }

  Future<void> _download(Uri url, File destination, CancelToken token) async {
    _diagnostics[token]?.stage = 'download';
    _log(token, 'download_start');
    final options = Options(responseType: ResponseType.stream)
        .compose(_downloadClient.options, url.toString(), cancelToken: token);
    options.headers.removeWhere((name, _) =>
        name.toLowerCase() == 'token' || name.toLowerCase() == 'authorization');
    final response = await _downloadClient.fetch<ResponseBody>(options);
    _checkActive(token);
    final body = response.data;
    if (body == null) {
      throw const VoiceToTextException('voiceToTextNetworkFailed');
    }
    final reportedSize =
        int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '');
    if (reportedSize != null && reportedSize > maxAudioBytes) {
      token.cancel();
      throw const VoiceToTextException('voiceToTextTooLarge');
    }
    final sink = destination.openWrite();
    final chunks = StreamIterator(body.stream);
    var received = 0;
    try {
      while (await Future.any<bool>([
        chunks.moveNext(),
        token.whenCancel.then((_) => false),
      ])) {
        _checkActive(token);
        final chunk = chunks.current;
        received += chunk.length;
        if (received > maxAudioBytes) {
          token.cancel();
          throw const VoiceToTextException('voiceToTextTooLarge');
        }
        sink.add(chunk);
        // Apply back pressure so disk writes do not accumulate the full audio.
        await sink.flush();
      }
      _checkActive(token);
      _log(token, 'download_complete', {'audioBytes': received});
    } finally {
      await chunks.cancel();
      await sink.close();
    }
  }

  /// Magic bytes take precedence over a misleading or absent file extension.
  /// PCM is the sole extension fallback: uncompressed PCM has no file header.
  static String? sniffAudioFormat(List<int> bytes, [String filePath = '']) {
    bool at(int offset, String signature) {
      if (bytes.length < offset + signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[offset + index] != signature.codeUnitAt(index)) return false;
      }
      return true;
    }

    if (at(0, 'RIFF') && at(8, 'WAVE')) return 'wav';
    if (at(0, '#!AMR\n') || at(0, '#!AMR-WB\n')) return 'amr';
    if (at(0, '#!SILK_V3') || at(1, '#!SILK_V3')) return 'silk';
    if (at(0, 'Speex ')) return 'speex';
    if (at(0, 'OggS')) {
      for (var index = 4; index < bytes.length; index++) {
        if (at(index, 'OpusHead')) return 'ogg-opus';
        if (at(index, 'Speex ')) return 'speex';
      }
      return null; // Ogg Vorbis is not a supported Tencent input format.
    }
    if (at(4, 'ftyp')) {
      const brands = ['M4A ', 'M4B ', 'isom', 'iso2', 'mp41', 'mp42'];
      if (brands.any((brand) => at(8, brand))) return 'm4a';
      return null;
    }
    if (at(0, 'ID3')) return 'mp3';
    if (bytes.length >= 4 && bytes[0] == 0xff) {
      // ADTS AAC sync has zero layer bits; MPEG audio has nonzero layer bits.
      if ((bytes[1] & 0xf6) == 0xf0) return 'aac';
      if ((bytes[1] & 0xe0) == 0xe0 &&
          (bytes[1] & 0x06) != 0 &&
          (bytes[1] & 0x18) != 0x08 &&
          (bytes[2] & 0xf0) != 0xf0 &&
          (bytes[2] & 0x0c) != 0x0c) {
        return 'mp3';
      }
    }
    if (path.extension(filePath).toLowerCase() == '.pcm' && bytes.isNotEmpty) {
      return 'pcm';
    }
    return null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final token in _pending.toList()) {
      token.cancel();
    }
    _pending.clear();
    if (_ownsClient) _client.close(force: true);
    if (_ownsDownloadClient) _downloadClient.close(force: true);
  }
}

class _AsrDiagnostic {
  final String operationID = const Uuid().v4();
  final Stopwatch clock = Stopwatch()..start();
  String stage = 'validate';
  bool uploadLogged = false;
}
