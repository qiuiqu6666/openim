import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'mine_logic.dart';
import 'settings/openim_profile_service.dart';
import 'widgets/mine_profile_view.dart';

class MinePage extends StatelessWidget {
  MinePage({super.key});

  final MineLogic logic = Get.find<MineLogic>();

  @override
  Widget build(BuildContext context) => Obx(() {
        final user = logic.imLogic.userInfo.value;
        logic.settingsStore.seedProfile(
            nickname: user.nickname ?? '',
            signature: OpenIMProfileService.signatureFromEx(user.ex));
        return AnimatedBuilder(
          animation: logic.settingsStore,
          builder: (context, _) => MineProfileView(
            nickname: logic.settingsStore.profileNickname.isEmpty
                ? (user.nickname ?? '')
                : logic.settingsStore.profileNickname,
            userId: user.userID ?? '',
            avatarUrl: user.faceURL ?? '',
            avatarBytes: logic.settingsStore.profileAvatarPreviewBytes,
            signature: logic.settingsStore.profileSignature,
            onProfileTap: () => logic.openProfileInfo(context),
            onQrTap: () => logic.openMyQr(context),
            onFavoritesTap: () => logic.openFavorites(context),
            onCallsTap: () => logic.openCalls(context),
            onNotificationsTap: () => logic.openNotifications(context),
            onShareAppTap: () => logic.openShareApp(context),
            onSettingsTap: () => logic.openSettings(context),
            onFeatureTap: logic.showReservedFeature,
            onUnavailableFeatureTap: logic.showUnavailableFeature,
          ),
        );
      });
}
