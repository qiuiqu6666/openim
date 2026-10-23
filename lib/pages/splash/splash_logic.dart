import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/im_controller.dart';
import '../../core/server_nodes/startup/startup_network_preparation.dart';
import '../../core/user_activity/activity_runtime.dart';
import '../../routes/app_navigator.dart';

class SplashLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final pushLogic = Get.find<PushController>();

  String? get userID => DataSp.userID;

  String? get token => DataSp.imToken;

  late StreamSubscription initializedSub;
  bool _loggingIn = false;
  bool _closed = false;
  bool _ready = false;
  bool _initialized = false;
  bool _starting = false;

  @override
  void onInit() {
    initializedSub = imLogic.initializedSubject.listen((value) {
      if (!value) return;
      _initialized = true;
      unawaited(_start());
    });
    super.onInit();
  }

  @override
  void onReady() {
    super.onReady();
    _ready = true;
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_closed || !_ready || !_initialized || _starting) return;
    _starting = true;
    if (userID != null && token != null) {
      await _login();
    } else {
      _handoff('login');
      AppNavigator.startLogin();
    }
  }

  Future<void> _login() async {
    if (_closed || _loggingIn) return;
    _loggingIn = true;
    final account = userID;
    final credential = token;
    try {
      Logger.print('Restoring login session');
      if (Get.isRegistered<StartupNetworkPreparation>()) {
        Get.find<StartupNetworkPreparation>().trace.event('login_start');
      }
      await imLogic.login(account!, credential!);
      if (_closed || account != userID || credential != token) return;
      ActivityRuntime.instance.sessionRestored(account, credential);
      Logger.print('---------im login success-------');
      PushController.login(
        account,
        onTokenRefresh: (token) {
          if (OpenIM.iMManager.userID != account ||
              DataSp.imToken != credential) {
            return;
          }
          OpenIM.iMManager.updateFcmToken(
              fcmToken: token,
              expireTime: DateTime.now()
                  .add(Duration(days: 90))
                  .millisecondsSinceEpoch);
        },
      );
      Logger.print('---------push login success----');
      _handoff('home');
      AppNavigator.startSplashToMain(isAutoLogin: true);
    } catch (e) {
      if (!_closed && userID == null && token == null) {
        _handoff('login');
        AppNavigator.startLogin();
        return;
      }
      if (_closed || account != userID || credential != token) return;
      // Authentication rejection is handled by the SDK session owner. A
      // transport failure must never destroy the persisted session.
      if (Get.isRegistered<StartupNetworkPreparation>()) {
        Get.find<StartupNetworkPreparation>().loginFailed(() async {
          if (!_closed && account == userID && credential == token) {
            await _login();
          }
        });
      }
    } finally {
      _loggingIn = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    initializedSub.cancel();
    super.onClose();
  }

  void _handoff(String destination) {
    if (Get.isRegistered<StartupNetworkPreparation>()) {
      Get.find<StartupNetworkPreparation>().finishHandoff(destination);
    }
  }
}
