import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_expiring_content.dart';
import 'package:openim_common/src/widgets/chat/chat_formatted_text.dart';
import 'package:openim_common/src/widgets/chat/chat_structured_message.dart';
import 'package:openim/pages/chat/group_setup/group_manage/group_member_permissions_page.dart';
import 'package:openim/pages/chat/chat_setup/message_retention_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: 'Me');
  });
  Widget host(Widget page, {bool dark = false}) => ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!),
          home: page));
  test('expiration falls back to receipt time and protects summaries', () {
    final message = Message.fromJson({
      'contentType': MessageType.text,
      'textElem': {'content': 'private text'},
      'hasReadTime': DateTime.now()
          .subtract(const Duration(seconds: 10))
          .millisecondsSinceEpoch,
      'attachedInfoElem': {
        'isPrivateChat': true,
        'hasReadTime': 0,
        'burnDuration': 1
      },
    });
    expect(message.hasExpired, isTrue);
    expect(IMUtils.parseMsg(message), isNot(contains('private text')));
  });
  testWidgets('reply preview remains visible and can be cleared',
      (tester) async {
    var cleared = false;
    final controller = TextEditingController(text: 'draft');
    await tester.pumpWidget(host(Scaffold(
        body: ChatInputBox(
      toolbox: const SizedBox(),
      voiceRecordBar: const SizedBox(),
      controller: controller,
      quoteContent: 'Original message',
      onClearQuote: () => cleared = true,
    ))));
    expect(find.text('Original message'), findsOneWidget);
    await tester.tap(find.text('Original message'));
    expect(cleared, isTrue);
    expect(controller.text, 'draft');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  test('extended message summaries and safe emoji URLs', () {
    for (final entry in [
      (
        MessageType.atText,
        {
          'atTextElem': {'text': '@Alice hello'}
        },
        '@Alice hello'
      ),
      (
        MessageType.advancedText,
        {
          'advancedTextElem': {'text': 'formatted'}
        },
        'formatted'
      ),
      (
        MessageType.quote,
        {
          'quoteElem': {'text': 'reply'}
        },
        'reply'
      ),
    ]) {
      expect(
          IMUtils.parseMsg(
              Message.fromJson({'contentType': entry.$1, ...entry.$2})),
          entry.$3);
    }
    expect(
        ChatStructuredMessage.emojiUrl(Message.fromJson({
          'faceElem': {'data': 'file:///secret'}
        })),
        isNull);
    expect(
        ChatStructuredMessage.emojiUrl(Message.fromJson({
          'faceElem': {'data': 'https://example.com/sticker.gif'}
        })),
        'https://example.com/sticker.gif');
  });
  test('rich text renders overlapping ranges and ignores invalid offsets', () {
    final spans = ChatFormattedText.spans(
        'abcdef',
        [
          MessageEntity(type: 'bold', offset: 0, length: 4),
          MessageEntity(type: 'italic', offset: 2, length: 4),
          MessageEntity(type: 'bold', offset: -1, length: 8)
        ],
        const TextStyle());
    expect(spans.map((s) => (s as TextSpan).text).join(), 'abcdef');
    expect((spans[1] as TextSpan).style!.fontWeight, FontWeight.bold);
    expect((spans[1] as TextSpan).style!.fontStyle, FontStyle.italic);
  });
  testWidgets('expired content is masked and timer is disposed',
      (tester) async {
    final message = Message.fromJson({
      'attachedInfoElem': {
        'isPrivateChat': true,
        'hasReadTime': DateTime.now()
            .subtract(const Duration(seconds: 10))
            .millisecondsSinceEpoch,
        'burnDuration': 1
      }
    });
    await tester.pumpWidget(host(Scaffold(
        body: ChatExpiringContent(
            message: message, child: const Text('secret')))));
    expect(find.text('secret'), findsNothing);
    expect(find.text('消息已到期'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final dark in [false, true]) {
    testWidgets('new message types render on narrow screens dark=$dark',
        (tester) async {
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = false);
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entries = [
        {
          'contentType': MessageType.atText,
          'atTextElem': {'text': '@Alice hello'}
        },
        {
          'contentType': MessageType.advancedText,
          'advancedTextElem': {
            'text': 'bold',
            'messageEntityList': [
              {'type': 'bold', 'offset': 0, 'length': 4}
            ]
          }
        },
        {
          'contentType': MessageType.merger,
          'mergeElem': {
            'title': 'History',
            'abstractList': ['A very long description of merged messages'],
            'multiMessage': []
          }
        },
        {
          'contentType': MessageType.location,
          'locationElem': {
            'latitude': 25.0,
            'longitude': 121.5,
            'description': 'A location with a long description'
          }
        },
        {
          'contentType': MessageType.customFace,
          'faceElem': {'index': 3, 'data': ''}
        },
      ];
      await tester.pumpWidget(host(
          Scaffold(
              body: SingleChildScrollView(
                  child: Column(children: [
            for (final entry in entries)
              ChatItemView(
                  message: Message.fromJson({
                    'clientMsgID': '${entry['contentType']}',
                    'sendID': 'me',
                    'sendTime': 123000,
                    'isRead': false,
                    'status': 2,
                    ...entry
                  }),
                  onTapUserProfile: (_) {})
          ]))),
          dark: dark));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(StrRes.unsupportedMessage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
  testWidgets('member role changes remain visible even when SDK cache is stale',
      (tester) async {
    final calls = <MethodCall>[];
    var role = GroupRoleLevel.admin;
    const channel = MethodChannel('flutter_openim_sdk');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'setGroupMemberInfo') {
        return null;
      }
      if (call.method == 'getGroupMemberList' ||
          call.method == 'getGroupMembersInfo')
        return jsonEncode([
          {
            'userID': 'other',
            'groupID': 'g',
            'nickname': 'Alice',
            'roleLevel': role
          }
        ]);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
        host(const GroupMemberPermissionsPage(groupID: 'g', owner: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消管理员'));
    await tester.pumpAndSettle();
    expect(
        calls.any((c) =>
            c.method == 'setGroupMemberInfo' &&
            c.arguments['info']['roleLevel'] == GroupRoleLevel.member),
        isTrue);
    expect(find.text('Alice'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mute and unmute update immediately despite stale SDK cache',
      (tester) async {
    const channel = MethodChannel('flutter_openim_sdk');
    final durations = <int>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'changeGroupMemberMute') {
        durations.add(call.arguments['seconds']);
        return null;
      }
      if (call.method == 'getGroupMemberList' ||
          call.method == 'getGroupMembersInfo') {
        return jsonEncode([
          {
            'userID': 'other',
            'groupID': 'g',
            'nickname': 'Alice',
            'roleLevel': 20,
            'muteEndTime': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600
          }
        ]);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(host(const GroupMemberPermissionsPage(
        groupID: 'g', owner: true, mode: MemberPermissionMode.muted)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解除禁言'));
    await tester.pumpAndSettle();
    expect(find.text('已禁言'), findsNothing);
    expect(durations, [0]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('retention changes go through setConversation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    final calls = <MethodCall>[];
    const channel = MethodChannel('flutter_openim_sdk');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'getMultipleConversation') {
        return jsonEncode([
          {
            'conversationID': 'c',
            'conversationType': 1,
            'unreadCount': 0,
            'isPrivateChat':
                calls.any((call) => call.method == 'setConversation'),
            'burnDuration': 30
          }
        ]);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(host(MessageRetentionPage(
        conversation:
            ConversationInfo(conversationID: 'c', conversationType: 1))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('retention-burn-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 秒').last);
    await tester.pumpAndSettle();
    final request = calls.singleWhere((c) => c.method == 'setConversation');
    expect(request.arguments['req']['isPrivateChat'], true);
    expect(request.arguments['req']['burnDuration'], 30);
    expect(request.arguments['req'].containsKey('isPinned'), false);
  });
}
