import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'app.dart';
import 'core/youmeng/youmeng_runtime.dart';
import 'theme/app_theme_controller.dart';

void main() {
  Logger.configureOutput();
  runZonedGuarded(() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Logger.print(
          'FlutterError: ${details.exception.toString()}, ${details.stack.toString()}');
    };

    Timer? retry;
    var failures = 0;
    Future<void> boot() async {
      retry?.cancel();
      await Config.init(() async {
        failures = 0;
        await AppSystemBars.initialize();
        AppThemeController.instance.load();
        NavigationGlassController.instance.load();
        await NavigationGlassController.instance.initializeRenderer();
        runApp(const ChatApp());
      },
          prepareNetwork: YoumengRuntime.prepare,
          onInitError: YoumengRuntime.enabled
              ? (_) {
                  const delays = [2, 4, 8, 15, 30];
                  retry = Timer(Duration(seconds: delays[failures]), boot);
                  if (failures < delays.length - 1) failures++;
                  runApp(MaterialApp(
                      home: Scaffold(
                          body: Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                        const Text('正在恢复网络连接，将自动重试'),
                        TextButton(onPressed: boot, child: const Text('重试')),
                      ])))));
                }
              : null);
    }

    unawaited(boot());
  }, (error, stackTrace) {
    Logger.print('FlutterError: ${error.toString()}, ${stackTrace.toString()}',
        onlyConsole: true);
  });
}
