import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_info.dart';
import 'package:openim/pages/chat/group_setup/group_manage/group_friend_protection_store.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim/pages/contacts/user_profile_panel/adding/profile_friend_add_account_resolver.dart';
import 'package:openim/pages/contacts/user_profile_panel/identity/group_profile_account_state.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _group = 'group-account-test';
const _peer = 'im_original-peer';

class _App extends GetxController implements AppController {
  @override
  final clientConfigMap = <String, dynamic>{}.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  final userInfo = UserFullInfo(userID: 'im_me', nickname: 'Me').obs;

  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations extends GetxController implements ConversationLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Run the production subscriptions without unrelated profile/network loading.
class _Profile extends UserProfilePanelLogic {
  _Profile(
    GroupProfileMembersLoader load,
    _Protection protection, {
    required ProfileFriendAddAccountResolver friendAddAccountResolver,
    required void Function(String) friendAddNotify,
  }) : super(
          groupMembersLoader: load,
          friendProtectionFactory: (_) => protection,
          friendAddAccountResolver: friendAddAccountResolver,
          friendAddNotify: friendAddNotify,
        );
  @override
  void onReady() {}
  void loadInitialMetadata() => super.onReady();
  @override
  Future<void> loadCommonGroupCount() async {}
}

class _AccountSearch extends ContactSearchSource {
  final calls = <(String, int)>[];
  final replies = <Completer<List<UserFullInfo>?>>[];

  @override
  Future<List<UserFullInfo>?> users(String keyword, int page, {int? way}) {
    calls.add((keyword, page));
    final reply = Completer<List<UserFullInfo>?>();
    replies.add(reply);
    return reply.future;
  }
}

class _Protection extends GroupFriendProtectionStore {
  _Protection() : super(_group, notify: (_) {});
  @override
  Future<void> refresh() async {
    ready.value = true;
  }
}

GroupMemberIdentityInfo _member({String userID = _peer, String? account}) =>
    GroupMemberIdentityInfo.fromJson({
      'groupID': _group,
      'userID': userID,
      if (account != null) 'account': account,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _IM im;
  late _Profile logic;
  late List<Completer<List<GroupMemberIdentityInfo>>> replies;
  late List<List<String>> requestedIDs;
  late _Protection protection;
  late _AccountSearch accountSearch;
  late List<String> messages;
  late List<Map<String, dynamic>> applications;
  const sdk = MethodChannel('flutter_openim_sdk');

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'im_me',
      'imToken': 'im-token',
      'chatToken': 'chat-token',
    }));
    await DataSp.putServerConfig({'authUrl': 'http://account-search.test'});
    OpenIM.iMManager.userID = 'im_me';
    Get.put<AppController>(_App(), permanent: true);
    im = Get.put<IMController>(_IM(), permanent: true) as _IM;
    Get.put<ConversationLogic>(_Conversations(), permanent: true);
    replies = [];
    requestedIDs = [];
    protection = _Protection();
    accountSearch = _AccountSearch();
    messages = [];
    applications = [];
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
    for (final reply in replies) {
      if (!reply.isCompleted) reply.complete([]);
    }
    for (final reply in accountSearch.replies) {
      if (!reply.isCompleted) reply.complete([]);
    }
  });

  Future<void> open(WidgetTester tester,
      {bool groupMember = true, String userID = _peer}) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const Scaffold()),
        GetPage(
          name: AppRoutes.addContactsBySearch,
          page: () => const Scaffold(body: Text('account-search')),
        ),
        GetPage(
          name: AppRoutes.sendVerificationApplication,
          page: () {
            applications.add(Map<String, dynamic>.from(Get.arguments as Map));
            return const Scaffold(body: Text('friend-application'));
          },
        ),
        GetPage(
          name: '/profile',
          binding: BindingsBuilder(() {
            logic = Get.put(_Profile((group, ids) {
              expect(group, _group);
              requestedIDs.add(ids);
              final reply = Completer<List<GroupMemberIdentityInfo>>();
              replies.add(reply);
              return reply.future;
            }, protection,
                friendAddAccountResolver:
                    ProfileFriendAddAccountResolver(source: accountSearch),
                friendAddNotify: messages.add));
          }),
          page: () => Scaffold(body: Obx(() => Text(logic.displayedUserID))),
        ),
      ],
    ));
    unawaited(Get.toNamed('/profile', arguments: {
      if (groupMember) 'groupID': _group,
      'userID': userID,
      'nickname': 'Member',
    }));
    await tester.pumpAndSettle();
  }

  Future<void> openChat(WidgetTester tester,
      {String? account = '@ab12cd34ef'}) async {
    await open(tester, groupMember: false);
    logic.userInfo.update((user) {
      user?.account = account;
      user?.allowAddFriend = 1;
      user?.isFriendship = false;
    });
  }

  List<UserFullInfo> verifiedPeer() => [
        UserFullInfo(userID: _peer, account: '@ab12cd34ef'),
      ];

  Future<void> disclose(WidgetTester tester) async {
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    replies.last.complete([_member(account: '@ab12cd34ef')]);
    await tester.pump();
    expect(logic.displayedUserID, '@ab12cd34ef');
    expect(requestedIDs.last, [_peer]);
    expect(logic.userInfo.value.userID, _peer);
  }

  testWidgets('single chat verifies its account before opening the application',
      (tester) async {
    await openChat(tester);
    expect(logic.addSource, FriendAddSource.chat);
    expect(logic.hasFriendAddEntry, isFalse);
    expect(logic.canPrepareFriendAdd, isTrue);
    logic.addFriend();
    expect(accountSearch.calls, [('@ab12cd34ef', 1)]);
    expect(logic.preparingFriendAdd.value, isTrue);
    expect(Get.currentRoute, '/profile');
    accountSearch.replies.single.complete(verifiedPeer());
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.sendVerificationApplication);
    expect(find.text('friend-application'), findsOneWidget);
    expect(find.text('account-search'), findsNothing);
    expect(applications, hasLength(1));
    expect(applications.single, containsPair('userID', _peer));
    expect(applications.single,
        containsPair('addSource', FriendAddSource.account));
    expect(applications.single,
        containsPair('friendAddFields', {'account': '@ab12cd34ef'}));
    expect(applications.single, containsPair('targetAccount', '@ab12cd34ef'));
    expect(applications.single, containsPair('selfNickname', 'Me'));
    expect(messages, isEmpty);
    expect(logic.userInfo.value.userID, _peer);
    expect(requestedIDs, isEmpty);
  });

  testWidgets('duplicate clicks stay blocked until the application returns',
      (tester) async {
    await openChat(tester);
    logic.addFriend();
    logic.addFriend();
    expect(accountSearch.calls, hasLength(1));
    accountSearch.replies.single.complete(verifiedPeer());
    await tester.pumpAndSettle();
    expect(logic.preparingFriendAdd.value, isTrue);
    logic.addFriend();
    await tester.pump();
    expect(accountSearch.calls, hasLength(1));
    expect(applications, hasLength(1));
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, '/profile');
    expect(logic.preparingFriendAdd.value, isFalse);
  });

  testWidgets('a missing public account cannot be guessed from the target ID',
      (tester) async {
    await openChat(tester, account: null);
    // Even a nickname shaped like an account is not a public-account grant.
    logic.userInfo.update((user) => user?.nickname = 'ab12cd34ef');
    expect(logic.canPrepareFriendAdd, isFalse);
    logic.addFriend();
    await tester.pumpAndSettle();
    expect(accountSearch.calls, isEmpty);
    expect(applications, isEmpty);
    expect(Get.currentRoute, '/profile');
    expect(messages, hasLength(1));
    expect(logic.preparingFriendAdd.value, isFalse);
    expect(logic.userInfo.value.userID, _peer);
  });

  for (final failure in ['different target', 'transport error']) {
    testWidgets('$failure stays on profile and allows a new attempt',
        (tester) async {
      await openChat(tester);
      logic.addFriend();
      if (failure == 'different target') {
        accountSearch.replies.single.complete([
          UserFullInfo(userID: 'im_other-peer', account: '@ab12cd34ef'),
        ]);
      } else {
        accountSearch.replies.single
            .completeError(StateError('account search unavailable'));
      }
      await tester.pumpAndSettle();
      expect(applications, isEmpty);
      expect(Get.currentRoute, '/profile');
      expect(messages, hasLength(1));
      expect(logic.preparingFriendAdd.value, isFalse);
      expect(logic.userInfo.value.userID, _peer);
      logic.addFriend();
      expect(accountSearch.calls, hasLength(2));
      accountSearch.replies.last.complete(verifiedPeer());
      await tester.pumpAndSettle();
      expect(applications, hasLength(1));
      expect(applications.single, containsPair('userID', _peer));
      expect(messages, hasLength(1));
    });
  }

  Future<void> invalidatePending(String change) async {
    switch (change) {
      case 'owner':
      case 'chat token':
        await DataSp.putLoginCertificate(LoginCertificate.fromJson({
          'userID': change == 'owner' ? 'im_next' : 'im_me',
          'imToken': 'im-token',
          'chatToken':
              change == 'chat token' ? 'next-chat-token' : 'chat-token',
        }));
      case 'SDK owner':
        OpenIM.iMManager.userID = 'im_next';
      case 'server':
        await DataSp.putServerConfig({'authUrl': 'http://other-server.test'});
      case 'target':
        logic.userInfo.update((user) => user?.userID = 'im_other-peer');
      case 'public account':
        logic.userInfo.update((user) => user?.account = '@zz98yx76wv');
      case 'friendship':
        logic.userInfo.update((user) => user?.isFriendship = true);
      case 'blacklist':
        logic.userInfo.update((user) => user?.isBlacklist = true);
      case 'close':
        await Get.delete<_Profile>(force: true);
    }
  }

  for (final change in [
    'owner',
    'SDK owner',
    'chat token',
    'server',
    'target',
    'public account',
    'friendship',
    'blacklist',
    'close',
  ]) {
    testWidgets('$change change discards a late successful account lookup',
        (tester) async {
      await openChat(tester);
      logic.addFriend();
      expect(accountSearch.calls, hasLength(1));
      await invalidatePending(change);
      accountSearch.replies.single.complete(verifiedPeer());
      await tester.pumpAndSettle();
      expect(applications, isEmpty);
      expect(Get.currentRoute, '/profile');
      expect(messages, isEmpty);
    });
  }

  for (final change in ['owner', 'close', 'public account']) {
    testWidgets('$change change suppresses a late lookup error',
        (tester) async {
      await openChat(tester);
      logic.addFriend();
      await invalidatePending(change);
      accountSearch.replies.single
          .completeError(StateError('account search unavailable'));
      await tester.pumpAndSettle();
      expect(applications, isEmpty);
      expect(messages, isEmpty);
    });
  }

  testWidgets('a covering page prevents a late lookup from redirecting it',
      (tester) async {
    await openChat(tester);
    logic.addFriend();
    unawaited(Get.toNamed(AppRoutes.addContactsBySearch));
    await tester.pumpAndSettle();
    accountSearch.replies.single.complete(verifiedPeer());
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AppRoutes.addContactsBySearch);
    expect(find.text('account-search'), findsOneWidget);
    expect(applications, isEmpty);
    expect(messages, isEmpty);
    expect(logic.preparingFriendAdd.value, isFalse);
  });

  testWidgets('group account is independent of general profile and friendship',
      (tester) async {
    await open(tester);
    logic.userInfo.update((user) => user?.account = '@cached1234');
    expect(logic.displayedUserID, isEmpty);
    await disclose(tester);
    expect(logic.userInfo.value.account, '@cached1234');
    logic.userInfo.update((user) => user?.isFriendship = true);
    await tester.pump();
    expect(logic.displayedUserID, '@ab12cd34ef');
  });

  testWidgets(
      'group friend hides a general account absent from the group reply',
      (tester) async {
    await open(tester);
    logic.userInfo.update((user) {
      user?.account = '@cached1234';
      user?.isFriendship = true;
    });
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    replies.single.complete([_member()]);
    await tester.pump();
    expect(logic.isFriendship, isTrue);
    expect(logic.userInfo.value.account, '@cached1234');
    expect(logic.displayedUserID, isEmpty);
  });

  testWidgets('group self uses only its raw group account', (tester) async {
    await open(tester, userID: 'im_me');
    logic.userInfo.update((user) => user?.account = '@cached1234');
    expect(logic.isMyself, isTrue);
    expect(logic.displayedUserID, isEmpty);
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(requestedIDs.single, ['im_me']);
    replies.single.complete([
      _member(userID: 'im_me', account: '@ab12cd34ef'),
    ]);
    await tester.pump();
    expect(logic.displayedUserID, '@ab12cd34ef');
    expect(logic.userInfo.value.account, '@cached1234');
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    replies.last.complete([_member(userID: 'im_me')]);
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
  });

  for (final self in [false, true]) {
    testWidgets('non-group account keeps its existing source (self: $self)',
        (tester) async {
      await open(tester, groupMember: false, userID: self ? 'im_me' : _peer);
      logic.userInfo.update((user) {
        user?.account = '@cached1234';
        user?.isFriendship = !self;
      });
      im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
      await tester.pump();
      expect(logic.displayedUserID, '@cached1234');
      expect(replies, isEmpty);
    });
  }

  testWidgets('replayed self info does not duplicate the first group lookup',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (_) async {
      throw PlatformException(code: 'optional-profile-unavailable');
    });
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await open(tester);
    expect(replies, isEmpty);
    logic.loadInitialMetadata();
    await tester.pump();
    expect(replies, hasLength(1));
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await tester.pump();
    expect(replies, hasLength(2));
  });

  testWidgets('reopening the same member rechecks unchanged group metadata',
      (tester) async {
    final groupReplies = <Completer<String>>[];
    final memberReplies = <Completer<String>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      if (call.method == 'getGroupsInfo') {
        final reply = Completer<String>();
        groupReplies.add(reply);
        return reply.future;
      }
      if (call.method == 'getGroupMembersInfo') {
        final reply = Completer<String>();
        memberReplies.add(reply);
        return reply.future;
      }
      throw PlatformException(code: 'optional-profile-unavailable');
    });
    void completeMetadata(int index) {
      groupReplies[index].complete(jsonEncode([
        {'groupID': _group},
      ]));
      memberReplies[index].complete(jsonEncode([
        {
          'groupID': _group,
          'userID': _peer,
          'roleLevel': GroupRoleLevel.member
        },
        {
          'groupID': _group,
          'userID': 'im_me',
          'roleLevel': GroupRoleLevel.member
        },
      ]));
    }

    await open(tester);
    logic.loadInitialMetadata();
    await tester.pump();
    expect(replies, isNotEmpty);
    final firstRequestCount = replies.length;
    for (final reply in replies) {
      reply.complete([_member(account: '@ab12cd34ef')]);
    }
    await tester.pump();
    expect(logic.displayedUserID, '@ab12cd34ef');
    completeMetadata(0);
    await tester.pump();
    expect(logic.groupInfo?.groupID, _group);
    expect(logic.displayedUserID, '@ab12cd34ef');
    final first = logic;
    Get.back();
    await tester.pumpAndSettle();
    expect(first.isClosed, isTrue);

    await open(tester);
    expect(logic, isNot(same(first)));
    logic.loadInitialMetadata();
    await tester.pump();
    expect(replies.length, greaterThan(firstRequestCount));
    expect(requestedIDs, everyElement([_peer]));
    expect(logic.displayedUserID, isEmpty);
    for (final reply in replies.skip(firstRequestCount)) {
      reply.complete([_member()]);
    }
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
    completeMetadata(1);
    await tester.pump();
    expect(logic.groupInfo?.groupID, _group);
    expect(logic.displayedUserID, isEmpty);
  });

  testWidgets('current self info rechecks disclosure and rejects older replies',
      (tester) async {
    await open(tester);
    await disclose(tester);
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
    expect(replies, hasLength(2));
    final older = replies.last;
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await tester.pump();
    expect(replies, hasLength(3));
    older.complete([_member(account: '@ab12cd34ef')]);
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
    replies.last.complete([_member()]);
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await tester.pump();
    replies.last.complete([_member(account: '@ab12cd34ef')]);
    await tester.pump();
    expect(logic.displayedUserID, '@ab12cd34ef');
    expect(logic.iHaveAdminOrOwnerPermission.value, isFalse);
  });

  testWidgets('another user or missing self identity does not recheck account',
      (tester) async {
    await open(tester);
    await disclose(tester);
    im.selfInfoUpdatedSubject.add(UserInfo(userID: _peer));
    im.selfInfoUpdatedSubject.add(UserInfo());
    await tester.pump();
    expect(replies, hasLength(1));
    expect(logic.displayedUserID, '@ab12cd34ef');
  });

  testWidgets('self refresh rejects a reply from an earlier session',
      (tester) async {
    await open(tester);
    await disclose(tester);
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await tester.pump();
    final pending = replies.last;
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'im_other-session',
      'imToken': 'other-im-token',
      'chatToken': 'other-chat-token',
    }));
    OpenIM.iMManager.userID = 'im_other-session';
    pending.complete([_member(account: '@ab12cd34ef')]);
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
    expect(replies, hasLength(2));
  });

  testWidgets('closing profile cancels the self info listener', (tester) async {
    await open(tester);
    await disclose(tester);
    expect(im.selfInfoUpdatedSubject.hasListener, isTrue);
    await Get.delete<_Profile>(force: true);
    expect(im.selfInfoUpdatedSubject.hasListener, isFalse);
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await tester.pump();
    expect(replies, hasLength(1));
    expect(logic.displayedUserID, isEmpty);
  });

  testWidgets(
      'self info restarts metadata and rejects older permission replies',
      (tester) async {
    final groupReplies = <Completer<String>>[];
    final memberReplies = <Completer<String>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      if (call.method == 'getGroupsInfo') {
        final reply = Completer<String>();
        groupReplies.add(reply);
        return reply.future;
      }
      if (call.method == 'getGroupMembersInfo') {
        final reply = Completer<String>();
        memberReplies.add(reply);
        return reply.future;
      }
      throw PlatformException(code: 'optional-profile-unavailable');
    });
    await open(tester);
    logic.loadInitialMetadata();
    await tester.pump();
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await tester.pump();
    expect(replies, hasLength(2));
    expect(groupReplies, hasLength(2));
    expect(memberReplies, hasLength(2));
    groupReplies.first.complete(jsonEncode([
      {'groupID': _group, 'lookMemberInfo': 0},
    ]));
    memberReplies.first.complete(jsonEncode([
      {'groupID': _group, 'userID': 'im_me', 'roleLevel': GroupRoleLevel.owner},
    ]));
    await tester.pump();
    expect(logic.groupInfo, isNull);
    expect(logic.iHaveAdminOrOwnerPermission.value, isFalse);
    expect(replies, hasLength(2));
    groupReplies.last.complete(jsonEncode([
      {'groupID': _group, 'lookMemberInfo': 1},
    ]));
    memberReplies.last.complete(jsonEncode([
      {
        'groupID': _group,
        'userID': _peer,
        'roleLevel': GroupRoleLevel.member,
        'joinTime': 123,
        'nickname': 'Current member',
      },
      {'groupID': _group, 'userID': 'im_me', 'roleLevel': GroupRoleLevel.admin},
    ]));
    await tester.pump();
    expect(logic.groupInfo?.lookMemberInfo, 1);
    expect(logic.iHaveAdminOrOwnerPermission.value, isTrue);
    expect(logic.iAmOwner.value, isFalse);
    expect(logic.joinGroupTime.value, 123);
    expect(logic.groupUserNickname.value, 'Current member');
    replies.last.complete([_member()]);
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
  });

  testWidgets('friend protection and member visibility remain separate',
      (tester) async {
    await open(tester);
    protection.protect.value = true;
    await disclose(tester);
    expect(logic.notAllowAddGroupMemberFriend.value, isTrue);
    expect(logic.displayedUserID, '@ab12cd34ef');
    im.groupInfoUpdatedSubject.add(GroupInfo(groupID: _group)
      ..lookMemberInfo = 1
      ..applyMemberFriend = 1);
    await tester.pump();
    protection.protect.value = false;
    await tester.pump();
    expect(logic.notAllowAddGroupMemberFriend.value, isFalse);
    expect(logic.notAllowLookGroupMemberProfiles.value, isTrue);
  });

  testWidgets('privacy update clears account without a member version change',
      (tester) async {
    await open(tester);
    await disclose(tester);
    im.groupInfoUpdatedSubject
        .add(GroupInfo(groupID: _group)..lookMemberInfo = 1);
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
    expect(replies, hasLength(2));
    replies.last.complete([_member()]);
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
    expect(logic.userInfo.value.userID, _peer);
  });

  testWidgets('self downgrade discards a pending older disclosure',
      (tester) async {
    await open(tester);
    await disclose(tester);
    im.memberInfoChangedSubject.add(GroupMembersInfo(
      groupID: _group,
      userID: 'im_me',
      roleLevel: GroupRoleLevel.admin,
    ));
    await tester.pump();
    final older = replies.last;
    im.memberInfoChangedSubject.add(GroupMembersInfo(
      groupID: _group,
      userID: 'im_me',
      roleLevel: GroupRoleLevel.member,
    ));
    await tester.pump();
    older.complete([_member(account: '@ab12cd34ef')]);
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
    replies.last.complete([_member()]);
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
  });

  for (final target in ['im_me', _peer]) {
    testWidgets('removing $target closes group account disclosure',
        (tester) async {
      await open(tester);
      await disclose(tester);
      im.memberDeletedSubject
          .add(GroupMembersInfo(groupID: _group, userID: target));
      await tester.pump();
      expect(logic.displayedUserID, isEmpty);
      logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
      im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
      expect(logic.hasActiveGroupMemberContext, isFalse);
      await tester.pump();
      expect(replies, hasLength(1));
    });
  }

  testWidgets('leaving group closes account disclosure and later requests',
      (tester) async {
    await open(tester);
    await disclose(tester);
    im.joinedGroupDeletedSubject.add(GroupInfo(groupID: _group));
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
    expect(logic.hasActiveGroupMemberContext, isFalse);
    im.groupInfoUpdatedSubject
        .add(GroupInfo(groupID: _group)..lookMemberInfo = 0);
    im.selfInfoUpdatedSubject.add(UserInfo(userID: 'im_me'));
    await tester.pump();
    expect(replies, hasLength(1));
  });

  testWidgets('foreground resume rechecks account when SDK versions stay equal',
      (tester) async {
    await open(tester);
    await disclose(tester);
    logic.didChangeAppLifecycleState(AppLifecycleState.paused);
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(logic.displayedUserID, isEmpty);
    expect(replies, hasLength(2));
    replies.last.complete([_member()]);
    await tester.pump();
    expect(logic.displayedUserID, isEmpty);
  });

  testWidgets('older initial SDK metadata cannot undo a role and privacy event',
      (tester) async {
    final oldGroup = Completer<String>();
    final oldMembers = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      return switch (call.method) {
        'getGroupsInfo' => oldGroup.future,
        'getGroupMembersInfo' => oldMembers.future,
        _ => throw PlatformException(code: 'optional-profile-unavailable'),
      };
    });
    await open(tester);
    logic.loadInitialMetadata();
    await tester.pump();
    im.groupInfoUpdatedSubject
        .add(GroupInfo(groupID: _group)..lookMemberInfo = 1);
    im.memberInfoChangedSubject.add(GroupMembersInfo(
      groupID: _group,
      userID: 'im_me',
      roleLevel: GroupRoleLevel.member,
    ));
    await tester.pump();
    oldGroup.complete(jsonEncode([
      {'groupID': _group, 'lookMemberInfo': 0},
    ]));
    oldMembers.complete(jsonEncode([
      {'groupID': _group, 'userID': _peer, 'roleLevel': GroupRoleLevel.member},
      {'groupID': _group, 'userID': 'im_me', 'roleLevel': GroupRoleLevel.owner},
    ]));
    await tester.pump();
    expect(logic.groupInfo?.lookMemberInfo, 1);
    expect(logic.iHaveAdminOrOwnerPermission.value, isFalse);
    expect(logic.iAmOwner.value, isFalse);
    expect(logic.notAllowLookGroupMemberProfiles.value, isTrue);
    expect(logic.userInfo.value.userID, _peer);
  });

  testWidgets('privacy-only event restarts the cancelled initial role query',
      (tester) async {
    final oldGroup = Completer<String>();
    final memberReplies = <Completer<String>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      if (call.method == 'getGroupsInfo') return oldGroup.future;
      if (call.method == 'getGroupMembersInfo') {
        final reply = Completer<String>();
        memberReplies.add(reply);
        return reply.future;
      }
      throw PlatformException(code: 'optional-profile-unavailable');
    });
    await open(tester);
    logic.loadInitialMetadata();
    await tester.pump();
    im.groupInfoUpdatedSubject
        .add(GroupInfo(groupID: _group)..lookMemberInfo = 1);
    await tester.pump();
    expect(memberReplies, hasLength(2));
    memberReplies.last.complete(jsonEncode([
      {'groupID': _group, 'userID': _peer, 'roleLevel': GroupRoleLevel.member},
      {'groupID': _group, 'userID': 'im_me', 'roleLevel': GroupRoleLevel.admin},
    ]));
    memberReplies.first.complete(jsonEncode([
      {'groupID': _group, 'userID': 'im_me', 'roleLevel': GroupRoleLevel.owner},
    ]));
    oldGroup.complete(jsonEncode([
      {'groupID': _group, 'lookMemberInfo': 0},
    ]));
    await tester.pump();
    expect(logic.iHaveAdminOrOwnerPermission.value, isTrue);
    expect(logic.iAmOwner.value, isFalse);
    expect(logic.groupInfo?.lookMemberInfo, 1);
  });

  testWidgets('foreground refresh restores current SDK role and group rules',
      (tester) async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      methods.add(call.method);
      return switch (call.method) {
        'getGroupsInfo' => jsonEncode([
            {'groupID': _group, 'lookMemberInfo': 1},
          ]),
        'getGroupMembersInfo' => jsonEncode([
            {
              'groupID': _group,
              'userID': _peer,
              'roleLevel': GroupRoleLevel.member
            },
            {
              'groupID': _group,
              'userID': 'im_me',
              'roleLevel': GroupRoleLevel.admin
            },
          ]),
        _ => throw PlatformException(code: 'optional-profile-unavailable'),
      };
    });
    await open(tester);
    protection.protect.value = true;
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(methods, containsAll(['getGroupsInfo', 'getGroupMembersInfo']));
    expect(logic.groupInfo?.lookMemberInfo, 1);
    expect(logic.iHaveAdminOrOwnerPermission.value, isTrue);
    expect(logic.notAllowAddGroupMemberFriend.value, isFalse);
  });
}
