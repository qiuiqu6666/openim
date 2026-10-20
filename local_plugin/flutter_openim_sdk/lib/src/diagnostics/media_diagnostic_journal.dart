import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Bounded, structural evidence retained independently of the noisy SDK log.
/// Only sanitized events are accepted; never store message bodies or URLs.
class MediaDiagnosticJournal {
  static const capacity = 512;
  final _events = <Map<String, dynamic>>[];
  Future<void> _pending = Future.value();
  File? _file;
  int _diskLines = 0;

  void configure(String directory) {
    _enqueue(() async {
      final file = File('$directory/media-diagnostics.jsonl');
      if (_file?.path == file.path) return;
      _file = file;
      _events.clear();
      _diskLines = 0;
      if (!await file.exists()) return;
      // Stream, rather than loading a possibly damaged or oversized file.
      await for (final line in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        _diskLines++;
        if (line.length > 4096) continue;
        try {
          final value = jsonDecode(line);
          if (value is Map<String, dynamic>) _retain(_sanitize(value));
        } on FormatException {
          // An interrupted final append must not hide preceding events.
        }
      }
    });
  }

  void capture(String? text) {
    if (text == null || !text.startsWith('chat_media ')) return;
    try {
      final value = jsonDecode(text.substring('chat_media '.length));
      if (value is! Map<String, dynamic>) return;
      final event = _sanitize(value);
      event.putIfAbsent(
          'timestampUtc', () => DateTime.now().toUtc().toIso8601String());
      _enqueue(() async {
        _retain(event);
        final file = _file;
        if (file == null) return;
        await file.parent.create(recursive: true);
        if (_diskLines >= capacity * 2) {
          await file.writeAsString('${_events.map(jsonEncode).join('\n')}\n',
              flush: true);
          _diskLines = _events.length;
        } else {
          await file.writeAsString('${jsonEncode(event)}\n',
              mode: FileMode.append, flush: true);
          _diskLines++;
        }
      });
    } on FormatException {
      // Diagnostic input cannot break sending.
    }
  }

  void _retain(Map<String, dynamic> event) {
    _events.add(event);
    if (_events.length > capacity) _events.removeAt(0);
  }

  void _enqueue(Future<void> Function() action) {
    _pending = _pending.then((_) => action()).catchError((Object _) {});
  }

  Future<List<Map<String, dynamic>>> snapshot() async {
    await _pending;
    return _events.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Map<String, dynamic> _sanitize(Map<String, dynamic> event) {
    const numbers = {
      'elapsedMs',
      'count',
      'sdkCode',
      'osCode',
      'bytes',
      'contentType',
      'httpStatus'
    };
    const labels = {
      'stage',
      'traceID',
      'clientMsgID',
      'outcome',
      'errorType',
      'failureReason',
      'timestampUtc',
      'mediaType',
      'part',
      'cosCode',
      'requestID',
    };
    return {
      for (final entry in event.entries)
        if ((numbers.contains(entry.key) && entry.value is num) ||
            (labels.contains(entry.key) &&
                entry.value is String &&
                RegExp(r'^[a-zA-Z0-9_.:+-]{1,160}$').hasMatch(entry.value)))
          entry.key: entry.value,
    };
  }
}

Map<String, Object> mediaErrorFields(Object error) {
  final text = error is PlatformException
      ? '${error.code} ${error.message ?? ''}'
      : error.toString();
  final status = RegExp(r'(?:StatusCode|status code|status)[:= ]+([45]\d{2})\b',
          caseSensitive: false)
      .firstMatch(text);
  final request = RegExp(
          r'(?:RequestID|RequestId|x-cos-request-id)[:= ]+([a-zA-Z0-9_-]{8,128})')
      .firstMatch(text);
  final cos = RegExp(
          r'\b(SignatureDoesNotMatch|AccessDenied|RequestExpired|ExpiredToken|NoSuchUpload|InvalidPart|EntityTooLarge|InternalError|SlowDown)\b')
      .firstMatch(text);
  return {
    'failureReason': mediaFailureReason(error),
    if (status != null) 'httpStatus': int.parse(status[1]!),
    if (request != null) 'requestID': request[1]!,
    if (cos != null) 'cosCode': cos[1]!,
  };
}

/// Classifies known error signatures without exporting raw native error text,
/// which can contain signed COS URLs, tokens and local filenames.
String mediaFailureReason(Object error) {
  if (error is TimeoutException) return 'timeout';
  if (error is FileSystemException) return 'local_file';
  final text = (error is PlatformException
          ? '${error.code} ${error.message ?? ''}'
          : error.toString())
      .toLowerCase();
  if (text.contains('signaturedoesnotmatch')) return 'signature_mismatch';
  if (text.contains('requestexpired') || text.contains('expiredtoken')) {
    return 'credential_expired';
  }
  if (text.contains('accessdenied') || text.contains('permission denied')) {
    return 'access_denied';
  }
  if (text.contains('timeout') ||
      text.contains('timed out') ||
      text.contains('deadline exceeded')) {
    return 'timeout';
  }
  if (text.contains('context canceled') || text.contains('cancelled')) {
    return 'cancelled';
  }
  if (text.contains('no such file') || text.contains('file not found')) {
    return 'local_file';
  }
  if (text.contains('no such host') || text.contains('dns')) return 'dns';
  if (text.contains('connection') ||
      text.contains('network') ||
      text.contains('socket')) {
    return 'network';
  }
  return 'unknown';
}
