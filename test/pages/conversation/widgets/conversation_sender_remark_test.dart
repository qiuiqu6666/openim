import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/summary/conversation_latest_message_text.dart';
import 'package:openim/pages/conversation/widgets/conversation_feed_row.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/conversation_live_fixture.dart';

class _Remarks extends GetxController implements ContactRemarkSource {
  final remarks = <String, String>{}.obs;
  final owner = OpenIM.iMManager.userID;

  @override
  bool get isCurrentSession => owner == OpenIM.iMManager.userID;

  @override
  String? remarkFor(String? userID) {
    final value = remarks[userID]?.trim();
    return isCurrentSession && value?.isNotEmpty == true ? value : null;
  }

  @override
  Iterable<String> matchingRemarkUserIDs(String keyword) =>
      remarks.keys.where((id) =>
          remarks[id]!.toLowerCase().contains(keyword.trim().toLowerCase()));
}

class _FeedLogic extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  @override
  bool isGroupChat(ConversationInfo info) => info.isGroupChat;
  @override
  bool isNotDisturb(ConversationInfo info) => info.recvMsgOpt == 2;
  @override
  int getUnreadCount(ConversationInfo info) => info.unreadCount;
  @override
  String getShowName(ConversationInfo info) => info.showName ?? '';
  @override
  String getContent(ConversationInfo info) => info.draftText?.isNotEmpty == true
      ? info.draftText!
      : conversationLatestMessageText(info);
  @override
  String getTime(ConversationInfo info) => '13:22';
  @override
  String? getPrefixTag(ConversationInfo info) => conversationPrefixTag(info);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationInfo _group() => ConversationInfo(
      conversationID: 'sg_team',
      conversationType: ConversationType.superGroup,
      groupID: 'team',
      showName: '群聊',
      unreadCount: 108,
      recvMsgOpt: 2,
      latestMsg: Message(
        clientMsgID: 'latest',
        contentType: MessageType.text,
        sendID: 'peer',
        senderNickname: '原昵称',
        textElem: TextElem(content: '消息内容'),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Remarks remarks;

  setUp(() async {
    Get.testMode = true;
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
    OpenIM.iMManager.userID = 'self';
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    remarks = _Remarks();
    Get.put<ContactRemarkSource>(remarks);
  });
  tearDown(Get.reset);

  test(
      'sender remarks preserve message data, own summaries and account isolation',
      () {
    final group = _group();
    final before = group.latestMsg!.toJson();
    remarks.remarks['peer'] = '  老王⬇️  ';
    expect(conversationLatestMessageText(group), '老王⬇️: 消息内容 ');
    expect(group.latestMsg!.toJson(), before);
    group.latestMsg!.senderNickname = null;
    expect(conversationLatestMessageText(group), '老王⬇️: 消息内容 ');
    group.latestMsg!.senderNickname = '原昵称';
    group.latestMsg!.sendID = 'self';
    remarks.remarks['self'] = '自己的备注';
    expect(conversationLatestMessageText(group), '消息内容');
    group.latestMsg!.sendID = 'peer';
    OpenIM.iMManager.userID = 'another-account';
    expect(conversationLatestMessageText(group), '原昵称: 消息内容 ');
  });

  for (final dark in [false, true]) {
    for (final archived in [false, true]) {
      testWidgets(
          'main/archive preview reacts to remark edits ($dark/$archived)',
          (tester) async {
        final logic = _FeedLogic();
        addTearDown(logic.onDelete.call);
        final group = _group();
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: Scaffold(
              body: ConversationFeedRow(
                logic: logic,
                info: group,
                showDivider: true,
                editing: false,
                selected: false,
                archivedLayout: archived,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        ));
        String content() =>
            tester.widget<MatchTextView>(find.byType(MatchTextView)).text;
        expect(content(), '原昵称: 消息内容 ');
        remarks.remarks['peer'] = '老王⬇️';
        await tester.pump();
        expect(content(), '老王⬇️: 消息内容 ');
        remarks.remarks['peer'] = '新备注';
        await tester.pump();
        expect(content(), '新备注: 消息内容 ');
        remarks.remarks.remove('peer');
        await tester.pump();
        expect(content(), '原昵称: 消息内容 ');
        expect(group.latestMsg!.senderNickname, '原昵称');
        expect(group.unreadCount, 108);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
