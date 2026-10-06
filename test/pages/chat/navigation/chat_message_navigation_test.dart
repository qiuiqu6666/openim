import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/navigation/chat_message_navigation.dart';
import 'package:openim/pages/contacts/add_by_search/add_by_search_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai_assistant/openim/support/ai_openim_test_fixture.dart';

class _Profiles {
  GroupInfo? group;
  bool closed = false;
  bool admin = false;
  bool groupChat = true;
  final opened = <Map<String, dynamic>>[];

  late final navigation = ChatMessageNavigation(
    isClosed: () => closed,
    isGroupChat: () => groupChat,
    isSingleChat: () => !groupChat,
    isAdminOrOwner: () => admin,
    groupID: () => groupChat ? 'group' : null,
    groupInfo: () => group,
  );

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() => dispose(tester));
    await tester.pumpWidget(GetMaterialApp(
      home: const Scaffold(body: Text('Chat')),
      getPages: [
        GetPage<dynamic>(
          name: AppRoutes.userProfilePanel,
          page: () {
            opened.add(Map<String, dynamic>.from(Get.arguments as Map));
            return const Scaffold(body: Text('Profile'));
          },
        ),
      ],
    ));
    await tester.pumpAndSettle();
  }

  void tapAvatar() => navigation.onTapLeftAvatar(Message(
        sendID: 'member',
        senderNickname: 'Member',
        senderFaceUrl: 'member-face',
      ));

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.token = 'test-im-token';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'imToken': 'test-im-token',
      'chatToken': 'test-chat-token',
    }));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      // Profile navigation now resolves ordinary/official SDK metadata before
      // routing. These fixtures all represent ordinary group/chat members.
      if (call.method == 'getUsersInfo') return '[]';
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    OpenIM.iMManager.userID = '';
    OpenIM.iMManager.token = null;
    await DataSp.removeLoginCertificate();
  });

  testWidgets('unknown group permissions wait safely and allow a later click',
      (tester) async {
    final profiles = _Profiles();
    await profiles.mount(tester);
    profiles.tapAvatar();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(profiles.opened, isEmpty);
    expect(find.text('Chat'), findsOneWidget);

    profiles.group = GroupInfo(groupID: 'group', lookMemberInfo: 0);
    profiles.tapAvatar();
    await tester.pumpAndSettle();
    expect(profiles.opened, hasLength(1));
    expect(profiles.opened.single['userID'], 'member');
    expect(profiles.opened.single['groupID'], 'group');
    expect(profiles.opened.single['nickname'], 'Member');
    expect(profiles.opened.single['faceURL'], 'member-face');
  });

  testWidgets('group privacy remains enforced after metadata arrives',
      (tester) async {
    final profiles = _Profiles();
    await profiles.mount(tester);
    profiles.tapAvatar();
    profiles.group = GroupInfo(groupID: 'group', lookMemberInfo: 1);
    profiles.tapAvatar();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(profiles.opened, isEmpty);
  });

  testWidgets('known administrator retains profile access while info loads',
      (tester) async {
    final profiles = _Profiles()..admin = true;
    await profiles.mount(tester);
    profiles.tapAvatar();
    await tester.pumpAndSettle();

    expect(profiles.opened.single['userID'], 'member');
    expect(profiles.opened.single['forceCanAdd'], isFalse);
  });

  testWidgets('shared cards retain their independent add-friend fields',
      (tester) async {
    final profiles = _Profiles();
    await profiles.mount(tester);
    profiles.navigation.viewUserInfo(UserInfo(userID: 'member'),
        isCard: true, inviteCode: 'invite-code');
    await tester.pumpAndSettle();

    expect(profiles.opened.single['forceCanAdd'], isTrue);
    expect(profiles.opened.single['addSource'], FriendAddSource.card);
    expect(profiles.opened.single['friendAddFields'],
        {'inviteCode': 'invite-code'});
  });

  testWidgets('single chat profile access does not depend on group metadata',
      (tester) async {
    final profiles = _Profiles()..groupChat = false;
    await profiles.mount(tester);
    profiles.tapAvatar();
    await tester.pumpAndSettle();

    expect(profiles.opened.single['userID'], 'member');
    expect(profiles.opened.single['offAllWhenDelFriend'], isTrue);
  });

  testWidgets('closed routes do not open profiles even with allowed metadata',
      (tester) async {
    final profiles = _Profiles()
      ..closed = true
      ..group = GroupInfo(groupID: 'group', lookMemberInfo: 0);
    await profiles.mount(tester);
    profiles.tapAvatar();
    await tester.pumpAndSettle();

    expect(profiles.opened, isEmpty);
  });

  testWidgets('chat verification opens an empty public-account search',
      (tester) async {
    final fixture = AiOpenimTestFixture();
    await fixture.initialize();
    addTearDown(fixture.dispose);
    final logic = fixture.open();
    await tester.idle();
    for (final history in fixture.histories) {
      history.complete([]);
    }
    Map<String, dynamic>? arguments;
    AddContactsBySearchLogic? search;
    await tester.pumpWidget(GetMaterialApp(
      home: const Scaffold(body: Text('Chat')),
      getPages: [
        GetPage<dynamic>(
          name: AppRoutes.addContactsBySearch,
          page: () {
            arguments = Map<String, dynamic>.from(Get.arguments as Map);
            search = Get.put(AddContactsBySearchLogic());
            return Scaffold(body: TextField(controller: search!.searchCtrl));
          },
        ),
        GetPage<dynamic>(
          name: AppRoutes.sendVerificationApplication,
          page: () => const Scaffold(body: Text('Unproven verification')),
        ),
      ],
    ));
    final nativeCalls = fixture.nativeCalls.length;
    logic.sendFriendVerification();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.addContactsBySearch);
    expect(arguments, {'searchType': SearchType.user});
    expect(search!.searchKey, isEmpty);
    expect(fixture.nativeCalls, hasLength(nativeCalls));
    expect(find.text('Unproven verification'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
