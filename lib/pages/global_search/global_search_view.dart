import '../chat/history_search/widgets/chat_history_search_bar.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../conversation/conversation_logic.dart';
import '../conversation/summary/conversation_latest_message_text.dart';
import '../chat/chat_setup/chat_history_search_page.dart';
import 'global_search_logic.dart';
import '../chat/history_search/cloud/chat_keyword_search_api.dart';
import '../chat/history_search/navigation/chat_history_message_navigation.dart';
import '../chat/history_search/context/search_context_strings.dart';
import '../chat/history_search/chat_history_search_strings.dart';
import 'widgets/global_search_conversation_subtitle.dart';
import 'widgets/global_search_contact_account.dart';
import '../official_account/widgets/official_account_name_label.dart';
import '../group_features/identity/group_name_label.dart';

class GlobalSearchPage extends StatelessWidget {
  GlobalSearchPage({super.key});
  final logic = Get.find<GlobalSearchLogic>();
  late final _messageNavigation = ChatHistoryMessageNavigation();
  List<String> get tabs => [
        StrRes.globalSearchContacts,
        StrRes.groupChat,
        'globalSearchConversations'.tr,
        StrRes.globalSearchChatHistory
      ];

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTokens.surface(
            dark: Theme.of(context).brightness == Brightness.dark),
        body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => logic.focusNode.unfocus(),
            child: SafeArea(
                child: Column(children: [
              _searchHeader(context),
              Expanded(child: Obx(() {
                final groupMessages = <String, ConversationInfo>{
                  for (final item in logic.source.currentConversations)
                    if (item.isGroupChat && item.groupID != null)
                      item.groupID!: item,
                };
                final rows = <Widget>[];
                void section(int id, List<Widget> children) {
                  if (children.isNotEmpty || logic.failures.contains(id)) {
                    if (rows.isNotEmpty) rows.add(_divider(context));
                    rows.add(Semantics(
                        key: ValueKey('global-search-section-$id'),
                        header: true,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppTokens.s5,
                                vertical: AppTokens.s3),
                            child: Text(tabs[id - 1],
                                style: TextStyle(
                                    color: AppTokens.textSecondary(
                                        dark: Theme.of(context).brightness ==
                                            Brightness.dark),
                                    fontSize: AppTokens.captionFontSize,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3)))));
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
                          subtitleWidget: GlobalSearchContactAccount(
                            key: ValueKey(friend.userID),
                            userID: friend.userID ?? '',
                          ),
                          titleWidget: OfficialAccountNameLabel(
                            name: name,
                            userID: friend.userID,
                            ex: friend.ex,
                          ));
                    }).toList());
                section(
                    2,
                    logic.groupList
                        .map((group) => _row(
                                group.groupName ?? group.groupID,
                                groupMessages[group.groupID] == null
                                    ? ''
                                    : conversationLatestMessageText(
                                        groupMessages[group.groupID]!),
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
                section(
                    3,
                    logic.conversations
                        .map((item) => _row(
                            item.showName ?? '',
                            item.isGroupChat
                                ? StrRes.globalSearchGroup
                                : StrRes.singleChat,
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
                            subtitleWidget: GlobalSearchConversationSubtitle(
                                conversation: item)))
                        .toList());
                section(4, [
                  ...logic.cloudHits
                      .map((message) => _cloudMessage(context, message)),
                  ...logic.textSearchResultItems
                      .map((item) => _messages(item, false))
                ]);
                if (logic.query.value.isNotEmpty &&
                    !logic.failures.contains(4) &&
                    (logic.cloudLoading.value || logic.cloudHasMore.value)) {
                  rows.add(Padding(
                    padding: const EdgeInsets.all(AppTokens.s4),
                    child: logic.cloudLoading.value
                        ? const Center(child: CircularProgressIndicator())
                        : TextButton(
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
                    padding: const EdgeInsets.only(
                        top: AppTokens.s3, bottom: AppTokens.s5),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: rows.length,
                    itemBuilder: (_, i) => rows[i]);
              })),
            ]))),
      );

  Widget _searchHeader(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      key: const ValueKey('global-search-header'),
      color: AppTokens.surface(dark: dark),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ChatHistorySearchBar(
          controller: logic.searchCtrl,
          focusNode: logic.focusNode,
          autofocus: true,
          hintText: StrRes.search,
          cancelColor: AppTokens.accent,
          onChanged:
              (_) {}, // The controller listener owns debounce and clearing.
          onSubmitted: (_) => logic.search(),
          onCancel: () {
            logic.focusNode.unfocus();
            Navigator.of(context).maybePop();
          },
        ),
        const SizedBox(height: AppTokens.s2),
        SizedBox(
            height: AppTokens.s2,
            child: Obx(() => logic.loading.value
                ? const LinearProgressIndicator(minHeight: AppTokens.s2)
                : const SizedBox.expand())),
        Obx(() => logic.query.value.isEmpty
            ? const SizedBox.shrink()
            : _divider(context)),
      ]),
    );
  }

  Widget _divider(BuildContext context, {bool resultRow = false}) {
    final theme = Theme.of(context);
    final tileTheme = ListTileTheme.of(context);
    final avatarSize = math.min(
        (AppTokens.s8 + AppTokens.s4).w, (AppTokens.s8 + AppTokens.s4).h);
    final leadingWidth = tileTheme.minLeadingWidth ??
        (theme.useMaterial3 ? AppTokens.s7 : AppTokens.s8 + AppTokens.s3);
    final density = tileTheme.visualDensity ?? theme.visualDensity;
    return Divider(
        height: 1,
        thickness: .5,
        indent: resultRow
            ? AppTokens.s5 +
                math.max(leadingWidth, avatarSize) +
                AppTokens.s4 +
                density.horizontal * 2
            : 0,
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
                            ? (noResults ? '试试其他关键词' : '输入关键词，快速找到你想要的内容')
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
      ListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s5, vertical: AppTokens.s2),
          horizontalTitleGap: AppTokens.s4,
          leading: AvatarView(
              url: avatar, text: title, isGroup: group, isCircle: true),
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
                          child: Text(formatChatMessageTime(context, sentAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: AppTokens.textSecondary(
                                          dark: Theme.of(context).brightness ==
                                              Brightness.dark))),
                        ),
                      ])),
          subtitle: subtitleWidget ??
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () {
            logic.focusNode.unfocus();
            tap();
          });

  Widget _messages(SearchResultItems item, bool files) {
    final message = item.messageList?.firstOrNull;
    final preview = message == null ? '' : IMUtils.parseMsg(message);
    return _row(
        item.showName ?? item.conversationID ?? '',
        '${'globalSearchMatchCount'.trArgs([
              '${item.messageCount ?? item.messageList?.length ?? 0}'
            ])} · $preview',
        item.faceURL,
        item.conversationType != ConversationType.single, () {
      if (item.conversationID == null) return;
      Get.to(() => ChatHistorySearchPage(
          conversationID: item.conversationID!,
          isGroup: item.conversationType != ConversationType.single,
          initialQuery: logic.query.value,
          filesOnly: files));
    }, sentAt: message?.sendTime);
  }

  Widget _cloudMessage(BuildContext context, CloudKeywordMessage message) {
    final matches = logic.source.currentConversations
        .where((c) => c.conversationID == message.conversationID);
    final conversation = matches.isEmpty ? null : matches.first;
    return _row(
        conversation?.showName ?? message.conversationID,
        message.summary,
        conversation?.faceURL,
        conversation?.isGroupChat ?? message.conversationID.startsWith('sg_'),
        () => _messageNavigation.open(context,
            conversationID: message.conversationID,
            message: message,
            isEntryCurrent: () => logic.cloudHits.contains(message)),
        sentAt: message.sendTime);
  }
}
