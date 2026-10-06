import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

ConversationInfo _conversation(String userID, {String? draft}) =>
    ConversationInfo(
        conversationID: 'si_${userID}_self',
        conversationType: ConversationType.single,
        userID: userID,
        draftText: draft);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;

  Future<void> identity(String userID, String imToken) async {
    OpenIM.iMManager.userID = userID;
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': userID, 'imToken': imToken, 'chatToken': ''}));
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: AppRoutes.home,
      defaultTransition: Transition.noTransition,
      getPages: [
        GetPage(
            name: AppRoutes.home,
            page: () => const Scaffold(body: Text('home'))),
        GetPage(name: '/mine', page: () => const Scaffold(body: Text('mine'))),
        GetPage(
            name: AppRoutes.chat,
            page: () => const Scaffold(body: Text('ordinary chat'))),
        GetPage(
            name: AppRoutes.aiAssistantChat,
            page: () => const Scaffold(body: Text('official chat'))),
      ],
    ));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await identity('self', 'im-token');
    calls = [];
    handler = (call) async {
      if (call.method == 'getOneConversation') {
        return jsonEncode(
            _conversation('assistant', draft: 'stored draft').toJson());
      }
      if (call.method == 'getUsersInfo') return '[]';
      if (call.method == 'getAdvancedHistoryMessageList') {
        return jsonEncode({'messageList': [], 'isEnd': true, 'errCode': 0});
      }
      return null;
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() async {
    ChatHistoryPrefetcher.shared.clear();
    // The deliberately minimal route fixtures do not instantiate ChatLogic.
    while (GetTags.chat != null) {
      GetTags.destroyChatTag();
    }
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('assistant routes preserve SDK conversation, draft and search',
      (tester) async {
    await mount(tester);
    final conversation = _conversation('assistant');
    final search = Message(clientMsgID: 'target-message');
    final navigation = AppNavigator.startChat(
        conversationInfo: conversation,
        draftText: 'draft',
        searchMessage: search);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.aiAssistantChat);
    expect(find.text('official chat'), findsOneWidget);
    expect(Get.arguments['conversationInfo'], same(conversation));
    expect(Get.arguments['draftText'], 'draft');
    expect(Get.arguments['searchMessage'], same(search));
    expect(calls.where((call) => call.method == 'getUsersInfo'), isEmpty);
    expect(
        calls.where((call) => call.method == 'getAdvancedHistoryMessageList'),
        hasLength(1));
    expect(AppRoutes.isConversationRoute(Get.currentRoute), isTrue);
    Get.back();
    await tester.pumpAndSettle();
    await navigation;
    ChatHistoryPrefetcher.shared.clear();
  });

  testWidgets('mine entry uses assistant session 1 and returns to mine',
      (tester) async {
    await mount(tester);
    unawaited(Get.toNamed('/mine'));
    await tester.pumpAndSettle();
    final navigation = AppNavigator.startAiAssistant();
    await tester.pumpAndSettle();
    expect(DataSp.chatToken, isEmpty);
    expect(Get.currentRoute, AppRoutes.aiAssistantChat);
    expect(Get.previousRoute, '/mine');
    final request =
        calls.singleWhere((call) => call.method == 'getOneConversation');
    expect(request.arguments['sourceID'], 'assistant');
    expect(request.arguments['sessionType'], ConversationType.single);
    expect(Get.arguments['draftText'], 'stored draft');
    expect((Get.arguments['conversationInfo'] as ConversationInfo).showName,
        'AI助理');
    Get.back();
    await tester.pumpAndSettle();
    await navigation;
    expect(find.text('mine'), findsOneWidget);
    ChatHistoryPrefetcher.shared.clear();
  });

  testWidgets('official SDK metadata routes a contact to the dedicated page',
      (tester) async {
    await mount(tester);
    final defaultHandler = handler;
    handler = (call) async {
      if (call.method == 'getUsersInfo') {
        return jsonEncode([
          {'userID': 'official-user', 'ex': '{"accountType":"official"}'}
        ]);
      }
      return defaultHandler(call);
    };
    final navigation = AppNavigator.startChat(
        conversationInfo: _conversation('official-user'));
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.aiAssistantChat);
    expect(
        calls
            .singleWhere((call) => call.method == 'getUsersInfo')
            .arguments['userIDList'],
        ['official-user']);
    Get.back();
    await tester.pumpAndSettle();
    await navigation;
    ChatHistoryPrefetcher.shared.clear();
  });

  testWidgets('ordinary SDK conversations keep the ordinary chat route',
      (tester) async {
    await mount(tester);
    final navigation =
        AppNavigator.startChat(conversationInfo: _conversation('peer'));
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.chat);
    expect(find.text('ordinary chat'), findsOneWidget);
    Get.back();
    await tester.pumpAndSettle();
    await navigation;
    ChatHistoryPrefetcher.shared.clear();
  });

  testWidgets('a late account profile cannot open a route after logout',
      (tester) async {
    await mount(tester);
    final profiles = Completer<Object?>();
    handler = (call) =>
        call.method == 'getUsersInfo' ? profiles.future : Future.value(null);
    final navigation =
        AppNavigator.startChat(conversationInfo: _conversation('peer'));
    await tester.pump();
    await identity('new-account', 'new-im-token');
    profiles.complete(jsonEncode([
      {'userID': 'peer', 'ex': '{"accountType":"official"}'}
    ]));
    await tester.pumpAndSettle();
    expect(await navigation, isNull);
    expect(Get.currentRoute, AppRoutes.home);
    expect(GetTags.chat, isNull);
    expect(
        calls.where((call) => call.method == 'getAdvancedHistoryMessageList'),
        isEmpty);
  });
}
