import 'dart:async';

import 'package:flutter/material.dart';
import 'my_info/my_avatar_editor.dart';

import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';

import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';
import '../../services/moments_repository.dart';
import '../../services/favorite_runtime.dart';
import '../moments/moments_page.dart';
import '../moments/moments_settings_page.dart';
import 'settings/settings_draft_store.dart';
import 'settings/settings_home_page.dart';
import 'settings/settings_navigation.dart';
import 'settings/openim_profile_service.dart';
import 'settings/pages/notification_settings_page.dart';
import 'settings/pages/font_size_page.dart';
import 'settings/pages/profile_info_page.dart';
import 'settings/pages/qr_profile_page.dart';
import 'secondary/favorites_page.dart';
import 'secondary/recent_calls_page.dart';
import 'secondary/share_app_sheet.dart';

class MineLogic extends GetxController {
  bool _aiAssistantRouteOpen = false;
  bool _momentsRouteOpen = false;
  bool _momentsSettingsRouteOpen = false;
  final imLogic = Get.find<IMController>();
  final settingsStore = SettingsDraftStore();
  late final OpenIMProfileService settingsService =
      OpenIMProfileService(imLogic);

  void viewMyInfo() => AppNavigator.startMyInfo();

  Future<void> openProfileInfo(BuildContext context) async {
    try {
      await settingsService.refresh();
    } catch (_) {
      IMViews.showToast(_isZh ? '资料刷新失败，显示已缓存资料' : 'Could not refresh profile');
    }
    if (!context.mounted || isClosed) return;
    final user = imLogic.userInfo.value;
    settingsStore.seedProfile(
        nickname: user.nickname ?? '',
        signature: OpenIMProfileService.signatureFromEx(user.ex));
    settingsStore
        .syncProfileSignature(OpenIMProfileService.signatureFromEx(user.ex));
    openSettingsPage(
      context,
      ProfileInfoPage(
        nickname: settingsStore.profileNickname.isEmpty
            ? (user.nickname ?? '')
            : settingsStore.profileNickname,
        userId: user.userID ?? '',
        account: user.account?.trim() ?? '',
        avatarUrl: user.faceURL ?? '',
        phoneNumber: user.phoneNumber ?? '',
        gender: user.gender ?? 0,
        birth: user.birth ?? 0,
        store: settingsStore,
        service: settingsService,
        onMomentsTap: () => openMoments(context, personal: true),
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
        account: user.account?.trim() ?? '',
        avatarUrl: user.faceURL ?? '',
        avatarBytes: settingsStore.profileAvatarPreviewBytes,
      ),
    );
  }

  void openFavorites(BuildContext context) => openSettingsPage(
      context,
      FavoritesPage(
        repository: FavoriteRuntime.repository,
        onSendToConversation: (item) =>
            FavoriteRuntime.sendToConversation(context, item),
        onSendItemsToConversation: (items) =>
            FavoriteRuntime.sendItemsToConversation(context, items),
        onCancelSendItemsToConversation: (items) =>
            FavoriteRuntime.cancelSendItems(context, items),
      ), activityPage: 'favorites',);

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
        NotificationSettingsPage(
            store: settingsStore, service: settingsService),
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
        profileAccount: user.account?.trim() ?? '',
        avatarUrl: user.faceURL ?? '',
        phoneNumber: user.phoneNumber ?? '',
        profileGender: user.gender ?? 0,
        profileBirth: user.birth ?? 0,
        onProfileTap: () => openProfileInfo(context),
        onMomentsTap: () => openMomentsSettings(context),
        onLogout: logout,
      ),
    );
  }

  void openPhotoSheet() => MyAvatarEditor.open(imLogic);

  void editMyName() => AppNavigator.startEditMyInfo();

  void copyID() {
    final account = imLogic.userInfo.value.account?.trim() ?? '';
    if (account.isNotEmpty) IMUtils.copy(text: account);
  }

  bool get _isZh => (Get.locale ?? Get.deviceLocale)?.languageCode == 'zh';

  void openFeature(BuildContext context, String feature) {
    if (feature == 'AI助手' || feature == 'AI Assistant') {
      unawaited(_openAiAssistant());
      return;
    }
    if (feature == '社区广场' || feature == 'Community') {
      openMoments(context);
      return;
    }
    showReservedFeature(feature);
  }

  Future<void> _openAiAssistant() async {
    if (_aiAssistantRouteOpen) return;
    _aiAssistantRouteOpen = true;
    try {
      await AppNavigator.startAiAssistant();
    } finally {
      _aiAssistantRouteOpen = false;
    }
  }

  Future<void> openMoments(BuildContext context,
      {bool personal = false}) async {
    if (_momentsRouteOpen || !context.mounted || isClosed) return;
    _momentsRouteOpen = true;
    final user = imLogic.userInfo.value;
    try {
      await openSettingsPage(
          context,
          MomentsPage(
            authorId: personal ? user.userID : null,
            profileUser: MomentUser(
                userId: user.userID ?? '',
                nickname: user.nickname ?? '',
                avatarUrl: user.faceURL ?? ''),
          ), activityPage: 'moments',);
    } finally {
      _momentsRouteOpen = false;
    }
  }

  Future<void> openMomentsSettings(BuildContext context) async {
    if (_momentsSettingsRouteOpen || !context.mounted || isClosed) return;
    _momentsSettingsRouteOpen = true;
    try {
      await openSettingsPage(
          context, MomentsSettingsPage(repository: MomentsRepository.instance));
    } finally {
      _momentsSettingsRouteOpen = false;
    }
  }

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
    if (confirm == true && !isClosed) {
      await Get.find<HomeLogic>().endSession();
    }
  }

  void kickedOffline({String? tips}) async {
    if (EasyLoading.isShow) {
      EasyLoading.dismiss();
    }
    IMViews.showToast(
        '${StrRes.accountWarn}\n${tips ?? StrRes.accountException}');
    await Get.find<HomeLogic>().endSession();
  }

  @override
  void onInit() {
    settingsStore.setFontSizeIndex(
      FontSizePage.indexForScale(DataSp.getChatFontSizeFactor()),
    );
    super.onInit();
  }

  @override
  void onClose() {
    settingsStore.dispose();
    super.onClose();
  }
}
