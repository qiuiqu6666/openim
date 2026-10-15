import 'dart:async';
import 'dart:developer';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

class Logger {
  /// Release keeps native OpenIM diagnostics, without application debug output.
  static void configureOutput() {
    if (kReleaseMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    }
  }

  static Logger? _instance;

  factory Logger() {
    return _instance ??= Logger._();
  }

  Logger._() {
    unawaited(_setPlatformInfo());
  }

  Future<void> _setPlatformInfo() async {
    try {
      final deviceInfo = await DeviceInfoPlugin().deviceInfo;

      if (deviceInfo is AndroidDeviceInfo) {
        final apiVersion = deviceInfo.version.sdkInt;

        _header = '[*flutter*Android/$apiVersion]';
      } else if (deviceInfo is IosDeviceInfo) {
        final osVersion = deviceInfo.systemVersion;

        _header = '[*flutter*iOS/$osVersion]';
      }
    } catch (_) {
      // Logging must still work when the optional platform plugin is unavailable.
    }
  }

  String _header = '*flutter*';
  bool sdkIsInited = false;

  static void print(dynamic text,
      {bool isError = false,
      String? fileName,
      String? functionName,
      String? errorMsg,
      List<dynamic>? keyAndValues,
      bool onlyConsole = false}) {
    if (kReleaseMode) return;
    final time = DateTime.now().toIso8601String();
    final logger = Logger();

    log(
      '$time ${logger._header} [Console]: $text, ${keyAndValues != null ? ', $keyAndValues' : ''}, isError [${isError || errorMsg != null}]',
    );
    if (!onlyConsole && logger.sdkIsInited) {
      unawaited(_writeNative(
        msgs:
            '$time ${logger._header} [${functionName ?? ''}]: $text, ${keyAndValues != null ? ', $keyAndValues' : ''}',
        err: errorMsg,
        keyAndValues: keyAndValues ?? [],
      ));
    }
  }

  static Future<void> _writeNative({
    required String msgs,
    String? err,
    required List<dynamic> keyAndValues,
  }) async {
    try {
      await OpenIM.iMManager
          .logs(msgs: msgs, err: err, keyAndValues: keyAndValues);
    } catch (error) {
      // The SDK can be torn down after sdkIsInited was checked. The console
      // already has this record; never recursively send a logging error back
      // to the same unavailable SDK or make it an application error.
      log('Native log unavailable (${error.runtimeType})',
          name: '99Chat.Logger');
    }
  }
}
