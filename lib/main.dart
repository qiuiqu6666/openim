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

    Future<void> boot() async {
      await Config.init(() async {
        await AppSystemBars.initialize();
        AppThemeController.instance.load();
        NavigationGlassController.instance.load();
        await NavigationGlassController.instance.initializeRenderer();
        runApp(const ChatApp());
      },
          prepareNetwork: YoumengRuntime.prepare,
          onInitError: YoumengRuntime.enabled
              ? (_) {
                  runApp(MaterialApp(
                      home: Scaffold(
                          body: Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                        const Text('网络保护启动失败，请检查配置后重试'),
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
