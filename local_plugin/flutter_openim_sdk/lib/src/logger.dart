import 'dart:developer';
import 'package:flutter/foundation.dart';

/// Detailed SDK callbacks are for debug builds; failures remain diagnosable.
class Logger {
  static final _brand = RegExp(r'open[-_]?im', caseSensitive: false);
  static String clean(Object value) =>
      value.toString().replaceAll(_brand, 'chat');
  static void print(String text) {
    if (kDebugMode) log(clean('** $text'), name: 'chat_sdk');
  }

  static void error(String message, Object error, StackTrace stackTrace) {
    log(clean(message),
        name: 'chat_sdk',
        level: 1000,
        error: clean(error),
        stackTrace: StackTrace.fromString(clean(stackTrace)));
  }
}
