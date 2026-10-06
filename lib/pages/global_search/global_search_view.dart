import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../conversation/conversation_logic.dart';
import '../chat/chat_setup/chat_history_search_page.dart';
import 'global_search_logic.dart';
import 'widgets/global_search_conversation_subtitle.dart';
import '../official_account/widgets/official_account_name_label.dart';

class GlobalSearchPage extends StatelessWidget {
  GlobalSearchPage({super.key});
  final logic = Get.find<GlobalSearchLogic>();
  List<String> get tabs => [
        StrRes.globalSearchAll,
        StrRes.globalSearchContacts,
        StrRes.globalSearchGroup,
        'globalSearchConversations'.tr,
        StrRes.globalSearchChatHistory,
        StrRes.globalSearchChatFile
      ];

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTokens.surface(
            dark: Theme.of(context).brightness == Brightness.dark),
        appBar: GlassAppBar(
          backgroundColor: AppTokens.surface(
              dark: Theme.of(context).brightness == Brightness.dark),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leadingWidth: AppIconTokens.androidTouchTarget + AppTokens.s3,
          actions: const [
            SizedBox(width: AppIconTokens.androidTouchTarget + AppTokens.s3),
          ],
          toolbarHeight: NavigationGlassTokens.toolbarHeight,
          leading: Center(
              child: SizedBox.square(
            dimension: AppIconTokens.androidTouchTarget,
            child: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppTokens.accent,
                    size: NavigationGlassTokens.iconSize),
                onPressed: () {
                  logic.focusNode.unfocus();
                  Get.back();
                }),
          )),
          title: Text(StrRes.search,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: AppTokens.listTitleFontSize,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary(
                      dark: Theme.of(context).brightness == Brightness.dark))),
        ),
        body: SafeArea(
            top: false,
            child: Column(children: [
              _searchHeader(context),
              Expanded(child: Obx(() {
                final selected = logic.index.value;
                final rows = <Widget>[];
                void section(int id, List<Widget> children) {
                  if (selected != 0 && selected != id) return;
                  if (children.isNotEmpty || logic.failures.contains(id)) {
                    if (rows.isNotEmpty) rows.add(_divider(context));
                    rows.add(Semantics(
                        key: ValueKey('global-search-section-$id'),
                        header: true,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppTokens.s5,
                                vertical: AppTokens.s3),
                            child: Text(tabs[id],
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
                        title: Text('globalSearchFailed'.tr),
                        trailing: TextButton(
                            onPressed: logic.search,
                            child: Text('chatSearchRetry'.tr))));
                  }
                }

                section(
                    1,
                    logic.contactsList.map((friend) {
                      final name = friend.remark?.isNotEmpty == true
                          ? friend.remark!
                          : friend.nickname ?? friend.userID ?? '';
                      return _row(
                          name, friend.userID ?? '', friend.faceURL, false, () {
                        if (friend.userID == null) return;
                        Get.find<ConversationLogic>()
                            .toChat(userID: friend.userID, offUntilHome: false);
                      },
                          titleWidget: OfficialAccountNameLabel(
                            name: name,
                            userID: friend.userID,
                            ex: friend.ex,
                          ));
                    }).toList());
                section(
                    2,
                    logic.groupList
                        .map((group) => _row(group.groupName ?? group.groupID,
                                group.groupID, group.faceURL, true, () {
                              Get.find<ConversationLogic>().toChat(
                                  groupID: group.groupID,
                                  sessionType: group.sessionType,
                                  offUntilHome: false);
                            }))
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
                            titleWidget: OfficialAccountNameLabel(
                                name: item.showName ?? '',
                                userID: item.userID,
                                ex: item.ex,
                                isSingleChat: item.conversationType ==
                                    ConversationType.single),
                            subtitleWidget: GlobalSearchConversationSubtitle(
                                conversation: item)))
                        .toList());
                section(
                    4,
                    logic.textSearchResultItems
                        .map((item) => _messages(item, false))
                        .toList());
                section(
                    5,
                    logic.fileSearchResultItems
                        .map((item) => _messages(item, true))
                        .toList());
                if (logic.query.value.isEmpty) return _empty(context);
                if (rows.isEmpty && !logic.loading.value) {
                  return _empty(context, noResults: true);
                }
                return ListView.builder(
                    key: ValueKey('${logic.query.value}:$selected'),
                    primary: false,
                    padding: const EdgeInsets.only(
                        top: AppTokens.s3, bottom: AppTokens.s5),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: rows.length,
                    itemBuilder: (_, i) => rows[i]);
              })),
            ])),
      );

  Widget _searchHeader(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = AppTokens.textSecondary(dark: dark);
    final inputHeight =
        (MediaQuery.textScalerOf(context).scale(AppTokens.captionFontSize) *
                    1.2 +
                AppTokens.s6)
            .clamp(AppIconTokens.androidTouchTarget, double.infinity)
            .toDouble();
    return ColoredBox(
      key: const ValueKey('global-search-header'),
      color: AppTokens.surface(dark: dark),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.s4, AppTokens.s4, AppTokens.s4, AppTokens.s3),
          child: SearchBox(
            controller: logic.searchCtrl,
            focusNode: logic.focusNode,
            enabled: true,
            height: inputHeight,
            hintText: 'globalSearchHint'.tr,
            textStyle: TextStyle(
                color: AppTokens.textPrimary(dark: dark),
                fontSize: AppTokens.captionFontSize,
                height: 1.2),
            hintStyle: TextStyle(
                color: secondary,
                fontSize: AppTokens.captionFontSize,
                height: 1.2),
            backgroundColor: AppTokens.background(dark: dark),
            borderRadius: BorderRadius.circular(NavigationGlassTokens.radius),
            padding: const EdgeInsets.only(left: AppTokens.s5),
            searchIcon: Icon(Icons.search_rounded,
                color: secondary, size: NavigationGlassTokens.iconSize),
            clearIcon: SizedBox.square(
                dimension: AppIconTokens.androidTouchTarget,
                child: IconButton(
                    tooltip: 'globalSearchClear'.tr,
                    onPressed: logic.searchCtrl.clear,
                    icon: Icon(Icons.cancel_rounded,
                        color: secondary.withValues(alpha: .4)))),
            onSubmitted: (_) => logic.search(),
          ),
        ),
        Obx(() {
          final selected = logic.index.value;
          return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
              child: Row(children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppTokens.s3),
                  ChoiceChip(
                      label: Text(tabs[i],
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected == i
                                  ? AppTokens.accent
                                  : secondary)),
                      showCheckmark: false,
                      surfaceTintColor: Colors.transparent,
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                      selectedColor: AppTokens.accent.withValues(alpha: .1),
                      backgroundColor: AppTokens.surface(dark: dark),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.s3, vertical: AppTokens.s2),
                      selected: selected == i,
                      onSelected: (_) => logic.index.value = i),
                ],
              ]));
        }),
        const SizedBox(height: AppTokens.s2),
        SizedBox(
            height: AppTokens.s2,
            child: Obx(() => logic.loading.value
                ? const LinearProgressIndicator(minHeight: AppTokens.s2)
                : const SizedBox.expand())),
        _divider(context),
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
          VoidCallback tap, {Widget? subtitleWidget, Widget? titleWidget}) =>
      ListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s5, vertical: AppTokens.s2),
          horizontalTitleGap: AppTokens.s4,
          leading: AvatarView(
              url: avatar, text: title, isGroup: group, isCircle: true),
          title: titleWidget ??
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    });
  }
}
