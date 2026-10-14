import 'dart:developer';
import 'package:flutter/foundation.dart';

/// Detailed SDK callbacks are for debug builds; failures remain diagnosable.
class Logger {
  static void print(String text) {
    if (kDebugMode) log('** $text', name: 'flutter_openim_sdk');
  }

  static void error(String message, Object error, StackTrace stackTrace) {
    log(message,
        name: 'flutter_openim_sdk',
        level: 1000,
        error: error,
        stackTrace: stackTrace);
  }
}
