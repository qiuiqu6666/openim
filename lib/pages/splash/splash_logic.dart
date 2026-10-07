import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/im_controller.dart';
import '../../core/session/sdk_session_queue.dart';
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

  @override
  void onInit() {
    initializedSub = imLogic.initializedSubject.listen((value) {
      if (_closed || _loggingIn || !value) return;
      if (null != userID && null != token) {
        _login();
      } else {
        AppNavigator.startLogin();
      }
    });
    super.onInit();
  }

  _login() async {
    if (_closed || _loggingIn) return;
    _loggingIn = true;
    final account = userID;
    final credential = token;
    try {
      Logger.print('Restoring login session');
      await imLogic.login(account!, credential!);
      if (_closed || account != userID || credential != token) return;
      ActivityRuntime.instance.sessionRestored(account, credential);
      Logger.print('---------im login success-------');
      PushController.login(
        account,
        onTokenRefresh: (token) {
          if (OpenIM.iMManager.userID != account ||
              DataSp.imToken != credential) return;
          OpenIM.iMManager.updateFcmToken(
              fcmToken: token,
              expireTime: DateTime.now()
                  .add(Duration(days: 90))
                  .millisecondsSinceEpoch);
        },
      );
      Logger.print('---------push login success----');
      AppNavigator.startSplashToMain(isAutoLogin: true);
    } catch (e, s) {
      if (_closed || account != userID || credential != token) return;
      IMViews.showToast(e is SdkSessionBusy
          ? (Get.locale?.languageCode == 'zh'
              ? '上一登录会话仍在清理，请稍后重试'
              : 'The previous session is still closing. Please try again shortly.')
          : '$e $s');
      await DataSp.removeLoginCertificate();
      AppNavigator.startLogin();
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
}
