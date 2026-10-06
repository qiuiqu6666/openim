import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/widgets/conversation_feed_row.dart';
import 'package:openim/pages/official_account/official_account_chrome_tokens.dart';
import 'package:openim/pages/official_account/widgets/official_account_name_label.dart';
import 'package:openim_common/openim_common.dart';

import '../../../support/conversation_live_fixture.dart';

class _FeedLogic extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  @override
  bool isGroupChat(ConversationInfo info) => info.isGroupChat;
  @override
  bool isNotDisturb(ConversationInfo info) => info.recvMsgOpt == 2;
  @override
  int getUnreadCount(ConversationInfo info) => 0;
  @override
  String getShowName(ConversationInfo info) => info.showName ?? '';
  @override
  String getContent(ConversationInfo info) => 'Recent SDK message';
  @override
  String getTime(ConversationInfo info) => '12:30';
  @override
  String? getPrefixTag(ConversationInfo info) => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder get _badges => find.byWidgetPredicate((widget) =>
    widget is Image &&
    widget.image is AssetImage &&
    (widget.image as AssetImage).assetName ==
        OfficialAccountChromeTokens.badgeAsset);

ConversationInfo _conversation(String id,
        {String? name, String? ex, bool group = false, bool muted = false}) =>
    ConversationInfo(
      conversationID: id,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      userID: group ? null : id,
      groupID: group ? id : null,
      showName: name ?? id,
      ex: ex,
      recvMsgOpt: muted ? 2 : 0,
    );

Future<void> _mount(
    WidgetTester tester, _FeedLogic logic, List<ConversationInfo> conversations,
    {required bool dark,
    bool archived = false,
    bool editing = false,
    VoidCallback? onTap}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: Column(
          children: [
            for (final info in conversations)
              ConversationFeedRow(
                logic: logic,
                info: info,
                showDivider: true,
                editing: editing,
                selected: false,
                archivedLayout: archived,
                onTap: onTap ?? () {},
                onLongPress: () {},
              ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    OpenIM.iMManager.userID = 'official-badge-viewer';
  });

  for (final dark in [false, true]) {
    for (final archived in [false, true]) {
      testWidgets(
          'main/archive conversation identities show badges ($dark/$archived)',
          (tester) async {
        final logic = _FeedLogic();
        addTearDown(logic.onDelete.call);
        final conversations = [
          _conversation('99Message', name: 'Announcement display name'),
          _conversation('99Pay'),
          _conversation('official-alias', ex: '{"accountType":"official"}'),
          _conversation('peer', name: 'Ordinary friend'),
          _conversation('99Pay',
              group: true,
              name: 'Group with an official-like ID',
              ex: '{"accountType":"official"}'),
        ];
        await _mount(tester, logic, conversations,
            dark: dark, archived: archived);
        expect(_badges, findsNWidgets(3));
        final labels = tester
            .widgetList<OfficialAccountNameLabel>(
                find.byType(OfficialAccountNameLabel))
            .toList();
        expect(labels.map((label) => label.name),
            conversations.map((conversation) => conversation.showName));
        expect(labels.first.userID, '99Message');
        expect(labels[2].ex, '{"accountType":"official"}');
        expect(labels.last.isSingleChat, isFalse);
        expect(labels.first.style!.fontSize, 16);
        expect(labels.first.style!.fontWeight, FontWeight.w500);
        expect(labels.first.style!.color, AppTokens.textPrimary(dark: dark));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
      'long official names retain the badge before the mute icon in editing',
      (tester) async {
    final logic = _FeedLogic();
    addTearDown(logic.onDelete.call);
    final name = List.filled(30, '官方通知').join();
    var taps = 0;
    await _mount(
        tester, logic, [_conversation('99Message', name: name, muted: true)],
        dark: false, editing: true, onTap: () => taps++);
    expect(_badges, findsOneWidget);
    final badgeRect = tester.getRect(_badges);
    final muteRect = tester.getRect(find.byIcon(Icons.notifications_off));
    expect(badgeRect.width, 16);
    expect(badgeRect.right, lessThanOrEqualTo(muteRect.left));
    expect(badgeRect.left, greaterThan(0));
    await tester.tap(find.byType(OfficialAccountNameLabel));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
