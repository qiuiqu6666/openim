import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/pages/official_account/models/official_account.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

ConversationInfo _conversation(String id, {String? ex}) => ConversationInfo(
    conversationID: 'si_${id}_self',
    conversationType: ConversationType.single,
    userID: id,
    ex: ex);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;
  var profileTagCreated = false;

  Future<void> identity(String id, String token) async {
    OpenIM.iMManager.userID = id;
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': id, 'imToken': token, 'chatToken': ''}));
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: AppRoutes.home,
      defaultTransition: Transition.noTransition,
      getPages: [
        for (final route in [
          AppRoutes.home,
          AppRoutes.chat,
          AppRoutes.aiAssistantChat,
          AppRoutes.officialAccountChat,
          AppRoutes.userProfilePanel,
          AppRoutes.personalInfo,
          AppRoutes.friendSetup,
          AppRoutes.chatSetup,
        ])
          GetPage(name: route, page: () => Scaffold(body: Text(route))),
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
    profileTagCreated = false;
    handler = (call) async {
      if (call.method == 'getUsersInfo') return '[]';
      if (call.method == 'getOneConversation') {
        return jsonEncode(
            _conversation(call.arguments['sourceID'] as String).toJson());
      }
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

  tearDown(() {
    ChatHistoryPrefetcher.shared.clear();
    while (GetTags.chat != null) {
      GetTags.destroyChatTag();
    }
    if (profileTagCreated) GetTags.destroyUserProfileTag();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final id in ['99Message', '99Pay']) {
    testWidgets(
        '$id opens its dedicated SDK conversation without a profile read',
        (tester) async {
      await mount(tester);
      final conversation = _conversation(id);
      final search = Message(clientMsgID: 'found-message');
      final navigation = AppNavigator.startChat(
          conversationInfo: conversation, searchMessage: search);
      await tester.pumpAndSettle();
      expect(Get.currentRoute, AppRoutes.officialAccountChat);
      expect(Get.arguments['conversationInfo'], same(conversation));
      expect(Get.arguments['searchMessage'], same(search));
      final account = Get.arguments['officialAccount'] as OfficialAccount;
      expect(account.userID, id);
      expect(account.isPay, id == '99Pay');
      expect(AppRoutes.isConversationRoute(Get.currentRoute), isTrue);
      expect(calls.where((call) => call.method == 'getUsersInfo'), isEmpty);
      Get.back();
      await tester.pumpAndSettle();
      await navigation;
      ChatHistoryPrefetcher.shared.clear();
    });

    testWidgets('$id profile entry opens the official conversation',
        (tester) async {
      await mount(tester);
      final navigation = AppNavigator.startUserProfilePane(userID: id);
      await tester.pumpAndSettle();
      expect(Get.currentRoute, AppRoutes.officialAccountChat);
      expect(() => GetTags.userProfile, throwsStateError);
      final request =
          calls.singleWhere((call) => call.method == 'getOneConversation');
      expect(request.arguments['sourceID'], id);
      expect(request.arguments['sessionType'], ConversationType.single);
      expect(calls.where((call) => call.method == 'getUsersInfo'), isEmpty);
      Get.back();
      await tester.pumpAndSettle();
      await navigation;
      ChatHistoryPrefetcher.shared.clear();
    });
  }

  testWidgets(
      'SDK profile role also prevents profile and friend settings entry',
      (tester) async {
    await mount(tester);
    final defaultHandler = handler;
    handler = (call) async => call.method == 'getUsersInfo'
        ? jsonEncode([
            {
              'userID': 'notice',
              'ex': '{"accountType":"official","officialRole":"pay"}'
            }
          ])
        : await defaultHandler(call);
    for (final navigate in [
      () => AppNavigator.startUserProfilePane(userID: 'notice'),
      () => AppNavigator.startPersonalInfo(userID: 'notice'),
      () => AppNavigator.startFriendSetup(userID: 'notice'),
    ]) {
      final navigation = navigate();
      await tester.pumpAndSettle();
      expect(Get.currentRoute, AppRoutes.officialAccountChat);
      expect(
          (Get.arguments['officialAccount'] as OfficialAccount).isPay, isTrue);
      expect(() => GetTags.userProfile, throwsStateError);
      Get.back();
      await tester.pumpAndSettle();
      await navigation;
      ChatHistoryPrefetcher.shared.clear();
    }
    expect(calls.where((call) => call.method == 'getUsersInfo'), hasLength(3));
  });

  testWidgets('ordinary profiles survive SDK metadata lookup failure',
      (tester) async {
    await mount(tester);
    handler = (call) async => throw StateError('Offline');
    final navigation = AppNavigator.startUserProfilePane(userID: 'ordinary');
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.userProfilePanel);
    profileTagCreated = true;
    expect(Get.arguments['userID'], 'ordinary');
    Get.back();
    await tester.pumpAndSettle();
    await navigation;
  });

  testWidgets('self profile bypasses metadata lookup', (tester) async {
    await mount(tester);
    final navigation = AppNavigator.startUserProfilePane(userID: 'self');
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.userProfilePanel);
    profileTagCreated = true;
    expect(calls, isEmpty);
    Get.back();
    await tester.pumpAndSettle();
    await navigation;
  });

  testWidgets('notification chats reject a direct personal-chat settings entry',
      (tester) async {
    await mount(tester);
    for (final conversation in [
      _conversation('99Message'),
      _conversation('99Pay'),
      _conversation('notice',
          ex: '{"accountType":"official","officialRole":"message"}'),
    ]) {
      expect(
          AppNavigator.startChatSetup(conversationInfo: conversation), isNull);
      await tester.pumpAndSettle();
      expect(Get.currentRoute, AppRoutes.home);
      expect(calls, isEmpty);
    }
    final ordinary = _conversation('ordinary');
    final navigation = AppNavigator.startChatSetup(conversationInfo: ordinary);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.chatSetup);
    expect(Get.arguments['conversationInfo'], same(ordinary));
    Get.back();
    await tester.pumpAndSettle();
    await navigation;
  });

  testWidgets('ordinary directory metadata avoids another SDK profile lookup',
      (tester) async {
    await mount(tester);
    final navigation =
        AppNavigator.startUserProfilePane(userID: 'ordinary', ex: '');
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.userProfilePanel);
    profileTagCreated = true;
    expect(calls, isEmpty);
    Get.back();
    await tester.pumpAndSettle();
    await navigation;
  });

  testWidgets('late official profile cannot navigate after a token change',
      (tester) async {
    await mount(tester);
    final profile = Completer<Object?>();
    handler = (call) => profile.future;
    final navigation = AppNavigator.startUserProfilePane(userID: 'notice');
    await tester.pump();
    await identity('self', 'rotated-im-token');
    profile.complete(jsonEncode([
      {
        'userID': 'notice',
        'ex': '{"accountType":"official","officialRole":"pay"}'
      }
    ]));
    await tester.pumpAndSettle();
    expect(await navigation, isNull);
    expect(Get.currentRoute, AppRoutes.home);
    expect(() => GetTags.userProfile, throwsStateError);
    expect(GetTags.chat, isNull);
    expect(calls.where((call) => call.method == 'getOneConversation'), isEmpty);
  });

  testWidgets(
      'profile replacement keeps the existing route replacement behavior',
      (tester) async {
    await mount(tester);
    unawaited(Get.toNamed(AppRoutes.personalInfo));
    await tester.pumpAndSettle();
    final navigation = AppNavigator.startUserProfilePane(
        userID: '99Message', offAndToNamed: true);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.officialAccountChat);
    expect(Get.previousRoute, AppRoutes.home);
    Get.back();
    await tester.pumpAndSettle();
    await navigation;
    ChatHistoryPrefetcher.shared.clear();
  });

  testWidgets('late official conversation cannot navigate after account change',
      (tester) async {
    await mount(tester);
    final conversation = Completer<Object?>();
    handler = (call) => conversation.future;
    final navigation = AppNavigator.startUserProfilePane(userID: '99Pay');
    await tester.pump();
    await identity('next-account', 'next-token');
    conversation.complete(jsonEncode(_conversation('99Pay').toJson()));
    await tester.pumpAndSettle();
    expect(await navigation, isNull);
    expect(Get.currentRoute, AppRoutes.home);
    expect(GetTags.chat, isNull);
  });
}
