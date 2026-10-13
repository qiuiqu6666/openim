import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'app.dart';
import 'core/server_nodes/startup_node_selection.dart';
import 'core/gameshield/gameshield_runtime.dart';
import 'core/gameshield/startup/gameshield_startup_failure_app.dart';
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
      final shield = GameShieldRuntime.instance;
      await Config.init(() async {
        await AppSystemBars.initialize();
        AppThemeController.instance.load();
        NavigationGlassController.instance.load();
        await NavigationGlassController.instance.initializeRenderer();
        runApp(const ChatApp());
      },
          prepareNetwork: shield.settings.enabled
              ? shield.prepare
              : StartupNodeSelection.prepare,
          onInitError: shield.settings.enabled
              ? (_) {
                  runApp(GameShieldStartupFailureApp(onRetry: boot));
                }
              : null);
    }

    unawaited(boot());
  }, (error, stackTrace) {
    Logger.print('FlutterError: ${error.toString()}, ${stackTrace.toString()}',
        onlyConsole: true);
  });
}
