import '../channels/models/channel_kind.dart';
import '../channels/presentation/channel_ui.dart';
import 'package:openim_common/localization.dart';
import '../chat/history_search/widgets/chat_history_search_bar.dart';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../conversation/conversation_logic.dart';
import '../conversation/summary/conversation_latest_message_text.dart';
import '../chat/chat_setup/chat_history_search_page.dart';
import 'global_search_logic.dart';
import '../chat/history_search/cloud/chat_keyword_search_api.dart';
import '../chat/history_search/context/search_context_strings.dart';
import '../chat/history_search/chat_history_search_strings.dart';
import 'widgets/global_search_conversation_subtitle.dart';
import 'widgets/global_search_contact_account.dart';
import 'widgets/global_search_result_tokens.dart';
import '../official_account/widgets/official_account_name_label.dart';
import '../group_features/identity/group_name_label.dart';

class GlobalSearchPage extends StatelessWidget {
  GlobalSearchPage(
      {super.key,
      GlobalSearchLogic? logic,
      this.onCancel,
      this.searchBar,
      this.autofocus = true})
      : logic = logic ?? Get.find<GlobalSearchLogic>();
  final GlobalSearchLogic logic;
  final VoidCallback? onCancel;
  final Widget? searchBar;
  final bool autofocus;
  List<String> get tabs => [
        StrRes.globalSearchContacts,
        StrRes.groupChat,
        'globalSearchConversations'.tr,
        StrRes.globalSearchChatHistory,
        'channelsLabel'.tr
      ];

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: GlobalSearchResultTokens.background(context),
        body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => logic.focusNode.unfocus(),
            child: SafeArea(
                child: Column(children: [
              _searchHeader(context),
              Expanded(child: Obx(() {
                logic.groupRevision.value;
                final groupMessages = <String, ConversationInfo>{
                  for (final item in logic.source.currentConversations
                      .map(logic.currentConversation))
                    if (item.isGroupChat && item.groupID != null)
                      item.groupID!: item,
                };
                final rows = <Widget>[];
                void section(int id, List<Widget> children) {
                  if (children.isNotEmpty || logic.failures.contains(id)) {
                    if (rows.isNotEmpty) {
                      rows.add(const SizedBox(height: AppTokens.s3));
                    }
                    rows.add(Semantics(
                        key: ValueKey('global-search-section-$id'),
                        header: true,
                        child: Padding(
                            padding: GlobalSearchResultTokens.sectionPadding,
                            child: Text(tabs[id - 1],
                                style: GlobalSearchResultTokens.metadataStyle(
                                    context)))));
                    for (var i = 0; i < children.length; i++) {
                      if (i > 0) {
                        rows.add(_divider(context, resultRow: true));
                      }
                      rows.add(children[i]);
                    }
                  }
                  if (logic.failures.contains(id)) {
                    rows.add(ListTile(
                        title: Text(id == 4 && logic.invalidKeyword
                            ? chatHistorySearchText(context, 'keywordLength')
                            : id == 4 && logic.searchError.value != null
                                ? searchErrorText(
                                    context, logic.searchError.value)
                                : 'globalSearchFailed'.tr),
                        trailing: TextButton(
                            onPressed: id == 4 && logic.cloudHasMore.value
                                ? logic.loadMoreCloud
                                : logic.search,
                            child: Text('chatSearchRetry'.tr))));
                  }
                }

                section(
                    1,
                    logic.contactsList.map((friend) {
                      final name = friend.remark?.isNotEmpty == true
                          ? friend.remark!
                          : friend.nickname ?? friend.userID ?? '';
                      return _row(name, '', friend.faceURL, false, () {
                        if (friend.userID == null) return;
                        Get.find<ConversationLogic>()
                            .toChat(userID: friend.userID, offUntilHome: false);
                      },
                          subtitleWidget:
                              friend.userID?.contains(logic.query.value) == true
                                  ? Text('UID: ${friend.userID}')
                                  : GlobalSearchContactAccount(
                                      key: ValueKey(friend.userID),
                                      userID: friend.userID ?? '',
                                    ),
                          titleWidget: OfficialAccountNameLabel(
                            name: name,
                            userID: friend.userID,
                            ex: friend.ex,
                          ));
                    }).toList());
                for (final channel in [false, true]) {
                  section(
                      channel ? 5 : 2,
                      logic.groupList
                          .map(logic.currentGroup)
                          .where((group) => isChannelEx(group.ex) == channel)
                          .map((group) => _row(
                                  group.groupName ?? group.groupID,
                                  group.groupID.contains(logic.query.value)
                                      ? 'UID: ${group.groupID}'
                                      : channel
                                          ? channelText(
                                              context,
                                              '${group.memberCount ?? 0} 位订阅者',
                                              '${group.memberCount ?? 0} subscribers')
                                          : groupMessages[group.groupID] == null
                                              ? ''
                                              : conversationLatestMessageText(
                                                  groupMessages[
                                                      group.groupID]!),
                                  group.faceURL,
                                  true, () {
                                Get.find<ConversationLogic>().toChat(
                                    groupID: group.groupID,
                                    sessionType: group.sessionType,
                                    offUntilHome: false);
                              },
                                  titleWidget: GroupNameLabel(
                                      name: group.groupName ?? group.groupID,
                                      groupID: group.groupID,
                                      ex: group.ex,
                                      store: logic.source.groupFeatures)))
                          .toList());
                }
                section(
                    3,
                    logic.conversations
                        .map(logic.currentConversation)
                        .map((item) => _row(
                            item.showName ?? '',
                            '',
                            item.faceURL,
                            item.isGroupChat,
                            () => Get.find<ConversationLogic>().toChat(
                                conversationInfo: item, offUntilHome: false),
                            titleWidget: item.isGroupChat
                                ? GroupNameLabel(
                                    name: item.showName ?? '',
                                    groupID: item.groupID,
                                    store: logic.source.groupFeatures)
                                : OfficialAccountNameLabel(
                                    name: item.showName ?? '',
                                    userID: item.userID,
                                    ex: item.ex,
                                    isSingleChat: item.conversationType ==
                                        ConversationType.single),
                            subtitleWidget:
                                GlobalSearchConversationSubtitle.hasContent(
                                        item)
                                    ? GlobalSearchConversationSubtitle(
                                        conversation: item)
                                    : null))
                        .toList());
                section(4, [
                  ...logic.cloudConversationHits.map(_cloudConversation),
                  ...logic.textSearchResultItems
                      .map((item) => _messages(item, false))
                ]);
                if (logic.query.value.isNotEmpty &&
                    !logic.failures.contains(4) &&
                    (!logic.cloudLoading.value &&
                        !logic.pendingSections.contains(4) &&
                        logic.cloudHasMore.value)) {
                  rows.add(Padding(
                    padding: const EdgeInsets.all(AppTokens.s4),
                    child: TextButton(
                        key: const ValueKey('global-history-cloud-more'),
                        onPressed: logic.loadMoreCloud,
                        child: Text('chatSearchMore'.tr)),
                  ));
                }
                if (logic.query.value.isNotEmpty &&
                    !logic.loading.value &&
                    !logic.cloudLoading.value &&
                    !logic.cloudHasMore.value &&
                    !logic.failures.contains(4) &&
                    rows.isNotEmpty) {
                  rows.add(Padding(
                    key: const ValueKey('global-search-no-more'),
                    padding: const EdgeInsets.all(AppTokens.s4),
                    child: Center(
                      child: Text('chatSearchNoMore'.tr,
                          style: TextStyle(
                              color: AppTokens.textSecondary(
                                  dark: Theme.of(context).brightness ==
                                      Brightness.dark))),
                    ),
                  ));
                }
                if (logic.query.value.isEmpty) return _empty(context);
                if (rows.isEmpty && !logic.loading.value) {
                  return _empty(context, noResults: true);
                }
                return ListView.builder(
                    key: ValueKey(logic.query.value),
                    primary: false,
                    padding: const EdgeInsets.only(bottom: AppTokens.s5),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: rows.length,
                    itemBuilder: (_, i) => rows[i]);
              })),
            ]))),
      );

  Widget _searchHeader(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('global-search-header'),
      color: GlobalSearchResultTokens.background(context),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        searchBar ??
            ChatHistorySearchBar(
              controller: logic.searchCtrl,
              focusNode: logic.focusNode,
              autofocus: autofocus,
              hintText: StrRes.search,
              cancelColor: AppTokens.accent,
              onChanged:
                  (_) {}, // The controller listener owns debounce and clearing.
              onSubmitted: (_) => logic.search(),
              onCancel: () {
                logic.focusNode.unfocus();
                if (onCancel != null) {
                  onCancel!();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
            ),
        const SizedBox(height: AppTokens.s2),
        Obx(() {
          if (logic.query.value.isEmpty) return const SizedBox.shrink();
          final busy = logic.loading.value ||
              logic.cloudLoading.value ||
              logic.pendingSections.isNotEmpty;
          return SizedBox(
            height: AppTokens.s2,
            child: busy
                ? LinearProgressIndicator(
                    key: const ValueKey('global-search-progress'),
                    color: AppTokens.accent,
                    backgroundColor: AppTokens.border(
                        dark: Theme.of(context).brightness == Brightness.dark),
                    semanticsLabel: 'profileCommonGroupsLoading'.tr,
                  )
                : Center(child: _divider(context)),
          );
        }),
      ]),
    );
  }

  Widget _divider(BuildContext context, {bool resultRow = false}) {
    final theme = Theme.of(context);
    return Divider(
        height: GlobalSearchResultTokens.dividerThickness,
        thickness: GlobalSearchResultTokens.dividerThickness,
        indent: resultRow ? GlobalSearchResultTokens.dividerInset : 0,
        endIndent: resultRow ? GlobalSearchResultTokens.horizontalPadding : 0,
        color: AppTokens.border(dark: theme.brightness == Brightness.dark));
  }

  Widget _empty(BuildContext context, {bool noResults = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!noResults) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s5, vertical: AppTokens.s8),
          child: Text('globalSearchScopeHint'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppTokens.captionFontSize,
                  color: AppTokens.textSecondary(dark: dark)
                      .withValues(alpha: .6))),
        ),
      );
    }
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                    child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        width: 150,
                        height: 140,
                        child: Stack(alignment: Alignment.center, children: [
                          Positioned(
                              left: 20,
                              top: 18,
                              child: Icon(Icons.description_rounded,
                                  size: 90,
                                  color: AppTokens.textSecondary(dark: dark)
                                      .withValues(alpha: .08))),
                          Positioned(
                              right: 6,
                              bottom: 4,
                              child: Icon(Icons.search_rounded,
                                  size: 115,
                                  color: AppTokens.textSecondary(dark: dark)
                                      .withValues(alpha: .18))),
                        ])),
                    const SizedBox(height: 24),
                    Text(
                        noResults
                            ? 'chatSearchEmpty'.tr
                            : 'globalSearchHint'.tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppTokens.textPrimary(dark: dark),
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Text(
                        zh
                            ? (noResults
                                ? AppCopy.text('试试其他关键词')
                                : AppCopy.text('输入关键词，快速找到你想要的内容'))
                            : (noResults
                                ? 'Try another keyword'
                                : 'Enter a keyword to find what you need'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppTokens.textSecondary(dark: dark),
                            fontSize: 14)),
                  ]),
                )),
              ),
            ));
  }

  Widget _row(String title, String subtitle, String? avatar, bool group,
          VoidCallback tap,
          {Widget? subtitleWidget, Widget? titleWidget, int? sentAt}) =>
      Builder(
          builder: (context) => ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: GlobalSearchResultTokens.horizontalPadding),
              minTileHeight: GlobalSearchResultTokens.rowMinHeight,
              minVerticalPadding: GlobalSearchResultTokens.verticalPadding,
              minLeadingWidth: GlobalSearchResultTokens.avatarSize,
              visualDensity: VisualDensity.standard,
              titleAlignment: ListTileTitleAlignment.center,
              horizontalTitleGap: GlobalSearchResultTokens.avatarTextGap,
              titleTextStyle: GlobalSearchResultTokens.titleStyle(context),
              subtitleTextStyle:
                  GlobalSearchResultTokens.subtitleStyle(context),
              leading: AvatarView(
                  url: avatar,
                  text: title,
                  isGroup: group,
                  isCircle: true,
                  width: GlobalSearchResultTokens.avatarSize,
                  height: GlobalSearchResultTokens.avatarSize),
              title: sentAt == null
                  ? titleWidget ??
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)
                  : LayoutBuilder(
                      builder: (context, constraints) => Row(children: [
                            Expanded(
                                child: titleWidget ??
                                    Text(title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: AppTokens.s3),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth * .4),
                              child: Text(
                                  formatChatMessageTime(context, sentAt),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: GlobalSearchResultTokens.metadataStyle(
                                      context)),
                            ),
                          ])),
              subtitle: subtitleWidget == null && graphemeTrim(subtitle).isEmpty
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(
                          top: GlobalSearchResultTokens.textGap),
                      child: subtitleWidget ??
                          Text(subtitle,
                              maxLines: 2, overflow: TextOverflow.ellipsis)),
              onTap: () {
                logic.focusNode.unfocus();
                tap();
              }));

  Widget _messages(SearchResultItems item, bool files) {
    final message = item.messageList?.firstOrNull;
    final preview = message == null ? '' : IMUtils.parseMsg(message);
    final conversation = logic.source.currentConversations
        .where((row) => row.conversationID == item.conversationID)
        .map(logic.currentConversation)
        .firstOrNull;
    final groupID = conversation?.groupID ?? message?.groupID;
    final group = groupID == null || groupID.isEmpty
        ? null
        : logic.currentGroup(GroupInfo(
            groupID: groupID, groupName: item.showName, faceURL: item.faceURL));
    return _row(
        group?.groupName ??
            conversation?.showName ??
            item.showName ??
            item.conversationID ??
            '',
        '${'globalSearchMatchCount'.trArgs([
              '${item.messageCount ?? item.messageList?.length ?? 0}'
            ])} · $preview',
        group?.faceURL ?? conversation?.faceURL ?? item.faceURL,
        item.conversationType != ConversationType.single, () {
      if (item.conversationID == null) return;
      Get.to(() => ChatHistorySearchPage(
          conversationID: item.conversationID!,
          isChannel: _isChannelConversation(item.conversationID!),
          isGroup: item.conversationType != ConversationType.single,
          initialQuery: logic.query.value,
          filesOnly: files));
    }, sentAt: message?.sendTime);
  }

  bool _isChannelConversation(String id) {
    final conversation = logic.source.currentConversations
        .where((item) => item.conversationID == id)
        .firstOrNull;
    final groupID = conversation?.groupID;
    if (groupID == null) return false;
    final group =
        logic.groupList.where((item) => item.groupID == groupID).firstOrNull ??
            logic.source.groupFeatures?.cachedGroupInfo(groupID);
    return isChannelEx(group?.ex);
  }

  Widget _cloudConversation(CloudKeywordMessage message) {
    final matches = logic.source.currentConversations
        .where((c) => c.conversationID == message.conversationID);
    final conversation =
        matches.isEmpty ? null : logic.currentConversation(matches.first);
    return _row(
        conversation?.showName ?? message.conversationID,
        message.summary,
        conversation?.faceURL,
        conversation?.isGroupChat ?? message.conversationID.startsWith('sg_'),
        () => Get.to(() => ChatHistorySearchPage(
            conversationID: message.conversationID,
            isChannel: _isChannelConversation(message.conversationID),
            isGroup: conversation?.isGroupChat ??
                message.conversationID.startsWith('sg_'),
            initialQuery: logic.query.value)),
        sentAt: message.sendTime);
  }
}
