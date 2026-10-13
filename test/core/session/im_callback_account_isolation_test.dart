import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/legacy_cleanup/legacy_service_conversation_cleanup.dart';
import 'package:openim/pages/group_features/data/group_feature_runtime.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Retain the actual SDK callback subjects across account changes, as the app's
// global IM controller does. Native login itself is covered by lifecycle tests.
class _IM extends GetxController with IMCallback implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    close();
    super.onClose();
  }
}

class _Home extends GetxController implements HomeLogic {
  @override
  final conversationsAtFirstPage = <ConversationInfo>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationInfo _row(String id, {String? preview}) => ConversationInfo(
      conversationID: id,
      conversationType: ConversationType.single,
      userID: 'peer-$id',
      showName: id,
      latestMsgSendTime: 100,
      draftTextTime: 0,
      latestMsg: Message(
          clientMsgID: 'message-$id',
          sendTime: 100,
          textElem: TextElem(content: preview ?? id)),
    );

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 35));

Future<void> _cancelAll(List<StreamSubscription<dynamic>> subscriptions) async {
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}

List<StreamSubscription<dynamic>> _listenGroupEvents(
        _IM im, List<String> received) =>
    [
      im.groupInfoUpdatedSubject
          .listen((info) => received.add('owner:${info.ownerUserID}')),
      im.memberAddedSubject.listen((member) =>
          received.add('added:${member.userID}:${member.roleLevel}')),
      im.memberDeletedSubject
          .listen((member) => received.add('removed:${member.userID}')),
      im.memberInfoChangedSubject.listen((member) =>
          received.add('role:${member.userID}:${member.roleLevel}')),
      im.joinedGroupAddedSubject
          .listen((info) => received.add('joined:${info.groupID}')),
      im.joinedGroupDeletedSubject
          .listen((info) => received.add('left:${info.groupID}')),
    ];

void _emitGroupEvents(_IM im, String owner) {
  final group =
      GroupInfo.fromJson({'groupID': 'shared-group', 'ownerUserID': owner});
  final member = GroupMembersInfo.fromJson(
      {'groupID': 'shared-group', 'userID': owner, 'roleLevel': 100});
  im.groupInfoChanged(group);
  im.groupMemberAdded(member);
  im.groupMemberDeleted(member);
  im.groupMemberInfoChanged(member);
  im.joinedGroupAdded(group);
  im.joinedGroupDeleted(group);
}

List<StreamSubscription<dynamic>> _listenFriendEvents(
        _IM im, List<String> received) =>
    [
      im.friendAddSubject
          .listen((friend) => received.add('added:${friend.userID}')),
      im.friendDelSubject
          .listen((friend) => received.add('removed:${friend.userID}')),
    ];

void _emitFriendEvents(_IM im, String owner) {
  im.friendAdded(FriendInfo.fromJson({'userID': '$owner-friend'}));
  im.friendDeleted(FriendInfo.fromJson({'userID': '$owner-deleted-friend'}));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _IM im;
  late List<ConversationInfo> snapshot;
  late List<ConversationLogic> openPages;
  late List<StreamSubscription<dynamic>> subscriptions;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Get.testMode = true;
    OpenIM.iMManager.userID = 'account-A';
    Get.put<AppController>(_App());
    im = _IM();
    Get.put<IMController>(im);
    Get.put<HomeLogic>(_Home());
    snapshot = [];
    openPages = [];
    subscriptions = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      expect(call.method, 'getConversationListSplit');
      return jsonEncode(snapshot.map((row) => row.toJson()).toList());
    });
  });

  tearDown(() async {
    for (final page in openPages) {
      page.onClose();
    }
    await _cancelAll(subscriptions);
    GroupFeatureRuntime.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
    OpenIM.iMManager.userID = '';
  });

  Future<ConversationLogic> openPage(
      String owner, List<ConversationInfo> currentSnapshot) async {
    OpenIM.iMManager.userID = owner;
    snapshot = currentSnapshot;
    final page = ConversationLogic(
        legacyCleanup: LegacyServiceConversationCleanup(session: () => null));
    openPages.add(page);
    page.onInit();
    await _settle();
    return page;
  }

  void closePage(ConversationLogic page) {
    page.onClose();
    openPages.remove(page);
  }

  test('initial sync survives connection callbacks and does not cross accounts', () async {
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({'userID':'A','imToken':'im-A','chatToken':'chat-A'}));
    im.imSdkStatus(IMSdkStatus.syncStart, reInstall: true);
    im.imSdkStatus(IMSdkStatus.connectionSucceeded);
    expect(im.initialSyncState?.reInstall, isTrue);
    expect(im.initialSyncState?.progress, 0);
    im.imSdkStatus(IMSdkStatus.syncProgress, progress: 4);
    expect(im.initialSyncState?.progress, 4);
    expect((await im.imSdkStatusSubject.first).reInstall, isTrue);
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({'userID':'B','imToken':'im-B','chatToken':'chat-B'}));
    expect(im.initialSyncState, isNull);
    im.imSdkStatus(IMSdkStatus.syncStart, reInstall: true);
    im.imSdkStatus(IMSdkStatus.syncFailed);
    expect(im.initialSyncState, isNull);
  });

  test('A to B to A never merges a previous account callback into the new feed',
      () async {
    final firstA = await openPage('account-A', [_row('A-snapshot')]);
    im.newConversation([_row('A-live')]);
    im.conversationChanged([_row('A-snapshot', preview: 'A-private-preview')]);
    await _settle();
    expect(firstA.list.map((row) => row.conversationID).toSet(),
        {'A-snapshot', 'A-live'});
    expect(
        firstA.list
            .singleWhere((row) => row.conversationID == 'A-snapshot')
            .latestMsg
            ?.textElem
            ?.content,
        'A-private-preview');
    closePage(firstA);

    final pageB = await openPage('account-B', [_row('B-snapshot')]);
    expect(pageB.list.map((row) => row.conversationID), ['B-snapshot']);
    im.newConversation([_row('B-live')]);
    im.conversationChanged([_row('B-snapshot', preview: 'B-private-preview')]);
    await _settle();
    expect(pageB.list.map((row) => row.conversationID).toSet(),
        {'B-snapshot', 'B-live'});
    expect(
        pageB.list
            .singleWhere((row) => row.conversationID == 'B-snapshot')
            .latestMsg
            ?.textElem
            ?.content,
        'B-private-preview');
    closePage(pageB);

    final secondA = await openPage('account-A', [_row('A-fresh-snapshot')]);
    expect(secondA.list.map((row) => row.conversationID), ['A-fresh-snapshot']);
    im.newConversation([_row('A-new-live')]);
    await _settle();
    expect(secondA.list.map((row) => row.conversationID).toSet(),
        {'A-fresh-snapshot', 'A-new-live'});
  });

  test('reopening the same account uses its snapshot instead of stale deltas',
      () async {
    final first = await openPage('account-A', [_row('shared-peer')]);
    im.newConversation([_row('stale-live-only')]);
    im.conversationChanged([_row('shared-peer', preview: 'old-preview')]);
    await _settle();
    expect(first.list, hasLength(2));
    closePage(first);

    final reopened = await openPage(
        'account-A', [_row('shared-peer', preview: 'current-preview')]);
    expect(reopened.list.map((row) => row.conversationID), ['shared-peer']);
    expect(
        reopened.list.single.latestMsg?.textElem?.content, 'current-preview');
    im.newConversation([_row('new-live-only')]);
    im.conversationChanged([_row('shared-peer', preview: 'new-live-preview')]);
    await _settle();
    expect(reopened.list.map((row) => row.conversationID).toSet(),
        {'shared-peer', 'new-live-only'});
    expect(
        reopened.list
            .singleWhere((row) => row.conversationID == 'shared-peer')
            .latestMsg
            ?.textElem
            ?.content,
        'new-live-preview');
  });

  test('same-group old exit and member roles are not replayed after switching',
      () async {
    final firstA = <String>[];
    final firstSubscriptions = _listenGroupEvents(im, firstA);
    subscriptions.addAll(firstSubscriptions);
    _emitGroupEvents(im, 'account-A');
    await _settle();
    expect(firstA, hasLength(6));
    await _cancelAll(firstSubscriptions);
    subscriptions.removeWhere(firstSubscriptions.contains);

    OpenIM.iMManager.userID = 'account-B';
    final pageB = <String>[];
    final secondSubscriptions = _listenGroupEvents(im, pageB);
    subscriptions.addAll(secondSubscriptions);
    await _settle();
    expect(pageB, isEmpty);
    _emitGroupEvents(im, 'account-B');
    await _settle();
    expect(pageB, [
      'owner:account-B',
      'added:account-B:100',
      'removed:account-B',
      'role:account-B:100',
      'joined:shared-group',
      'left:shared-group',
    ]);
    await _cancelAll(secondSubscriptions);
    subscriptions.removeWhere(secondSubscriptions.contains);

    OpenIM.iMManager.userID = 'account-A';
    final secondA = <String>[];
    subscriptions.addAll(_listenGroupEvents(im, secondA));
    await _settle();
    expect(secondA, isEmpty);
    _emitGroupEvents(im, 'account-A');
    await _settle();
    expect(secondA, hasLength(6));
    expect(secondA.first, 'owner:account-A');
  });

  test(
      'old friend additions and deletions cannot enter the replacement account',
      () async {
    final firstA = <String>[];
    final firstSubscriptions = _listenFriendEvents(im, firstA);
    subscriptions.addAll(firstSubscriptions);
    _emitFriendEvents(im, 'account-A');
    await _settle();
    expect(
        firstA, ['added:account-A-friend', 'removed:account-A-deleted-friend']);
    await _cancelAll(firstSubscriptions);
    subscriptions.removeWhere(firstSubscriptions.contains);

    OpenIM.iMManager.userID = 'account-B';
    final pageB = <String>[];
    final secondSubscriptions = _listenFriendEvents(im, pageB);
    subscriptions.addAll(secondSubscriptions);
    await _settle();
    expect(pageB, isEmpty);
    _emitFriendEvents(im, 'account-B');
    await _settle();
    expect(
        pageB, ['added:account-B-friend', 'removed:account-B-deleted-friend']);
    await _cancelAll(secondSubscriptions);
    subscriptions.removeWhere(secondSubscriptions.contains);

    OpenIM.iMManager.userID = 'account-A';
    final secondA = <String>[];
    subscriptions.addAll(_listenFriendEvents(im, secondA));
    await _settle();
    expect(secondA, isEmpty);
    _emitFriendEvents(im, 'account-A');
    await _settle();
    expect(secondA,
        ['added:account-A-friend', 'removed:account-A-deleted-friend']);
  });
}
