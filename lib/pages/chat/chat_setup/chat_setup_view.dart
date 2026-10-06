import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/widgets/settings_widgets.dart';
import 'chat_setup_logic.dart';
import 'chat_setup_tokens.dart';
import 'message_retention_page.dart';
import 'widgets/chat_setup_members_card.dart';

class ChatSetupPage extends StatelessWidget {
  ChatSetupPage({super.key, ChatSetupLogic? logic})
      : logic = logic ?? Get.find<ChatSetupLogic>();

  final ChatSetupLogic logic;

  @override
  Widget build(BuildContext context) => Obx(() {
        final updating = logic.updating.value;
        final clearing = logic.clearing.value;
        final dark = settingsIsDark(context);
        return SettingsScaffold(
          title: 'chatSettingsTitle'.tr,
          children: [
            SizedBox(
              height: AppTokens.s2,
              child: updating || clearing
                  ? const LinearProgressIndicator(
                      key: ValueKey('chat-setup-progress'),
                      color: AppTokens.accent)
                  : null,
            ),
            ChatSetupMembersCard(
              key: const ValueKey('chat-setup-members'),
              conversation: logic.conversationInfo.value,
              onViewProfile: logic.viewUserInfo,
              onAddMember: logic.createGroup,
            ),
            SettingsGroup(children: [
              SettingsCell(
                key: const ValueKey('chat-setup-retention'),
                title: 'sdkRetention'.tr,
                showDivider: false,
                onTap: () => Get.to(() => MessageRetentionPage(
                    conversation: logic.conversationInfo.value)),
              ),
            ]),
            SettingsGroup(
              key: const ValueKey('chat-setup-history-group'),
              children: [
                SettingsCell(
                  key: const ValueKey('chat-setup-search'),
                  title: 'findChatContent'.tr,
                  showDivider: false,
                  onTap: logic.searchHistory,
                ),
              ],
            ),
            SettingsGroup(
              key: const ValueKey('chat-setup-notifications-group'),
              children: [
                SettingsCell(
                  key: const ValueKey('chat-setup-pin'),
                  title: 'groupPinLabel'.tr,
                  showArrow: false,
                  showDivider: false,
                  enabled: !updating && !clearing,
                  trailing: AppSwitch(
                    value: logic.isPinned,
                    onChanged: updating || clearing ? null : logic.setPinned,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                  child: Divider(
                    height: 1,
                    thickness: ChatSetupTokens.dividerThickness,
                    color: AppTokens.border(dark: dark),
                  ),
                ),
                SettingsCell(
                  key: const ValueKey('chat-setup-mute'),
                  title: 'groupMuteLabel'.tr,
                  showArrow: false,
                  enabled: !updating && !clearing,
                  showDivider: false,
                  trailing: AppSwitch(
                    value: logic.isMuted,
                    onChanged: updating || clearing ? null : logic.setMuted,
                  ),
                ),
              ],
            ),
            SettingsGroup(children: [
              SettingsCell(
                key: const ValueKey('chat-setup-background'),
                title: 'currentChatBackground'.tr,
                showDivider: false,
                onTap: logic.setBackground,
              ),
            ]),
            SettingsGroup(children: [
              SettingsCell(
                key: const ValueKey('chat-setup-clear'),
                title: StrRes.clearChatHistory,
                showDivider: false,
                enabled: !clearing && !updating,
                onTap: clearing || updating ? null : logic.clearHistory,
              ),
            ]),
            SettingsGroup(children: [
              SettingsCell(
                key: const ValueKey('chat-setup-report'),
                title: 'groupReport'.tr,
                showDivider: false,
                onTap: logic.reportConversation,
              ),
            ]),
          ],
        );
      });
}
