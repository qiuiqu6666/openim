import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/global_search/global_search_logic.dart';
import 'package:openim/pages/global_search/identity/global_search_add_actions.dart';
import 'package:openim/pages/contacts/add_by_search/add_by_search_logic.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';

class _Directory extends ContactSearchSource {
  final usersSearched = <String>[];
  final groupsSearched = <String>[];
  final friendsSearched = <String>[];
  @override
  Future<List<FriendInfo>> friends(String keyword) async {
    friendsSearched.add(keyword);
    return [FriendInfo(userID: 'friend-1', nickname: 'Friend')];
  }

  @override
  Future<List<UserFullInfo>?> users(String keyword, int page,
      {int? way}) async {
    usersSearched.add(keyword);
    return [];
  }

  @override
  Future<List<GroupInfo>> groups(String keyword) async {
    groupsSearched.add(keyword);
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);
  test('SDK searches IDs, public UID supplements friends without duplicates',
      () async {
    const channel = MethodChannel('flutter_openim_sdk');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return jsonEncode(call.method == 'searchFriends'
          ? [
              {'userID': 'friend-1', 'nickname': 'Friend', 'relationship': 1}
            ]
          : [
              {'groupID': 'group-123', 'groupName': 'Group'}
            ]);
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final directory = _Directory();
    final source = GlobalSearchSource(directory: directory);
    expect((await source.friends('@abcdefgh12')).single.userID, 'friend-1');
    expect(directory.friendsSearched, ['@abcdefgh12']);
    expect(directory.usersSearched, isEmpty);
    expect((calls.first.arguments as Map)['searchParam']['isSearchUserID'],
        isTrue);
    expect((await source.groups('group-123')).single.groupID, 'group-123');
    expect((calls.last.arguments as Map)['searchParam']['isSearchGroupID'],
        isTrue);
    final conversations = [
      ConversationInfo(conversationID: 'a', userID: 'user-123'),
      ConversationInfo(conversationID: 'b', groupID: 'group-123')
    ];
    expect(GlobalSearchSource.matchConversations(conversations, 'user-123'),
        [conversations.first]);
    expect(GlobalSearchSource.matchConversations(conversations, 'group-123'),
        [conversations.last]);
  });

  for (final type in SearchType.values) {
    testWidgets(
        '$type handoff prefills UID and automatically queries the matching add page once',
        (tester) async {
      OpenIM.iMManager.userID = 'self';
      final directory = _Directory();
      final logic = GlobalSearchLogic();
      logic.query.value = 'target-123';
      late AddContactsBySearchLogic destination;
      await tester.pumpWidget(GetMaterialApp(
        locale: const Locale('zh', 'CN'),
        home: Scaffold(body: GlobalSearchAddActions(logic: logic)),
        getPages: [
          GetPage(
              name: AppRoutes.addContactsBySearch,
              binding: BindingsBuilder(() {
                destination =
                    Get.put(AddContactsBySearchLogic(source: directory));
              }),
              page: () => const Scaffold(body: Text('Destination')))
        ],
      ));
      await tester.tap(find.byKey(ValueKey('global-search-add-${type.name}')));
      await tester.pumpAndSettle();
      expect(destination.searchCtrl.text, 'target-123');
      expect(destination.searchType, type);
      expect(
          type == SearchType.user
              ? directory.usersSearched
              : directory.groupsSearched,
          ['target-123']);
      expect(
          type == SearchType.user
              ? directory.groupsSearched
              : directory.usersSearched,
          isEmpty);
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(logic.query.value, 'target-123');
      await tester.pumpWidget(const SizedBox());
      logic.onClose();
    });
  }

  testWidgets('exact known IDs do not offer corresponding add action',
      (tester) async {
    final logic = GlobalSearchLogic();
    logic.query.value = '123';
    logic.contactsList.add(FriendInfo(userID: '123'));
    logic.groupList.add(GroupInfo(groupID: '123'));
    await tester.pumpWidget(GetMaterialApp(
        home: Scaffold(body: GlobalSearchAddActions(logic: logic))));
    expect(find.byType(ListTile), findsNothing);
    await tester.pumpWidget(const SizedBox());
    logic.onClose();
  });
}
