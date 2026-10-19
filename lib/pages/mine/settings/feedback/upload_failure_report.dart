import 'package:flutter/services.dart';

/// Only allowlisted classifications leave the native error boundary. Native
/// errors may contain signed URLs, credentials and private filesystem paths.
class UploadFailureReport implements Exception {
  UploadFailureReport(Object error, this.operationID)
      : createdAt = DateTime.now().toUtc(),
        sdkCode = error is PlatformException &&
                RegExp(r'^-?\d{1,10}$').hasMatch(error.code)
            ? error.code
            : null,
        category = _classify(error),
        stage = _stage(error),
        httpStatus = _status(error);

  final String operationID;
  final DateTime createdAt;
  final String? sdkCode;
  final String category;
  final String? stage;
  final String? httpStatus;

  static String _text(Object error) => error is PlatformException
      ? '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase()
      : error.toString().toLowerCase();

  static String? _status(Object error) =>
      RegExp(r'(?:status code|statuscode|http status)[:=\s]+([1-5]\d{2})\b')
          .firstMatch(_text(error))
          ?.group(1);

  static String? _stage(Object error) => RegExp(
          r'\bsdk_log_stage=(prepare|collect|archive|transfer|register)\b')
      .firstMatch(_text(error))
      ?.group(1);

  static String _classify(Object error) {
    final text = _text(error);
    for (final entry in <String, List<String>>{
      'dns': ['no such host', 'failed host lookup', 'name resolution'],
      'tls': [
        'x509:',
        'certificate verify',
        'tls handshake',
        'handshakeexception'
      ],
      'signature_expired': [
        'requestexpired',
        'request has expired',
        'expiredtoken'
      ],
      'signature_invalid': ['signaturedoesnotmatch'],
      'storage_access_denied': ['accessdenied'],
      'upload_session_missing': ['nosuchupload'],
      'log_file_missing': ['not found log file'],
      'log_upload_busy': ['log file is uploading'],
      'local_disk_full': ['no space left on device', 'disk full', 'enospc'],
      'log_line_too_long': ['bufio.scanner: token too long'],
      'part_size_mismatch': ['part filesize not match'],
      'timeout': ['timed out', 'timeout', 'deadline exceeded'],
      'connection_reset': ['connection reset', 'broken pipe', 'unexpected eof'],
      'network_unreachable': ['network is unreachable', 'no route to host'],
      'local_file_access': ['permission denied', 'no such file or directory'],
    }.entries) {
      if (entry.value.any(text.contains)) return entry.key;
    }
    return _status(error) != null ? 'http_failure' : 'unclassified';
  }

  String get text => [
        'SDK log upload failed',
        'time=${createdAt.toIso8601String()}',
        'operationID=$operationID',
        'category=$category',
        if (stage != null) 'stage=$stage',
        if (sdkCode != null) 'sdkCode=$sdkCode',
        if (httpStatus != null) 'httpStatus=$httpStatus',
      ].join('\n');

  @override
  String toString() => text;
}
