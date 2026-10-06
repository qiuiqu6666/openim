import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_setup/message_context_page.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Message _message(String id, int minute) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'self',
      'recvID': 'peer',
      'senderNickname': 'Self',
      'seq': minute,
      'sendTime': DateTime(2026, 10, 4, 8, minute).millisecondsSinceEpoch,
      'status': MessageStatus.succeeded,
      'textElem': {'content': id},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late List<MethodCall> calls;
  late String findResultField;
  late List<Message> found;
  final target = _message('selected-date-target', 20);

  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    calls = [];
    findResultField = 'findResultItems';
    found = [target];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'findMessageList':
          return jsonEncode({
            'totalCount': found.length,
            findResultField: [
              {
                'conversationID': 'chat',
                'messageList':
                    found.map((message) => message.toJson()).toList(),
              },
            ],
          });
        case 'getAdvancedHistoryMessageList':
          return jsonEncode({
            'isEnd': true,
            'messageList': List.generate(
                20, (index) => _message('older-$index', index).toJson()),
          });
        case 'getAdvancedHistoryMessageListReverse':
          return jsonEncode({
            'isEnd': true,
            'messageList': [target.toJson(), _message('newer', 21).toJson()],
          });
        default:
          throw PlatformException(
              code: 'unexpected-call', message: call.method);
      }
    });
  });

  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(WidgetTester tester,
      {DateTime? date, Brightness brightness = Brightness.light}) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MessageContextPage(
          conversationID: 'chat',
          target: target,
          date: date,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder targetRow() => find.byWidgetPredicate((widget) =>
      widget is ChatItemView &&
      widget.message.clientMsgID == target.clientMsgID);

  for (final brightness in Brightness.values) {
    testWidgets(
        'SDK findResultItems locates chosen day and loads adjacent messages in ${brightness.name}',
        (tester) async {
      final date = DateTime(2026, 10, 4);
      await mount(tester, date: date, brightness: brightness);

      expect(calls.map((call) => call.method),
          ['findMessageList', 'getAdvancedHistoryMessageList']);
      final findArgs = calls.first.arguments as Map;
      expect((findArgs['searchParams'] as List).single, {
        'conversationID': 'chat',
        'clientMsgIDList': [target.clientMsgID],
      });
      expect((calls.last.arguments as Map)['startClientMsgID'],
          target.clientMsgID);
      expect(find.byType(ChatItemView), findsNWidgets(21));
      expect(targetRow(), findsOneWidget);

      final context = tester.element(find.byType(MessageContextPage));
      expect(find.text(MaterialLocalizations.of(context).formatFullDate(date)),
          findsOneWidget);
      expect(tester.widget<ChatItemView>(targetRow()).highlightColor,
          Theme.of(context).colorScheme.primary.withValues(alpha: .10));
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final row = tester.getRect(targetRow());
      expect(row.top, greaterThanOrEqualTo(viewport.top));
      expect(row.bottom, lessThanOrEqualTo(viewport.bottom));

      final newer = find.text('sdkSearchNewer');
      await tester.ensureVisible(newer);
      await tester.tap(newer);
      await tester.pumpAndSettle();
      expect(calls.last.method, 'getAdvancedHistoryMessageListReverse');
      expect((calls.last.arguments as Map)['startClientMsgID'],
          target.clientMsgID);
      expect(find.byType(ChatItemView), findsNWidgets(22));
      expect(targetRow(), findsOneWidget,
          reason: 'Overlapping context pages must not duplicate the anchor.');
      expect(find.text('sdkSearchNewer'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('legacy searchResultItems response keeps ordinary context title',
      (tester) async {
    findResultField = 'searchResultItems';
    await mount(tester);
    expect(targetRow(), findsOneWidget);
    expect(find.text('sdkSearchContext'), findsOneWidget);
    expect(calls.map((call) => call.method),
        ['findMessageList', 'getAdvancedHistoryMessageList']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a removed target shows empty history without paging an anchor',
      (tester) async {
    found = [];
    await mount(tester);
    expect(find.text('chatSearchEmpty'), findsOneWidget);
    expect(find.byType(ChatItemView), findsNothing);
    expect(calls.map((call) => call.method), ['findMessageList']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
