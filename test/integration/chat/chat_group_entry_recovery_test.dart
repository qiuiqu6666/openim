import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/chat/chat_entry_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late EntryTestIM im;
  late List<EntryHistoryCall> history;
  late List<ChatLogic> owners;
  var metadataReads = 0;
  var metadataFails = false;
  var groupName = 'Loaded group';
  var groupFace = 'old-avatar';
  var groupCount = 12;

  ChatLogic open() {
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
        conversationID: 'sg_group',
        groupID: 'group',
        conversationType: ConversationType.superGroup,
        showName: 'Group fallback',
        unreadCount: 0,
        groupAtType: GroupAtType.atNormal,
        latestMsg: Message(
          clientMsgID: 'cached-latest',
          contentType: MessageType.text,
          sendTime: 1,
          status: MessageStatus.succeeded,
          textElem: TextElem(content: 'Cached message'),
        ),
      ),
    };
    final logic = ChatLogic();
    owners.add(logic);
    logic.onInit();
    return logic;
  }

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    ChatHistoryCache.clear();
    ChatHistoryPrefetcher.shared.clear();
    history = [];
    owners = [];
    metadataReads = 0;
    metadataFails = false;
    groupName = 'Loaded group';
    groupFace = 'old-avatar';
    groupCount = 12;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
    Get.put<AppController>(EntryTestApp());
    im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
    Get.put<ConversationLogic>(EntryTestConversation());
    Get.put<CacheController>(EntryTestCache());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      switch (call.method) {
        case 'getAdvancedHistoryMessageList':
        case 'getAdvancedHistoryMessageListReverse':
          final pending = EntryHistoryCall(
              Map<String, dynamic>.from(call.arguments as Map));
          history.add(pending);
          return pending.result.future;
        case 'isJoinGroup':
          return 'true';
        case 'getGroupsInfo':
          metadataReads++;
          if (metadataFails) throw PlatformException(code: 'offline');
          return jsonEncode([
            GroupInfo(
                    groupID: 'group',
                    groupName: groupName,
                    faceURL: groupFace,
                    memberCount: groupCount)
                .toJson(),
          ]);
        case 'getGroupMembersInfo':
          return jsonEncode([
            GroupMembersInfo(
                    groupID: 'group',
                    userID: 'self',
                    roleLevel: GroupRoleLevel.member)
                .toJson(),
          ]);
        case 'getGroupMemberOwnerAndAdmin':
        case 'getBlacklist':
          return '[]';
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    for (final logic in owners) {
      if (!logic.isClosed) logic.onDelete();
    }
    for (final pending in history) {
      pending.complete([]);
    }
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
  });

  testWidgets(
      'pending history cannot block group metadata on entry or re-entry',
      (tester) async {
    final first = open();
    expect(first.memberStr, isEmpty, reason: 'Unknown is not zero members');
    await tester.pump();
    expect(first.historyLoading.value, isTrue);
    expect(first.messageList, isEmpty);
    expect(first.nickname.value, 'Loaded group');
    expect(first.memberCount.value, 12);
    expect(metadataReads, 1);
    first.onDelete();
    final second = open();
    await tester.pump();
    expect(second.historyLoading.value, isTrue);
    expect(second.nickname.value, 'Loaded group');
    expect(second.memberCount.value, 12);
    expect(metadataReads, 2);
    for (final pending in history) {
      pending.complete([]);
    }
    await tester.pump();
    expect(second.historyLoading.value, isFalse);
    expect(metadataReads, 2,
        reason: 'History completion must not reload healthy metadata');
    second.onDelete();
  });

  testWidgets('connection recovery reloads failed metadata while history waits',
      (tester) async {
    metadataFails = true;
    final logic = open();
    await tester.pump();
    expect(logic.nickname.value, 'Group fallback');
    expect(logic.memberStr, isEmpty);
    metadataFails = false;
    im.imSdkStatus(IMSdkStatus.connectionSucceeded);
    await tester.pump();
    expect(logic.historyLoading.value, isTrue);
    expect(logic.nickname.value, 'Loaded group');
    expect(logic.memberCount.value, 12);
    expect(metadataReads, 2);
    logic.onDelete();
    for (final pending in history) {
      pending.complete([]);
    }
    await tester.pump();
  });

  testWidgets('offline profile changes refresh the open chat after sync',
      (tester) async {
    final logic = open();
    await tester.pump();
    expect(logic.nickname.value, 'Loaded group');
    expect(logic.faceUrl.value, 'old-avatar');
    groupName = 'Renamed while offline';
    groupFace = 'new-avatar';
    im.imSdkStatus(IMSdkStatus.connecting);
    im.imSdkStatus(IMSdkStatus.connectionSucceeded);
    await tester.pump();
    expect(logic.nickname.value, 'Loaded group');
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    expect(logic.nickname.value, groupName);
    expect(logic.faceUrl.value, groupFace);
    expect(logic.messageList, isEmpty);
    expect(logic.historyLoading.value, isTrue);
    final reads = metadataReads;
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    expect(metadataReads, reads, reason: 'Duplicate finishes cannot reload');
    im.imSdkStatus(IMSdkStatus.syncStart);
    groupFace = '';
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    expect(logic.faceUrl.value, '', reason: 'Avatar removal must propagate');
    logic.onDelete();
    for (final pending in history) {
      pending.complete([]);
    }
    await tester.pump();
  });

  testWidgets(
      'delayed metadata after message sync updates name count and member identity',
      (tester) async {
    final logic = open();
    await tester.pump();
    im.imSdkStatus(IMSdkStatus.connecting);
    im.imSdkStatus(IMSdkStatus.connectionSucceeded);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    // Native auxiliary metadata has not reached the local database yet.
    expect(logic.nickname.value, 'Loaded group');
    expect(logic.memberCount.value, 12);
    groupName = 'Renamed offline';
    groupCount = 13;
    im.groupMemberAdded(
        GroupMembersInfo(groupID: 'group', userID: 'added', nickname: 'Added'));
    im.groupMemberDeleted(
        GroupMembersInfo(groupID: 'group', userID: 'removed'));
    im.groupMemberInfoChanged(GroupMembersInfo(
        groupID: 'group',
        userID: 'self',
        nickname: 'New self nickname',
        roleLevel: GroupRoleLevel.member));
    im.groupInfoChanged(GroupInfo(
        groupID: 'group', groupName: groupName, memberCount: groupCount));
    await tester.pump();
    expect(logic.nickname.value, groupName);
    expect(logic.memberCount.value, 13);
    expect(logic.groupMembersInfo?.nickname, 'New self nickname');
    expect(logic.memberUpdateInfoMap['added']?.nickname, 'Added');
    expect(logic.memberUpdateInfoMap.containsKey('removed'), isFalse);
    // A subsequent offline removal and rename must also propagate downward.
    im.imSdkStatus(IMSdkStatus.syncStart);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    im.groupInfoChanged(GroupInfo(
        groupID: 'group', groupName: 'Renamed again', memberCount: 11));
    await tester.pump();
    expect(logic.nickname.value, 'Renamed again');
    expect(logic.memberCount.value, 11);
    logic.onDelete();
    for (final pending in history) {
      pending.complete([]);
    }
    await tester.pump();
  });
}
