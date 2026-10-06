import 'dart:async';
import 'dart:developer';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

class Logger {
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
    final time = DateTime.now().toIso8601String();
    final logger = Logger();

    log(
      '$time ${logger._header} [Console]: $text, ${keyAndValues != null ? ', $keyAndValues' : ''}, isError [${isError || errorMsg != null}]',
    );
    if (!onlyConsole && logger.sdkIsInited) {
      OpenIM.iMManager.logs(
        msgs:
            '$time ${logger._header} [${functionName ?? ''}]: $text, ${keyAndValues != null ? ', $keyAndValues' : ''}',
        err: errorMsg,
        keyAndValues: keyAndValues ?? [],
      );
    }
  }
}
