import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/media/preparation/pending_chat_media.dart';
import 'package:openim/pages/chat/media/widgets/pending_chat_media_bubble.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';
import '../../support/chat/chat_recovery_fixture.dart';

class _Asset extends AssetEntity {
  const _Asset() : super(id: 'selected', typeInt: 1, width: 100, height: 100);
  @override
  Future<Uint8List?> thumbnailDataWithSize(ThumbnailSize size,
          {ThumbnailFormat format = ThumbnailFormat.jpeg,
          int quality = 100,
          PMProgressHandler? progressHandler,
          int frame = 0}) async =>
      null;
}

void main() {
  recoveryScenario('pending bubble uses timeline without entering SDK history',
      (tester, fixture) async {
    PendingChatMedia.entries.clear();
    addTearDown(PendingChatMedia.entries.clear);
    final latest = recoveryMessage('latest', 1);
    fixture.localSnapshot = [latest];
    Get.routing.args = {
      'conversationInfo': fixture.conversation(latest: latest)
    };
    final logic = fixture.logic = ChatLogic();
    logic.onInit();
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          home: Scaffold(
              body: ChatMessageList(
        logic: logic,
        messageBuilder: (_, message) => Text(message.clientMsgID!),
      ))),
    ));
    fixture.calls.single.complete([latest], isEnd: true);
    await tester.pumpAndSettle();
    final pending = PendingChatMedia(
        asset: const _Asset(),
        conversationID: logic.conversationInfo.conversationID,
        visible: () => true);
    PendingChatMedia.entries.add(pending);
    await tester.pump();
    expect(find.byType(PendingChatMediaBubble), findsOneWidget);
    expect(logic.messageList.map((message) => message.clientMsgID), ['latest']);
    PendingChatMedia.entries.remove(pending);
    await tester.pump();
    expect(find.byType(PendingChatMediaBubble), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
