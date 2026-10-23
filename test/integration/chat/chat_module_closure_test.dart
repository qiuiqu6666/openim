import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/directory/contact_directory_indexer.dart';
import 'package:openim/pages/contacts/directory/contact_directory_snapshot.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/friend_setup/friend_setup_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/editing/conversation_edit_controller.dart';
import 'package:openim/pages/conversation/editing/conversation_edit_actions.dart';
import 'package:openim/pages/chat/composer/chat_composer_controller.dart';
import 'package:openim/pages/chat/receipts/chat_read_receipts.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/services/chat_history_cache.dart';
import '../../support/chat_closure/chat_closure_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late ClosureIM im;
  late List<MethodCall> calls;
  Future<Object?> Function(MethodCall)? handler;

  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    ChatHistoryCache.clear();
    Get.put<AppController>(ClosureApp());
    im = Get.put<IMController>(ClosureIM()) as ClosureIM;
    Get.put<HomeLogic>(ClosureHome());
    calls = [];
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      calls.add(call);
      return handler == null ? null : await handler!(call);
    });
  });

  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
  });

  for (final pin in [true, false]) {
    test('stale list read cannot undo accepted ${pin ? 'pin' : 'mute'}',
        () async {
      final reply = Completer<String>();
      handler = (call) async {
        if (call.method == 'getConversationListSplit') return reply.future;
        if (call.method == 'setConversation') return null;
        throw StateError('Unexpected ${call.method}');
      };
      final info = ConversationInfo(
          conversationID: 'chat',
          userID: 'peer',
          latestMsgSendTime: 1,
          draftTextTime: 0,
          isPinned: false,
          recvMsgOpt: 0);
      final stale = ConversationInfo.fromJson(info.toJson());
      final logic = ConversationLogic();
      addTearDown(logic.onClose);
      logic.list.add(info);
      final loading = logic.getFirstPage();
      await Future<void>.delayed(Duration.zero);
      if (pin) {
        await logic.setPinned(info, true);
      } else {
        await logic.setNotDisturb(info, true);
      }
      expect(
          pin ? logic.list.single.isPinned : logic.list.single.recvMsgOpt == 2,
          isTrue);
      reply.complete(jsonEncode([stale.toJson()]));
      await loading;
      expect(
          pin ? logic.list.single.isPinned : logic.list.single.recvMsgOpt == 2,
          isTrue,
          reason:
              'The older query must not roll back a successful user setting.');
    });
  }

  testWidgets('failed batch deletion retains editing and failed selection',
      (tester) async {
    await tester.pumpWidget(
        GetMaterialApp(builder: EasyLoading.init(), home: const Scaffold()));
    handler = (call) async {
      if (call.method == 'deleteConversationAndDeleteAllMsg') {
        throw PlatformException(code: '500', message: 'Deletion rejected');
      }
      return null;
    };
    final logic = ConversationLogic();
    addTearDown(logic.onClose);
    final info = ConversationInfo(
        conversationID: 'chat',
        userID: 'peer',
        latestMsgSendTime: 1,
        draftTextTime: 0);
    logic.list.add(info);
    final editor = ConversationEditController()
      ..toggleEditing()
      ..toggleSelection('chat');
    addTearDown(editor.dispose);
    final actions = ConversationEditActions(
        logic: logic, editor: editor, isMounted: () => true);
    final operation =
        actions.delete(tester.element(find.byType(Scaffold)), [info]);
    await tester.pumpAndSettle();
    Get.back(result: true);
    await tester.pump();
    await operation;
    await EasyLoading.dismiss(animation: false);
    await tester.pumpAndSettle();
    expect(logic.list, hasLength(1));
    expect(editor.editing, isTrue,
        reason:
            'The production delete action must propagate the rejected SDK result.');
    expect(editor.selectedIds, contains('chat'));
  });

  testWidgets('deleting a friend rejects an already queued conversation event',
      (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            builder: EasyLoading.init(),
            home: const Scaffold(body: Text('Home')))));
    final owner = Get.put<ConversationLogic>(ClosureConversationOwner());
    GetTags.createUserProfileTag();
    addTearDown(GetTags.destroyUserProfileTag);
    Get.put<UserProfilePanelLogic>(ClosureProfile(), tag: GetTags.userProfile);
    final row = ConversationInfo(
        conversationID: 'si_peer_self',
        userID: 'peer',
        conversationType: ConversationType.single,
        latestMsgSendTime: 1000,
        draftTextTime: 0);
    owner.list.add(row);
    handler = (call) async {
      if (call.method == 'deleteFriend') return null;
      if (call.method == 'hideConversation') {
        owner.queueChanges([ConversationInfo.fromJson(row.toJson())]);
        return null;
      }
      throw StateError('Unexpected ${call.method}');
    };
    final settings = FriendSetupLogic();
    ChatHistoryCache.write('self', row.conversationID,
        [Message(clientMsgID: 'retained', seq: 1000)]);
    settings.deleteFromFriendList();
    await tester.pumpAndSettle();
    Get.back(result: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'hideConversation'), hasLength(1));
    expect(calls.where((c) => c.method == 'deleteConversationAndDeleteAllMsg'),
        isEmpty);
    expect(ChatHistoryCache.read('self', row.conversationID).single.clientMsgID,
        'retained');
    await tester.pump(const Duration(milliseconds: 100));
    expect(owner.list, isEmpty,
        reason:
            'Friend deletion must use the same buffer cleanup/tombstone as conversation deletion.');
  });

  testWidgets('blocking filters the conversation and retains local history',
      (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            builder: EasyLoading.init(), home: const Scaffold())));
    final owner = Get.put<ConversationLogic>(ClosureConversationOwner());
    final row = ConversationInfo(
        conversationID: 'si_peer_self',
        userID: 'peer',
        conversationType: ConversationType.single,
        latestMsgSendTime: 1000,
        latestMsg: Message(clientMsgID: 'retained', seq: 1000));
    owner.list.add(row);
    ChatHistoryCache.write('self', row.conversationID, [row.latestMsg!]);
    final profile = UserProfilePanelLogic()
      ..userInfo = UserFullInfo(userID: 'peer', nickname: 'Peer').obs;
    handler = (call) async {
      if (call.method == 'addBlacklist') return null;
      if (call.method == 'hideConversation') {
        owner.queueChanges([ConversationInfo.fromJson(row.toJson())]);
        return null;
      }
      throw StateError('Unexpected ${call.method}');
    };
    final action = profile.setBlacklist(true);
    await tester.pumpAndSettle();
    Get.back(result: true);
    await tester.pumpAndSettle();
    await action;
    await tester.pump(const Duration(seconds: 1));
    expect(profile.userInfo.value.isBlacklist, isTrue);
    expect(owner.list, contains(row));
    expect(owner.allowsSearchConversation(row), isFalse);
    expect(owner.allowsSearchUser('peer'), isFalse);
    expect(calls.map((c) => c.method), contains('addBlacklist'));
    expect(calls.any((c) => c.method == 'hideConversation'), isFalse);
    expect(calls.any((c) => c.method == 'deleteConversationAndDeleteAllMsg'),
        isFalse);
    expect(ChatHistoryCache.read('self', row.conversationID).single.clientMsgID,
        'retained');
  });

  test('failed hide retains conversation and messages; retry can hide it',
      () async {
    final owner = ConversationLogic();
    addTearDown(owner.onClose);
    final row = ConversationInfo(
        conversationID: 'chat',
        userID: 'peer',
        conversationType: ConversationType.single,
        latestMsgSendTime: 1000);
    owner.list.add(row);
    ChatHistoryCache.write('self', 'chat', [Message(clientMsgID: 'kept')]);
    var failing = true;
    handler = (call) async {
      if (call.method != 'hideConversation') {
        throw StateError('Unexpected ${call.method}');
      }
      if (failing) throw PlatformException(code: '500');
      return null;
    };
    await expectLater(
        owner.hidePeerConversation('peer'), throwsA(isA<PlatformException>()));
    expect(owner.list.single.conversationID, 'chat');
    failing = false;
    await owner.hidePeerConversation('peer');
    expect(owner.list, isEmpty);
    expect(ChatHistoryCache.read('self', 'chat').single.clientMsgID, 'kept');
  });

  test('hiding a stranger without a persisted conversation is a no-op',
      () async {
    final owner = ConversationLogic();
    addTearDown(owner.onClose);
    handler = (call) async {
      if (call.method == 'getOneConversation') {
        return jsonEncode(ConversationInfo(
                conversationID: 'si_peer_self',
                userID: 'peer',
                conversationType: ConversationType.single,
                latestMsgSendTime: 0)
            .toJson());
      }
      throw StateError('Unexpected ${call.method}');
    };
    await owner.hidePeerConversation('peer');
    expect(calls.map((call) => call.method), ['getOneConversation']);
    expect(owner.list, isEmpty);
  });

  testWidgets('unblocking does not remove or recreate a conversation',
      (tester) async {
    await tester.pumpWidget(
        GetMaterialApp(builder: EasyLoading.init(), home: const Scaffold()));
    final owner = Get.put<ConversationLogic>(ClosureConversationOwner());
    final profile = UserProfilePanelLogic()
      ..userInfo =
          UserFullInfo(userID: 'peer', nickname: 'Peer', isBlacklist: true).obs;
    handler = (call) async {
      if (call.method == 'removeBlacklist') return null;
      throw StateError('Unexpected ${call.method}');
    };
    final action = profile.setBlacklist(false);
    await tester.pumpAndSettle();
    await action;
    expect(profile.userInfo.value.isBlacklist, isFalse);
    expect(owner.list, isEmpty);
    expect(calls.map((call) => call.method), ['removeBlacklist']);
  });

  test('initial friend load failure can be retried by directory consumers',
      () async {
    var fetches = 0;
    var offline = true;
    final logic = Get.put(ContactsLogic(
      fetchFriendsPage: (_, __) async {
        fetches++;
        if (offline) throw StateError('offline');
        return [FriendInfo(userID: 'peer', nickname: 'Peer')];
      },
      directoryIndexer: ContactDirectoryIndexer(
          worker: (names) async => buildContactNameIndex(names)),
    ));
    await logic.loadFriends();
    expect(logic.friendsLoading.value, isFalse);
    offline = false;
    final directory = await loadContactDirectorySnapshot();
    expect(directory.map((f) => f.userID), contains('peer'),
        reason:
            'The retry path must reload after the initial failure; fetches=$fetches');
  });

  test('main contacts owner reacts to blacklist changes', () async {
    var blocked = false;
    final logic = Get.put(ContactsLogic(
      fetchFriendsPage: (_, __) async =>
          blocked ? [] : [FriendInfo(userID: 'peer', nickname: 'Peer')],
      directoryIndexer: ContactDirectoryIndexer(
          worker: (names) async => buildContactNameIndex(names)),
    ));
    await logic.loadFriends();
    expect(logic.friends, hasLength(1));
    blocked = true;
    im.blacklistAdded(BlacklistInfo(userID: 'peer'));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(logic.friends, isEmpty,
        reason:
            'filterBlack=true must remain true after a live blacklist event.');
  });

  test('playing an older voice must not clear unseen newer messages', () async {
    final voice = Message(
        clientMsgID: 'voice',
        sendID: 'peer',
        seq: 1,
        contentType: MessageType.voice,
        isRead: false);
    final unseen = Message(
        clientMsgID: 'unseen',
        sendID: 'peer',
        seq: 2,
        contentType: MessageType.text,
        isRead: false);
    final messages = [voice, unseen].obs;
    final receipts = ChatReadReceipts(
      messageList: messages,
      conversation: () => ConversationInfo(
          conversationID: 'chat',
          userID: 'peer',
          latestMsg: unseen,
          unreadCount: 2),
      isClosed: () => false,
    );
    addTearDown(receipts.close);
    await receipts.markVisibleMessages(['voice']);
    expect(calls, isEmpty);
    await receipts.markRead(voice);
    expect(calls.where((c) => c.method == 'markConversationMessageAsRead'),
        isEmpty,
        reason: 'Only voice was painted, not the latest message.');
  });

  test('reply target survives a draft save and restore', () async {
    var saved = '';
    ChatComposerController composer() => ChatComposerController(
          conversationID: () => 'chat',
          currentUserID: () => 'self',
          isGroupChat: () => false,
          groupInfo: () => null,
          sendingMuted: () => false,
          sendMessage: (_) async {},
          persistDraft: (_, draft) async {
            saved = draft;
          },
          selectMembers: (_, __) async => null,
          closeToolbox: () {},
          scrollBottom: () {},
          onTypingChanged: (_) {},
          showError: (_) {},
        );
    final first = composer()..initialize(null);
    first.replyToMessage(Message(
        clientMsgID: 'quoted',
        sendID: 'peer',
        contentType: MessageType.text,
        textElem: TextElem(content: 'Original')));
    first.inputCtrl.text = 'Reply';
    await first.saveDraft();
    final snapshot = saved;
    first.dispose();
    final second = composer()..initialize(snapshot);
    addTearDown(second.dispose);
    expect(second.inputCtrl.text, 'Reply');
    expect(second.quotedMessage.value?.clientMsgID, 'quoted');
  });

  test('group profile consumes self removal events', () async {
    Get.put<ConversationLogic>(ClosureConversations());
    handler = (call) async => switch (call.method) {
          'isJoinGroup' || 'isJoinedGroup' => 'true',
          'getGroupsInfo' || 'getGroupMemberList' => jsonEncode([]),
          _ => throw StateError('Unexpected ${call.method}'),
        };
    Get.routing.args = {
      'groupID': 'g',
      'joinGroupMethod': JoinGroupMethod.search
    };
    final profile = GroupProfilePanelLogic()..onInit();
    addTearDown(() => profile.onDelete());
    await Future<void>.delayed(Duration.zero);
    expect(profile.isJoined.value, isTrue);
    im.memberDeletedSubject.add(GroupMembersInfo(groupID: 'g', userID: 'self'));
    im.joinedGroupDeletedSubject.add(GroupInfo(groupID: 'g'));
    await Future<void>.delayed(Duration.zero);
    expect(profile.isJoined.value, isFalse,
        reason: 'The profile must switch from Enter to Apply after removal.');
  });

  test('old membership query cannot undo a newer joined event', () async {
    Get.put<ConversationLogic>(ClosureConversations());
    final queried = Completer<String>();
    handler = (call) async => switch (call.method) {
          'isJoinGroup' || 'isJoinedGroup' => queried.future,
          'getGroupsInfo' || 'getGroupMemberList' => jsonEncode([]),
          _ => throw StateError('Unexpected ${call.method}'),
        };
    Get.routing.args = {
      'groupID': 'g',
      'joinGroupMethod': JoinGroupMethod.search
    };
    final profile = GroupProfilePanelLogic()..onInit();
    addTearDown(() => profile.onDelete());
    im.joinedGroupAddedSubject.add(GroupInfo(groupID: 'g'));
    await Future<void>.delayed(Duration.zero);
    expect(profile.isJoined.value, isTrue);
    queried.complete('false');
    await Future<void>.delayed(Duration.zero);
    expect(profile.isJoined.value, isTrue);
  });
}
