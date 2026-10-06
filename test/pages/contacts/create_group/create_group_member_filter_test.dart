import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/create_group/create_group_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';

class _Conversations extends GetxController implements ConversationLogic {
  final openedUserIDs = <String?>[];
  final openedNames = <String?>[];

  @override
  void toChat({
    bool offUntilHome = true,
    String? userID,
    String? groupID,
    String? nickname,
    String? faceURL,
    int? sessionType,
    ConversationInfo? conversationInfo,
    Message? searchMessage,
  }) {
    openedUserIDs.add(userID);
    openedNames.add(nickname);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<CreateGroupLogic> _openCreation(
  WidgetTester tester, {
  required List<UserInfo> defaultChecked,
  required List<UserInfo> checked,
}) async {
  late CreateGroupLogic logic;
  await tester.pumpWidget(GetMaterialApp(
    defaultTransition: Transition.noTransition,
    home: const Scaffold(body: Text('origin')),
    getPages: [
      GetPage(
        name: '/create-group-filter',
        binding: BindingsBuilder(() {
          logic = Get.put(CreateGroupLogic());
        }),
        page: () => const Scaffold(body: Text('create group')),
      ),
    ],
  ));
  unawaited(Get.toNamed<void>('/create-group-filter', arguments: {
    'defaultCheckedList': defaultChecked,
    'checkedList': checked,
  }));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    Get.reset();
  });
  return logic;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdkChannel = MethodChannel('flutter_openim_sdk');
  late _Conversations conversations;
  late List<MethodCall> sdkCalls;

  setUp(() {
    Get.reset();
    Get.testMode = true;
    conversations = _Conversations();
    Get.put<ConversationLogic>(conversations, permanent: true);
    sdkCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, (call) async {
      sdkCalls.add(call);
      throw StateError('This member-filter test must not call the SDK.');
    });
  });

  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, null);
  });

  testWidgets(
      'route preselection excludes official accounts and keeps namesakes',
      (tester) async {
    final defaultChecked = [
      UserInfo(userID: 'self', nickname: '我'),
      UserInfo(userID: 'assistant', nickname: 'AI助理'),
      UserInfo(
          userID: 'another-assistant',
          nickname: '官方助手',
          ex: '{"accountType":"official","officialRole":"assistant"}'),
      UserInfo(userID: '99Pay'),
    ];
    final checked = [
      UserInfo(userID: 'assistant', nickname: 'AI助理'),
      UserInfo(userID: 'ordinary', nickname: 'AI助理'),
      UserInfo(userID: 'friend', nickname: '好友'),
    ];
    final logic = await _openCreation(tester,
        defaultChecked: defaultChecked, checked: checked);

    expect(logic.defaultCheckedList.map((member) => member.userID), ['self']);
    expect(logic.checkedList.map((member) => member.userID),
        ['ordinary', 'friend']);
    expect(logic.allList.map((member) => member.userID),
        ['self', 'ordinary', 'friend']);
    expect(logic.groupName, '我、AI助理、好友');
    expect(defaultChecked, hasLength(4));
    expect(checked, hasLength(3));
    expect(conversations.openedUserIDs, isEmpty);
    expect(sdkCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submission removes official accounts added after initialization',
      (tester) async {
    final ordinary = UserInfo(userID: 'ordinary', nickname: 'AI助理');
    final logic =
        await _openCreation(tester, defaultChecked: [], checked: [ordinary]);
    final blocked = [
      UserInfo(userID: 'assistant', nickname: 'AI助理'),
      UserInfo(
          userID: 'official-without-role',
          nickname: '官方助手',
          ex: '{"accountType":"official"}'),
    ];
    logic.defaultCheckedList.addAll(blocked);
    logic.checkedList.addAll(blocked);
    logic.allList.addAll(blocked);

    await logic.completeCreation();

    expect(logic.defaultCheckedList, isEmpty);
    expect(logic.checkedList.map((member) => member.userID), ['ordinary']);
    expect(logic.allList.map((member) => member.userID), ['ordinary']);
    expect(conversations.openedUserIDs, ['ordinary']);
    expect(conversations.openedNames, ['AI助理']);
    expect(sdkCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
