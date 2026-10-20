import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'media_diagnostic_journal.dart';

class MediaOperationDiagnostics {
  MediaOperationDiagnostics(this.channel);
  final MethodChannel channel;
  final journal = MediaDiagnosticJournal();
  final _writes = <Future<void>>{};
  bool _enabled = false;

  void configure(String directory) {
    _enabled = true;
    journal.configure(directory);
  }

  void record(Map<String, Object?> event, String operationID) {
    if (!_enabled) return;
    final text = 'chat_media ${jsonEncode({
          ...event,
          'traceID': operationID,
          'timestampUtc': DateTime.now().toUtc().toIso8601String(),
        })}';
    journal.capture(text);
    late Future<void> write;
    write = channel
        .invokeMethod('logs', {
          'ManagerName': 'imManager',
          'logLevel': 4,
          'line': 0,
          'file': '',
          'err': '',
          'msgs': text,
          'keyAndValue': '[]',
          'operationID': operationID,
        })
        .timeout(const Duration(seconds: 2))
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _writes.remove(write));
    _writes.add(write);
  }

  Future<T> run<T>(Map<String, Object?> fields, String operationID,
      Future<T> Function() action) async {
    final watch = Stopwatch()..start();
    record({...fields, 'outcome': 'start'}, operationID);
    try {
      final result = await action();
      record({
        ...fields,
        'outcome': 'complete',
        'elapsedMs': watch.elapsedMilliseconds
      }, operationID);
      return result;
    } catch (error) {
      record({
        ...fields,
        'outcome': 'failed',
        'elapsedMs': watch.elapsedMilliseconds,
        'errorType': error.runtimeType.toString(),
        ...mediaErrorFields(error),
        if (error is PlatformException) 'sdkCode': int.tryParse(error.code),
      }, operationID);
      rethrow;
    }
  }

  /// Replay as one bounded line: even a tail-only export carries the recent
  /// media history, including events from a previous app process.
  Future<void> prepareExport(String operationID) async {
    await Future.wait(_writes.toList());
    final events = await journal.snapshot();
    if (events.isEmpty) return;
    // Do not silently upload an incomplete diagnostic bundle if this fails.
    await channel.invokeMethod('logs', {
      'ManagerName': 'imManager',
      'logLevel': 4,
      'line': 0,
      'file': '',
      'err': '',
      'msgs': 'chat_media_snapshot ${jsonEncode({
            'schema': 1,
            'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
            'capacity': MediaDiagnosticJournal.capacity,
            'events': events,
          })}',
      'keyAndValue': '[]',
      'operationID': operationID,
    }).timeout(const Duration(seconds: 5));
  }
}
