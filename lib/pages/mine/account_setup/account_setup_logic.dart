import 'package:get/get.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'presence_visibility_store.dart';
import '../../../core/im_callback.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';

class AccountSetupLogic extends GetxController with WidgetsBindingObserver {
  final presenceVisibility = PresenceVisibilityStore();
  StreamSubscription? _visibilitySubscription;
  StreamSubscription? _connectionSubscription;
  final imLogic = Get.find<IMController>();
  final curLanguage = "".obs;
  final friendSettingsReady = false.obs;
  final friendSettingsBusy = false.obs;
  final friendSettingsFailed = false.obs;
  final friendPermissions = <String, int>{}.obs;
  final allowAddFriend = 1.obs;

  @override
  void onReady() {
    _updateLanguage();
    super.onReady();
  }

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    _visibilitySubscription = imLogic.customBusinessMessageSubject
        .listen(presenceVisibility.onNotification);
    _connectionSubscription = imLogic.imSdkStatusPublishSubject.listen((event) {
      if (event.status == IMSdkStatus.connectionSucceeded) {
        presenceVisibility.refresh();
      }
    });
    presenceVisibility.refresh();
    _queryMyFullInfo();
    super.onInit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      presenceVisibility.refresh();
      if (!friendSettingsBusy.value) _queryMyFullInfo();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _visibilitySubscription?.cancel();
    _connectionSubscription?.cancel();
    presenceVisibility.dispose();
    super.onClose();
  }

  Future<void> _queryMyFullInfo() async {
    friendSettingsReady.value = false;
    friendSettingsFailed.value = false;
    try {
      final data = await Apis.queryMyFullInfo();
      if (isClosed) return;
      if (data == null) {
        friendSettingsFailed.value = true;
        return;
      }
      final userInfo = UserFullInfo.fromJson(data.toJson());
      allowAddFriend.value = userInfo.allowAddFriend ?? 1;
      friendPermissions.assignAll({
        'allowAddByUserID': userInfo.allowAddByUserID ?? 1,
        'allowAddByPhone': userInfo.allowAddByPhone ?? 1,
        'allowAddByEmail': userInfo.allowAddByEmail ?? 1,
        'allowAddByQRCode': userInfo.allowAddByQRCode ?? 1,
        'allowAddByGroup': userInfo.allowAddByGroup ?? 1,
        'allowAddByCard': userInfo.allowAddByCard ?? 1,
      });
      imLogic.userInfo.update((val) {
        val?.allowAddFriend = userInfo.allowAddFriend;
        val?.allowBeep = userInfo.allowBeep;
        val?.allowVibration = userInfo.allowVibration;
      });
      friendSettingsReady.value = true;
    } catch (_) {
      if (!isClosed) friendSettingsFailed.value = true;
    }
  }

  void refreshFriendSettings() => _queryMyFullInfo();

  Future<void> setFriendPermission(String field, bool enabled) async {
    if (!friendSettingsReady.value || friendSettingsBusy.value) return;
    final value = enabled ? 1 : (field == 'allowAddFriend' ? 0 : 2);
    if (field == 'allowAddFriend'
        ? allowAddFriend.value == value
        : friendPermissions[field] == value) {
      return;
    }
    friendSettingsBusy.value = true;
    try {
      await Apis.updateFriendAddPermission(
        userID: OpenIM.iMManager.userID,
        field: field,
        value: value,
      );
      if (isClosed) return;
      if (field == 'allowAddFriend') {
        allowAddFriend.value = value;
        imLogic.userInfo.update((user) => user?.allowAddFriend = value);
      } else {
        friendPermissions[field] = value;
      }
    } catch (error) {
      Logger.print('updateFriendAddPermission failed: $error');
      if (!isClosed) {
        final unsupported = error is StateError &&
            error.message ==
                'Friend add permission was not saved by the server';
        IMViews.showToast(
          unsupported ? 'friendAddSettingsUnsupported'.tr : StrRes.saveFailed,
        );
      }
    } finally {
      if (!isClosed) friendSettingsBusy.value = false;
    }
  }

  final globalMuteBusy = false.obs;
  Future<void> setGlobalMute(bool value) async {
    if (globalMuteBusy.value) return;
    globalMuteBusy.value = true;
    try {
      await OpenIM.iMManager.userManager
          .setGlobalRecvMessageOpt(status: value ? 2 : 0);
      final user = await OpenIM.iMManager.userManager.getSelfUserInfo();
      if (!isClosed)
        imLogic.userInfo
            .update((info) => info?.globalRecvMsgOpt = user.globalRecvMsgOpt);
    } catch (error) {
      IMViews.showToast(error.toString());
    } finally {
      if (!isClosed) globalMuteBusy.value = false;
    }
  }

  void blacklist() => AppNavigator.startBlacklist();

  void languageSetting() => AppNavigator.startLanguageSetup();

  void _updateLanguage() {
    var index = DataSp.getLanguage() ?? 0;
    switch (index) {
      case 1:
        curLanguage.value = StrRes.chinese;
        break;
      case 2:
        curLanguage.value = StrRes.english;
        break;
      default:
        curLanguage.value = StrRes.followSystem;
        break;
    }
  }
}
