import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_logic.dart';
import 'messages/widgets/chat_message_list.dart';
import 'messages/selection/message_selection_action_bar.dart';
import 'messages/selection/message_selection_toolbar.dart';
import 'stickers/personal_sticker_panel.dart';
import 'stickers/builtin/chat_builtin_sticker.dart';
import 'stickers/builtin/chat_builtin_sticker_panel.dart';
import 'group/announcements/group_announcement_banner.dart';
import '../contacts/contacts_logic.dart';
import '../contacts/presence/contact_presence_policy.dart';
import '../official_account/official_account_page.dart';
import '../group_features/widgets/group_chat_feature_surface.dart';
import '../group_features/widgets/group_feature_actions.dart';

class ChatPage extends StatelessWidget {
  final logic = Get.find<ChatLogic>(tag: GetTags.chat);

  ChatPage({super.key});

  Widget? get _groupCallHintView => null;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FriendDisplayPreferences.changes,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    if (logic.isOfficialNotificationChat) {
      return OfficialAccountPage(logic: logic);
    }
    // Register a theme dependency so an already open chat refreshes when the
    // user changes appearance without changing the conversation state.
    Theme.of(context);
    final headerHeight = TitleBar.chatToolbarHeightFor(context,
        isSingleChat: logic.isSingleChat);
    final messages = _buildMessages();
    final input = _buildInput();
    return ListenableBuilder(
      listenable: logic.messageSelection,
      builder: (context, child) => PopScope(
        canPop: !logic.messageSelection.active,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && logic.messageSelection.active) {
            logic.messageSelection.cancel();
          }
        },
        child: child!,
      ),
      child: Scaffold(
          backgroundColor: ChatComposerTokens.background(
              dark: Theme.of(context).brightness == Brightness.dark),
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(headerHeight),
            child: ListenableBuilder(
              listenable: logic.messageSelection,
              builder: (context, child) => logic.messageSelection.active
                  ? MessageSelectionToolbar(controller: logic.messageSelection)
                  : child!,
              child: Obx(() {
                final cachedPresence =
                    logic.isSingleChat && Get.isRegistered<ContactsLogic>()
                        ? Get.find<ContactsLogic>().presence.users[logic.userID]
                        : null;
                final presence = logic.isSingleChat
                    ? ContactPresencePolicy.resolve(
                        userID: logic.userID,
                        ex: logic.conversationInfo.ex,
                        presence: cachedPresence)
                    : null;
                return TitleBar.chat(
                  toolbarHeight: headerHeight,
                  title: logic.nickname.value,
                  avatarUrl: logic.faceUrl.value,
                  presenceText: logic.peerTyping.value
                      ? StrRes.typing
                      : (FriendDisplayPreferences.showOnlineStatus
                          ? presence?.label
                          : null),
                  isOnline: FriendDisplayPreferences.showOnlineStatus &&
                      (presence?.displayOnline ?? false),
                  isSingleChat: logic.isSingleChat,
                  member: logic.memberStr,
                  onCloseMultiModel: logic.exit,
                  onClickMoreBtn: logic.chatSetup,
                  onClickCallBtn: logic.isGroupChat ? null : logic.callAudio,
                  onClickVideoBtn: logic.isGroupChat ? null : logic.callVideo,
                );
              }),
            ),
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: Column(children: [
              if (logic.isGroupChat)
                Obx(() => logic.announcement.value.trim().isEmpty
                    ? const SizedBox.shrink()
                    : GroupAnnouncementBanner(
                        text: logic.announcement.value,
                        version: logic.announcementVersion.value,
                        groupID: logic.groupID!,
                        userID: OpenIM.iMManager.userID,
                        preferences: SpUtil().prefs,
                      )),
              Expanded(
                  child: ListenableBuilder(
                      listenable: logic.groupFeatures,
                      builder: (context, _) => Obx(() {
                            final body = WaterMarkBgView(
                              text: '',
                              path: logic.background.value,
                              backgroundColor: ChatComposerTokens.background(
                                  dark: Theme.of(context).brightness ==
                                      Brightness.dark),
                              floatView: _groupCallHintView,
                              newMessageCount:
                                  logic.newMessages.unseenCount.value,
                              showBackToBottom:
                                  logic.newMessages.awayFromLatest.value,
                              onSeeNewMessage: () =>
                                  logic.scrollBottom(smooth: true),
                              bottomView: input,
                              child: messages,
                            );
                            if (!logic.isGroupChat || !logic.isInGroup.value) {
                              return body;
                            }
                            logic.groupMemberRoleLevel.value;
                            return GroupChatFeatureSurface(
                                store: logic.groupFeatures,
                                featureContext: logic.groupFeatureContext,
                                child: body);
                          }))),
            ]),
          )),
    );
  }

  Widget _buildInput() => ListenableBuilder(
        listenable: logic.messageSelection,
        child: _buildComposer(),
        builder: (context, child) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Offstage(offstage: logic.messageSelection.active, child: child),
            if (logic.messageSelection.active)
              MessageSelectionActionBar(controller: logic.messageSelection),
          ],
        ),
      );

  Widget _buildComposer() => Obx(() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logic.quotedMessage.value != null)
            ListTile(
              dense: true,
              title: Text(
                '${logic.quotedMessage.value?.senderNickname ?? ''}: ${logic.quotedMessage.value?.textElem?.content ?? StrRes.message}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: logic.clearReply,
              ),
            ),
          ChatInputBox(
            builtinStickerPanel:
                ChatBuiltinStickerPanel(onSend: logic.sendBuiltinSticker),
            builtinStickerIcon: Image.asset(
              ChatBuiltinStickerCatalog.menuAssetPath,
              width: AppTokens.s7,
              height: AppTokens.s7,
              fit: BoxFit.contain,
            ),
            stickerPanel: PersonalStickerPanel(
              store: logic.personalStickers,
              onAdd: logic.addPersonalSticker,
              onSend: logic.sendPersonalSticker,
              onSendDice: logic.sendDice,
            ),
            forceCloseToolboxSub: logic.forceCloseToolbox,
            controller: logic.inputCtrl,
            focusNode: logic.focusNode,
            isNotInGroup: logic.isInvalidGroup,
            enabled: !logic.sendingMuted,
            hintText: logic.sendingMuted ? StrRes.youMuted : null,
            directionalText: logic.directionalText(),
            onCloseDirectional: logic.onClearDirectional,
            onSend: (v) => logic.sendTextMsg(),
            onTapVoice: logic.onTapRecord,
            toolbox: ListenableBuilder(
                listenable: logic.groupFeatures,
                builder: (context, _) => ChatToolBox(
                      extraItems: logic.isGroupChat
                          ? GroupFeatureActions.items(
                              context, logic.groupFeatureContext,
                              onLiveStateChanged: () => logic.groupFeatures
                                  .refreshGroup(logic.groupID!))
                          : const [],
                      onTapAlbum: logic.onTapAlbum,
                      onTapFile: logic.onTapFile,
                      onTapCamera: logic.onTapCamera,
                      onTapCard: logic.onTapCard,
                      onTapLocation: logic.onTapLocation,
                      onTapCall: logic.isGroupChat ? null : logic.call,
                      onTapRedPacket: logic.onTapRedPacket,
                      onTapTransfer: logic.onTapTransfer,
                      onTapFavorites: logic.onTapFavorites,
                      isGroupChat: logic.isGroupChat,
                    )),
            voiceRecordBar: HoldToRecordButton(
              expandedPanel: true,
              enabled: !logic.sendingMuted && !logic.isInvalidGroup,
              onRecorded: logic.sendRecordedVoice,
              onConvertToText: logic.convertRecordedVoice,
            ),
          ),
        ],
      ));

  Widget _buildMessages() => ChatMessageList(logic: logic);
}
