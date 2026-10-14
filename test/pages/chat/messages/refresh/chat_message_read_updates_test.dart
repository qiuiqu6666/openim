import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/refresh/chat_message_read_updates.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_tile.dart';
import 'package:openim/pages/chat/receipts/chat_read_receipts.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:visibility_detector/visibility_detector.dart';

Message _message(String id) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sendID': 'self',
      'recvID': 'peer',
      'sessionType': ConversationType.single,
      'sendTime': 1700000000000,
      'status': MessageStatus.succeeded,
      'isRead': false,
      'textElem': {'content': id},
    });

class _TileLogic extends GetxController implements ChatLogic {
  @override
  final messageReadUpdates = ChatMessageReadUpdates();
  @override
  final messageList = <Message>[].obs;
  @override
  final scaleFactor = 1.0.obs;
  @override
  final copyTextMap = <String?, String?>{};
  @override
  final sendStatusSub = PublishSubject<MsgStreamEv<bool>>();
  @override
  final conversationInfo = ConversationInfo(conversationID: 'chat');
  @override
  late final voicePlayback =
      VoicePlaybackController(messages: () => messageList);
  @override
  bool get isSingleChat => true;
  @override
  bool get isGroupChat => false;
  @override
  bool get isOfficialNotificationChat => false;
  @override
  String? get senderName => 'Self';
  @override
  ValueKey itemKey(Message message) => ValueKey(message.clientMsgID!);
  @override
  Map<String, String> getAtMapping(Message message) => const {};
  @override
  String? getShowTime(Message message) => null;
  @override
  String? getNewestNickname(Message message) => message.senderNickname;
  @override
  String? getNewestFaceURL(Message message) => null;
  @override
  bool canForward(Message message) => false;
  @override
  bool canFavorite(Message message) => false;
  @override
  bool canAddMessageToStickers(Message message) => false;
  @override
  bool canRevoke(Message message) => false;
  @override
  bool canTranscribeVoice(Message message) => false;
  @override
  VoiceTranscriptionState? displayedVoiceTranscription(Message message) => null;
  @override
  ValueListenable<ChatTransferStatus?>? transferStatus(Message message) => null;
  @override
  void setFundMessageVisible(Message message, bool visible) {}
  @override
  void onTapRightAvatar() {}
  @override
  void clickLinkText(String url, Object? type) {}

  void closeFixture() {
    messageReadUpdates.close();
    voicePlayback.dispose();
    sendStatusSub.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _probe(ChatMessageReadUpdates updates, String id, String slot,
        Map<String, int> builds) =>
    ListenableBuilder(
        key: ValueKey(slot),
        listenable: updates.forMessage(id),
        builder: (_, __) {
          builds.update(slot, (count) => count + 1, ifAbsent: () => 1);
          return Text('$slot:$id');
        });

void main() {
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    final interval = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(
        () => VisibilityDetectorController.instance.updateInterval = interval);
  });
  tearDown(Get.reset);

  testWidgets('real tiles refresh only the receipt target without a list event',
      (tester) async {
    final logic = _TileLogic();
    final first = _message('first'), other = _message('other');
    logic.messageList.addAll([first, other]);
    final receipts = ChatReadReceipts(
        messageList: logic.messageList,
        conversation: () => logic.conversationInfo,
        isClosed: () => false,
        onReadStateChanged: logic.messageReadUpdates.notify);
    var listEvents = 0;
    final subscription = logic.messageList.listen((_) => listEvents++);
    final builds = <String, int>{};
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            translations: TranslationService(),
            theme: ThemeData.light(),
            home: Scaffold(
                body: Column(children: [
              for (final message in logic.messageList)
                ChatMessageTile(
                    key: ValueKey(message.clientMsgID),
                    logic: logic,
                    message: message,
                    textContentBuilder: (_, message) {
                      final id = message.clientMsgID!;
                      builds.update(id, (count) => count + 1,
                          ifAbsent: () => 1);
                      return Text('$id:${message.isRead}');
                    }),
            ])))));
    await tester.pumpAndSettle();
    final before = Map<String, int>.of(builds);
    receipts.applyC2CReceipt([
      ReadReceiptInfo(userID: 'peer', msgIDList: ['first'])
    ], 'peer');
    await tester.pump(Duration.zero);
    expect(find.text('first:true'), findsOneWidget);
    expect(find.text('other:false'), findsOneWidget);
    expect(builds['first'], greaterThan(before['first']!));
    expect(builds['other'], before['other']);
    expect(listEvents, 0);
    final firstBubble = find.descendant(
        of: find.byWidgetPredicate((widget) =>
            widget is ChatMessageTile && widget.message.clientMsgID == 'first'),
        matching: find.byType(ChatItemContainer));
    expect(tester.widget<ChatItemContainer>(firstBubble).hasRead, isTrue);
    await tester.pumpWidget(const SizedBox());
    logic.messageReadUpdates.notify({'first', 'other'});
    await tester.pump();
    expect(tester.takeException(), isNull);
    receipts.close();
    await subscription.cancel();
    logic.closeFixture();
  });

  testWidgets('same ID reaches all mounted consumers and removes detached ones',
      (tester) async {
    final updates = ChatMessageReadUpdates();
    final builds = <String, int>{};
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      _probe(updates, 'shared', 'left', builds),
      _probe(updates, 'shared', 'right', builds),
      _probe(updates, 'unrelated', 'other', builds),
    ])));
    final before = Map<String, int>.of(builds);
    updates.notify({'shared'});
    await tester.pump();
    expect(builds['left'], before['left']! + 1);
    expect(builds['right'], before['right']! + 1);
    expect(builds['other'], before['other']);
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      _probe(updates, 'shared', 'left', builds),
    ])));
    final detached = builds['right'];
    final retained = builds['left']!;
    updates.notify({'shared'});
    await tester.pump();
    expect(builds['left'], retained + 1);
    expect(builds['right'], detached);
    await tester.pumpWidget(const SizedBox());
    final unmounted = Map<String, int>.of(builds);
    updates.notify({'shared', 'unrelated'});
    await tester.pump();
    expect(builds, unmounted);
    expect(tester.takeException(), isNull);
    updates.close();
  });

  testWidgets(
      'changing the message ID replaces its subscription; close is final',
      (tester) async {
    final updates = ChatMessageReadUpdates();
    final builds = <String, int>{};
    await tester
        .pumpWidget(MaterialApp(home: _probe(updates, 'old', 'slot', builds)));
    await tester
        .pumpWidget(MaterialApp(home: _probe(updates, 'new', 'slot', builds)));
    final switched = builds['slot']!;
    updates.notify({'old'});
    await tester.pump();
    expect(builds['slot'], switched);
    updates.notify({'new'});
    await tester.pump();
    expect(builds['slot'], switched + 1);
    updates.close();
    updates.notify({'new'});
    await tester.pump();
    expect(builds['slot'], switched + 1);
    await tester.pumpWidget(
        MaterialApp(home: _probe(updates, 'new', 'after-close', builds)));
    final afterClose = builds['after-close'];
    updates.notify({'new'});
    await tester.pump();
    expect(builds['after-close'], afterClose);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
