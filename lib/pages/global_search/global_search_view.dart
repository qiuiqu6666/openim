import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../conversation/conversation_logic.dart';
import '../chat/chat_setup/chat_history_search_page.dart';
import 'global_search_logic.dart';

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
        appBar: GlassAppBar(title: Text(StrRes.search)),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: logic.searchCtrl,
                focusNode: logic.focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => logic.search(),
                decoration: InputDecoration(
                    hintText: 'globalSearchHint'.tr,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                        tooltip: 'globalSearchClear'.tr,
                        onPressed: logic.searchCtrl.clear,
                        icon: const Icon(Icons.close)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12))),
              )),
          SizedBox(
              height: 48,
              child: Obx(() {
                final selected = logic.index.value;
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ChoiceChip(
                      label: Text(tabs[i]),
                      selected: selected == i,
                      onSelected: (_) => logic.index.value = i),
                );
              })),
          Obx(() => logic.loading.value
              ? const LinearProgressIndicator()
              : const SizedBox(height: 4)),
          Expanded(child: Obx(() {
            final selected = logic.index.value;
            final rows = <Widget>[];
            void section(int id, List<Widget> children) {
              if (selected != 0 && selected != id) return;
              if (children.isNotEmpty || logic.failures.contains(id)) {
                rows.add(Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(tabs[id],
                        style: Theme.of(context).textTheme.titleSmall)));
                rows.addAll(children);
              }
              if (logic.failures.contains(id))
                rows.add(ListTile(
                    title: Text('globalSearchFailed'.tr),
                    trailing: TextButton(
                        onPressed: logic.search,
                        child: Text('chatSearchRetry'.tr))));
            }

            section(
                1,
                logic.contactsList.map((friend) {
                  final name = friend.remark?.isNotEmpty == true
                      ? friend.remark!
                      : friend.nickname ?? friend.userID ?? '';
                  return _row(name, friend.userID ?? '', friend.faceURL, false,
                      () {
                    if (friend.userID == null) return;
                    Get.find<ConversationLogic>()
                        .toChat(userID: friend.userID, offUntilHome: false);
                  });
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
                            conversationInfo: item, offUntilHome: false)))
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
            if (logic.query.value.isEmpty)
              return Center(child: Text('globalSearchHint'.tr));
            if (rows.isEmpty && !logic.loading.value)
              return Center(child: Text('chatSearchEmpty'.tr));
            return ListView.builder(
                key: ValueKey('${logic.query.value}:$selected'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: rows.length,
                itemBuilder: (_, i) => rows[i]);
          })),
        ])),
      );

  Widget _row(String title, String subtitle, String? avatar, bool group,
          VoidCallback tap) =>
      ListTile(
          leading: AvatarView(url: avatar, text: title, isGroup: group),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
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
          initialQuery: logic.query.value,
          filesOnly: files));
    });
  }
}
