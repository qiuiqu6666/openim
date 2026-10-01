import 'dart:async';
import 'my_info/my_avatar_editor.dart';

import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';

class MineLogic extends GetxController {
  final imLogic = Get.find<IMController>();

  late StreamSubscription kickedOfflineSub;

  void viewMyInfo() => AppNavigator.startMyInfo();

  void openPhotoSheet() => MyAvatarEditor.open(imLogic);

  void editMyName() => AppNavigator.startEditMyInfo();

  void copyID() {
    final account = imLogic.userInfo.value.account;
    if (account != null && account.isNotEmpty) IMUtils.copy(text: account);
  }

  void accountSetup() => AppNavigator.startAccountSetup();

  void aboutUs() => AppNavigator.startAboutUs();

  void logout() async {
    var confirm = await Get.dialog(CustomDialog(title: StrRes.logoutHint));
    if (confirm == true) {
      try {
        await LoadingView.singleton.wrap(asyncFunction: () async {
          await imLogic.logout();
          await DataSp.removeLoginCertificate();
          PushController.logout();
          Get.find<HomeLogic>().conversationsAtFirstPage.clear();
        });
        AppNavigator.startLogin();
      } catch (e) {
        IMViews.showToast('e:$e');
      }
    }
  }

  void kickedOffline({String? tips}) async {
    if (EasyLoading.isShow) {
      EasyLoading.dismiss();
    }
    Get.snackbar(StrRes.accountWarn, tips ?? StrRes.accountException);
    await DataSp.removeLoginCertificate();
    PushController.logout();
    AppNavigator.startLogin();
  }

  @override
  void onInit() {
    kickedOfflineSub = imLogic.onKickedOfflineSubject.listen((value) {
      if (value == KickoffType.userTokenInvalid) {
        kickedOffline(tips: StrRes.tokenInvalid);
      } else {
        kickedOffline();
      }
    });
    super.onInit();
  }

  @override
  void onClose() {
    kickedOfflineSub.cancel();
    super.onClose();
  }
}
