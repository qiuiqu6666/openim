import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim_common/openim_common.dart';

/// Mounts the production controller with cheap rows, without ChatPage plugins.
/// The common variant passes immutable ID snapshots like the production view.
Widget buildChatEntryList(ChatLogic logic,
    {bool commonList = false,
    bool showInput = false,
    double Function(Message)? rowHeight,
    void Function(List<String>, double)? observeViewport}) {
  final chat = Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 360,
        height: 240,
        child: NotificationListener<ScrollNotification>(
          onNotification: logic.onChatScrollNotification,
          child: Obx(() {
            final rows = logic.messageList.reversed.toList();
            if (commonList) {
              final ids = rows.map((message) => message.clientMsgID!).toList();
              final indices = <String, int>{
                for (var index = 0; index < ids.length; index++)
                  ids[index]: index
              };
              return ChatListView(
                controller: logic.scrollController,
                loadOnInit: false,
                hasMore: false,
                itemCount: rows.length,
                messageIDs: ids,
                onViewportChanged: (ids, distance) {
                  logic.onChatViewportChanged(ids, distance);
                  observeViewport?.call(ids, distance);
                },
                findChildIndexCallback: (key) =>
                    key is ValueKey<String> ? indices[key.value] : null,
                itemBuilder: (_, index) => SizedBox(
                  key: ValueKey(ids[index]),
                  height: rowHeight?.call(rows[index]) ?? 48,
                  child: Text(ids[index]),
                ),
              );
            }
            return ListView.builder(
              controller: logic.scrollController,
              reverse: true,
              itemExtent: 48,
              itemCount: rows.length,
              itemBuilder: (_, index) => Text(rows[index].clientMsgID!),
            );
          }),
        ),
      ),
    ),
  );
  final content = showInput
      ? MaterialApp(
          home: Scaffold(
            body: Column(children: [
              Expanded(child: chat),
              TextField(
                controller: logic.inputCtrl,
                focusNode: logic.focusNode,
              ),
            ]),
          ),
        )
      : chat;
  return commonList
      ? ScreenUtilInit(
          designSize: const Size(375, 812), builder: (_, __) => content)
      : content;
}

void expectMessageInsideChatList(WidgetTester tester, String id) {
  final viewport = tester.getRect(find.byType(ChatListView));
  // The common measured row retains the builder's key on its outer wrapper.
  final row = tester.getRect(find.byKey(ValueKey(id)).first);
  expect(row.top, greaterThanOrEqualTo(viewport.top - 0.5));
  expect(row.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
}
