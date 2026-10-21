import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'group_qrcode_content.dart';
import 'group_qrcode_logic.dart';
import 'group_qrcode_tokens.dart';
import '../../../channels/models/channel_kind.dart';

class GroupQrcodePage extends StatelessWidget {
  final logic = Get.find<GroupQrcodeLogic>();
  GroupQrcodePage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final group = logic.groupSetupLogic.groupInfo.value;
      final channel = isChannelEx(group.ex);
      return Scaffold(
        appBar: GlassAppBar(
          centerTitle: true,
          title: Text(channel ? 'channelQrcode'.tr : StrRes.groupQrcode,
              style: TextStyle(
                  color: AppTokens.textPrimary(dark: dark),
                  fontSize: GroupQrcodeTokens.titleSize,
                  fontWeight: FontWeight.w700)),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppTokens.accent),
          ),
        ),
        backgroundColor: AppTokens.background(dark: dark),
        body: SafeArea(
            top: false,
            child: GroupQrcodeContent(
              isChannel: channel,
              groupName: group.groupName ?? '',
              groupId: logic.displayGroupId,
              faceUrl: group.faceURL,
              qrData: logic.buildQRContent(),
              cardKey: logic.cardKey,
              saving: logic.saving.value,
              scanning: logic.scanning.value,
              onSave: logic.saveToAlbum,
              onScan: logic.scan,
              onCopy: logic.copyGroupId,
            )),
      );
    });
  }
}
