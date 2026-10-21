import '../channels/conversation/channel_notification_bar.dart';
import '../conversation/conversation_logic.dart';
import 'messages/forwarding/pending_forward_bar.dart';
import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_logic.dart';
import 'media/widgets/chat_media_preparation_indicator.dart';
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
import '../group_features/identity/group_name_label.dart';

class ChatPage extends StatelessWidget {
  final logic = Get.find<ChatLogic>(tag: GetTags.chat);
  // Membership/feature changes move the timeline between wrapper branches.
  // Reparent its existing state instead of attaching a second viewport before
  // the old one is disposed at the end of the frame.
  final _messageListKey = GlobalKey();

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
              child: ListenableBuilder(
                listenable: logic.groupFeatures,
                builder: (context, _) => Obx(() {
                  final contactName =
                      logic.isSingleChat && Get.isRegistered<ContactsLogic>()
                          ? Get.find<ContactsLogic>()
                              .friendDisplayNameFor(logic.userID)
                          : null;
                  final cachedPresence = logic.isSingleChat &&
                          Get.isRegistered<ContactsLogic>()
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
                    title: contactName ?? logic.nickname.value,
                    titleColor: logic.isGroupChat
                        ? groupNameColor(context,
                            logic.groupFeatures.gameType(logic.groupID!))
                        : null,
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
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: Column(children: [
              if (logic.isGroupChat)
                Obx(() =>
                    logic.isChannel || logic.announcement.value.trim().isEmpty
                        ? const SizedBox.shrink()
                        : GroupAnnouncementBanner(
                            text: logic.announcement.value,
                            version: logic.announcementVersion.value,
                        publisherID: logic.groupInfo?.notificationUserID,
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
                              messageHint: logic.isGroupChat &&
                                      logic.mentions.pending.isNotEmpty
                                  ? NewMessageIndicator(
                                      labelText: logic.mentions.busy.value
                                          ? '正在定位…'
                                          : AppCopy.format('{#0}条@我的消息',
                                              [logic.mentions.pending.length]),
                                      icon: Icons.alternate_email,
                                      onTap: logic.mentions.busy.value
                                          ? null
                                          : logic.jumpToMention,
                                    )
                                  : null,
                              newMessageCount:
                                  logic.newMessages.unseenCount.value,
                              hasNewerMessages: logic.hasDeferredLatest,
                              showBackToBottom:
                                  logic.newMessages.showBackToBottom.value,
                              onSeeNewMessage: () =>
                                  logic.scrollBottom(smooth: true),
                              bottomView: input,
                              child: messages,
                            );
                            if (!logic.isGroupChat ||
                                logic.isChannel ||
                                !logic.isInGroup.value) {
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

  Widget _buildComposer() =>
      Obx(() => logic.isChannelSubscriber && !logic.isInvalidGroup
          ? ChannelNotificationBar(
              key: ValueKey(logic.conversationInfo.conversationID),
              conversation: () => logic.conversationInfo,
              changes: logic.imLogic.conversationChangedSubject,
              setMuted: (info, muted) =>
                  Get.find<ConversationLogic>().setNotDisturb(info, muted),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logic.preparingMediaCount > 0 ||
                    logic.failedMediaPreparationCount > 0)
                  ChatMediaPreparationIndicator(
                    count: logic.preparingMediaCount,
                    failedCount: logic.failedMediaPreparationCount,
                    onRetry: logic.retryMediaPreparation,
                    stageLabel: logic.mediaPreparationLabel,
                    onCancel: logic.cancelMediaPreparation,
                    onRetryOriginal: logic.hasFailedVideoPreparation
                        ? logic.retryOriginalVideoPreparation
                        : null,
                  ),
                if (logic.quotedMessage.value != null)
                  ChatComposerContextPreview(
                    message: logic.quotedMessage.value,
                    onClose: logic.clearReply,
                  ),
                if (logic.pendingForward.draft.value case final draft?)
                  PendingForwardBar(
                    key: ObjectKey(draft),
                    onOpenOptions: logic.reviewPendingForward,
                    count: draft.messages.length,
                    sending: logic.pendingForward.sending.value,
                    onCancel: logic.pendingForward.cancel,
                  ),
                ChatInputBox(
                  pendingSend: logic.pendingForward.draft.value != null,
                  pendingSending: logic.pendingForward.sending.value,
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
                  enabled: !logic.sendingMuted &&
                      !logic.pendingForward.sending.value,
                  showDisabledWarning: !logic.groupMutePending,
                  hintText: logic.groupMembershipPending
                      ? StrRes.synchronizing
                      : logic.groupMutePending
                          ? ''
                          : (logic.isChannelSubscriber
                              ? 'channelPublishRestricted'.tr
                              : logic.sendingMuted
                                  ? StrRes.youMuted
                                  : null),
                  directionalText: logic.directionalText(),
                  onCloseDirectional: logic.onClearDirectional,
                  onSend: (v) => logic.sendTextMsg(),
                  onTapVoice: logic.onTapRecord,
                  toolbox: ListenableBuilder(
                      listenable: logic.groupFeatures,
                      builder: (context, _) => ChatToolBox(
                            extraItems: logic.isGroupChat && !logic.isChannel
                                ? GroupFeatureActions.items(
                                    context, logic.groupFeatureContext,
                                    onLiveStateChanged: () => logic
                                        .groupFeatures
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

  Widget _buildMessages() =>
      ChatMessageList(key: _messageListKey, logic: logic);
}
