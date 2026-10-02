import 'dart:async';

import 'package:flutter/material.dart';
import 'my_info/my_avatar_editor.dart';

import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';
import 'settings/settings_draft_store.dart';
import 'settings/settings_home_page.dart';
import 'settings/settings_navigation.dart';
import 'settings/settings_service.dart';
import 'settings/pages/notification_settings_page.dart';
import 'settings/pages/font_size_page.dart';
import 'settings/pages/profile_info_page.dart';
import 'settings/pages/qr_profile_page.dart';
import 'secondary/favorites_draft_store.dart';
import 'secondary/favorites_page.dart';
import 'secondary/recent_calls_page.dart';
import 'secondary/share_app_sheet.dart';

class MineLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final settingsStore = SettingsDraftStore();
  final SettingsService settingsService = const StubSettingsService();
  final favoritesStore = FavoritesDraftStore();

  late StreamSubscription kickedOfflineSub;

  void viewMyInfo() => AppNavigator.startMyInfo();

  void openProfileInfo(BuildContext context) {
    final user = imLogic.userInfo.value;
    openSettingsPage(
      context,
      ProfileInfoPage(
        nickname: settingsStore.profileNickname.isEmpty
            ? (user.nickname ?? '')
            : settingsStore.profileNickname,
        userId: user.userID ?? '',
        avatarUrl: user.faceURL ?? '',
        phoneNumber: user.phoneNumber ?? '',
        gender: user.gender ?? 0,
        birth: user.birth ?? 0,
        store: settingsStore,
        service: settingsService,
      ),
    );
  }

  void openMyQr(BuildContext context) {
    final user = imLogic.userInfo.value;
    openSettingsPage(
      context,
      QrProfilePage(
        nickname: settingsStore.profileNickname.isEmpty
            ? (user.nickname ?? '')
            : settingsStore.profileNickname,
        userId: user.userID ?? '',
        avatarUrl: user.faceURL ?? '',
        avatarBytes: settingsStore.profileAvatarPreviewBytes,
      ),
    );
  }

  void openFavorites(BuildContext context) =>
      openSettingsPage(context, FavoritesPage(store: favoritesStore));

  void openCalls(BuildContext context) => openSettingsPage(
        context,
        RecentCallsPage(
          onStartCall: (userId, video) {
            imLogic.call(
              callObj: CallObj.single,
              callType: video ? CallType.video : CallType.audio,
              inviteeUserIDList: [userId],
            );
          },
        ),
      );

  void openNotifications(BuildContext context) => openSettingsPage(
        context,
        NotificationSettingsPage(store: settingsStore, service: settingsService),
      );

  void openShareApp(BuildContext context) => ShareAppSheet.show(context);

  void openSettings(BuildContext context) {
    final user = imLogic.userInfo.value;
    openSettingsPage(
      context,
      SettingsHomePage(
        store: settingsStore,
        service: settingsService,
        profileName: settingsStore.profileNickname.isEmpty
            ? (user.nickname ?? '')
            : settingsStore.profileNickname,
        profileId: user.userID ?? '',
        avatarUrl: user.faceURL ?? '',
        phoneNumber: user.phoneNumber ?? '',
        profileGender: user.gender ?? 0,
        profileBirth: user.birth ?? 0,
        onLogout: logout,
      ),
    );
  }


  void openPhotoSheet() => MyAvatarEditor.open(imLogic);

  void editMyName() => AppNavigator.startEditMyInfo();

  void copyID() {
    IMUtils.copy(text: imLogic.userInfo.value.userID!);
  }

  bool get _isZh => (Get.locale ?? Get.deviceLocale)?.languageCode == 'zh';

  void showReservedFeature(String feature) {
    IMViews.showToast(
      _isZh ? '$feature 暂未开放' : '$feature is not available yet',
    );
  }

  void showUnavailableFeature(String feature) {
    IMViews.showToast(
      _isZh ? '$feature 暂未开放' : '$feature is not available yet',
    );
  }

  void showReservedQrFeature() =>
      showReservedFeature(_isZh ? '我的二维码' : 'My QR Code');

  void accountSetup() => AppNavigator.startAccountSetup();

  void aboutUs() => AppNavigator.startAboutUs();

  Future<void> logout() async {
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
    settingsStore.setFontSizeIndex(
      FontSizePage.indexForScale(DataSp.getChatFontSizeFactor()),
    );
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
    settingsStore.dispose();
    favoritesStore.dispose();
    super.onClose();
  }
}
