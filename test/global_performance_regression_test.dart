import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/directory/contact_directory_indexer.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';

class _FakeApp extends GetxController implements AppController {
  int notifications = 0;

  @override
  Future<void> onNotificationSessionReady({bool authenticated = false}) async {}

  @override
  Future<void> showNotification(Message message,
      {bool showNotification = true}) async {
    notifications++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIM extends GetxController with IMCallback implements IMController {
  @override
  Rx<UserFullInfo> userInfo = UserFullInfo(globalRecvMsgOpt: 0).obs;

  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHome extends GetxController implements HomeLogic {
  @override
  List<ConversationInfo> conversationsAtFirstPage = [];
  @override
  final unhandledFriendApplicationCount = 0.obs;
  @override
  final unhandledGroupApplicationCount = 0.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePush extends GetxController implements PushController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCache extends GetxController implements CacheController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingHome extends HomeLogic {
  int friendRequests = 0;
  int groupRequests = 0;

  @override
  void getUnhandledFriendApplicationCount() => friendRequests++;
  @override
  void getUnhandledGroupApplicationCount() => groupRequests++;
}

class _NotificationApp extends AppController {
  int prompts = 0;
  @override
  Future<void> promptSoundOrNotification(int seq) async => prompts++;
}

ConversationInfo _conversation(String id, int time, {bool pinned = false}) =>
    ConversationInfo(
      conversationID: id,
      latestMsgSendTime: time,
      draftTextTime: 0,
      isPinned: pinned,
    );

Message _message(String id) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'peer',
      'seq': 1,
      'sendTime': 1,
      'textElem': {'content': id},
    });

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdkChannel = MethodChannel('flutter_openim_sdk');
  late _FakeApp app;
  late _FakeIM im;

  setUp(() {
    Get.testMode = true;
    app = Get.put<AppController>(_FakeApp()) as _FakeApp;
    im = Get.put<IMController>(_FakeIM()) as _FakeIM;
    Get.put<HomeLogic>(_FakeHome());
    OpenIM.iMManager.userID = 'self';
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, null);
    ChatHistoryCache.clear();
    Get.reset();
  });

  for (final size in [401, 801]) {
    test('conversation batch of $size is merged without mutating SDK input',
        () async {
      final logic = ConversationLogic();
      logic.list.add(_conversation('retained', 0));
      final batch = List<ConversationInfo>.unmodifiable(
          List.generate(size, (i) => _conversation('c$i', i + 1)));
      final emissions = <int>[];
      final subscription =
          logic.list.listen((rows) => emissions.add(rows.length));

      logic.onChanged(batch);
      await _flush();

      expect(batch.length, size);
      expect(batch.first.conversationID, 'c0');
      expect(logic.list.length, size + 1);
      expect(logic.list.first.conversationID, 'c${size - 1}');
      expect(logic.list.last.conversationID, 'retained');
      expect(emissions, [size + 1]);
      await subscription.cancel();
      logic.onDelete();
    });
  }

  test('latest duplicate wins and pinned conversations keep their ordering',
      () {
    final logic = ConversationLogic();
    logic.list.addAll([
      _conversation('changed', 1),
      _conversation('pinned', 2, pinned: true),
    ]);
    final newest = _conversation('changed', 200);
    logic.onChanged([
      _conversation('changed', 100),
      _conversation('added', 150),
      newest,
    ]);
    expect(logic.list.map((item) => item.conversationID),
        ['pinned', 'changed', 'added']);
    expect(identical(logic.list[1], newest), isTrue);
    logic.onDelete();
  });

  test(
      'conversation subscriptions are canceled when the page controller closes',
      () async {
    final logic = ConversationLogic()..onInit();
    expect(im.conversationAddedSubject.hasListener, isTrue);
    expect(im.conversationChangedSubject.hasListener, isTrue);
    expect(im.imSdkStatusSubject.hasListener, isTrue);
    expect(im.customBusinessMessageSubject.hasListener, isTrue);
    logic.onDelete();
    expect(im.conversationAddedSubject.hasListener, isFalse);
    expect(im.conversationChangedSubject.hasListener, isFalse);
    expect(im.imSdkStatusSubject.hasListener, isFalse);
    expect(im.customBusinessMessageSubject.hasListener, isFalse);
    im.conversationChanged([_conversation('late', 1)]);
    await _flush();
    expect(logic.list, isEmpty);
  });

  test('home subscriptions are canceled rather than accumulating on reentry',
      () async {
    Get.put<PushController>(_FakePush());
    Get.put<CacheController>(_FakeCache());
    final first = _CountingHome()..onInit();
    expect(im.unreadMsgCountEventSubject.hasListener, isTrue);
    first.onDelete();
    expect(im.unreadMsgCountEventSubject.hasListener, isFalse);
    expect(im.friendApplicationChangedSubject.hasListener, isFalse);
    expect(im.groupApplicationChangedSubject.hasListener, isFalse);
    expect(im.imSdkStatusPublishSubject.hasListener, isFalse);

    final second = _CountingHome()..onInit();
    im.friendApplicationAdded(FriendApplicationInfo());
    await _flush();
    expect(first.friendRequests, 0);
    expect(second.friendRequests, 1);
    second.onDelete();
  });

  test('SDK status replays only the latest value and exposes it immediately',
      () async {
    im.imSdkStatus(IMSdkStatus.syncStart, reInstall: true);
    for (var i = 0; i <= 100; i++) {
      im.imSdkStatus(IMSdkStatus.syncProgress, reInstall: true, progress: i);
    }
    im.imSdkStatus(IMSdkStatus.syncEnded);
    expect(im.currentSdkStatus, IMSdkStatus.syncEnded);
    final replayed = <IMSdkStatus>[];
    final subscription =
        im.imSdkStatusSubject.listen((event) => replayed.add(event.status));
    await _flush();
    expect(replayed, [IMSdkStatus.syncEnded]);
    expect(im.imSdkStatusSubject.values.length, 1);
    await subscription.cancel();
  });

  test(
      'offline sync suppresses notification work while still delivering messages',
      () {
    final delivered = <String?>[];
    im.onRecvOfflineMessage = (message) => delivered.add(message.clientMsgID);
    im.imSdkStatus(IMSdkStatus.syncStart);
    im.recvOfflineMessage(_message('offline'));
    expect(app.notifications, 0);
    expect(delivered, ['offline']);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    im.recvOfflineMessage(_message('live'));
    expect(app.notifications, 1);
    expect(delivered, ['offline', 'live']);
  });

  test('revoke and delete remove cached content before forwarding the event',
      () {
    ChatHistoryCache.write(
        'self', 'chat', [_message('revoked'), _message('deleted')]);
    final otherAccount = _message('revoked');
    ChatHistoryCache.write('other', 'chat', [otherAccount]);
    im.onRecvMessageRevoked = (_) {
      expect(ChatHistoryCache.read('self', 'chat').map((m) => m.clientMsgID),
          ['deleted']);
    };
    im.recvMessageRevoked(RevokedInfo(clientMsgID: 'revoked'));
    im.messageDeleted(_message('deleted'));
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
    expect(ChatHistoryCache.read('other', 'chat'), [otherAccount]);
  });

  test(
      'notification query is skipped until sync ends and preserves mute filtering',
      () async {
    var lookups = 0;
    var muted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, (call) async {
      if (call.method == 'getOneConversation') {
        lookups++;
        return jsonEncode({
          'conversationID': 'chat',
          'unreadCount': 0,
          'recvMsgOpt': muted ? 2 : 0,
        });
      }
      return null;
    });
    final notifications = _NotificationApp();
    im.imSdkStatus(IMSdkStatus.syncStart);
    await notifications.showNotification(_message('sync'));
    expect(lookups, 0);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await notifications.showNotification(_message('disabled'),
        showNotification: false);
    expect(lookups, 0);
    await notifications.showNotification(_message('muted'));
    expect(lookups, 1);
    expect(notifications.prompts, 0);
    muted = false;
    await notifications.showNotification(_message('allowed'));
    expect(lookups, 2);
    expect(notifications.prompts, 1);
    notifications.onDelete();
  });

  test('friend refreshes share work and stop obsolete pagination', () async {
    final requests = <Completer<List<FriendInfo>>>[];
    final offsets = <int>[];
    final logic = ContactsLogic(fetchFriendsPage: (offset, _) {
      offsets.add(offset);
      final request = Completer<List<FriendInfo>>();
      requests.add(request);
      return request.future;
    });
    final first = logic.loadFriends();
    final second = logic.loadFriends();
    final third = logic.loadFriends();
    expect(identical(first, second), isTrue);
    expect(identical(first, third), isTrue);
    expect(requests.length, 1);
    requests.single.complete(List.generate(
        1000, (i) => FriendInfo(userID: 'obsolete$i', nickname: 'Old $i')));
    await _flush();
    expect(offsets, [0, 0]);
    requests.last.complete([FriendInfo(userID: 'new', nickname: 'New')]);
    await Future.wait([first, second, third]);
    expect(logic.friends.map((item) => item.userID), ['new']);
    expect(logic.friendsLoading.value, isFalse);
    logic.onDelete();
  });

  test('closing contacts stops later pages and preserves the last directory',
      () async {
    final request = Completer<List<FriendInfo>>();
    var fetches = 0;
    final logic = ContactsLogic(fetchFriendsPage: (_, __) {
      fetches++;
      return request.future;
    });
    logic.friends
        .add(ISUserInfo.fromJson({'userID': 'kept', 'nickname': 'Kept'}));
    final pending = logic.loadFriends();
    logic.onDelete();
    request.complete(List.generate(
        1000, (i) => FriendInfo(userID: 'late$i', nickname: 'Late $i')));
    await pending;
    expect(fetches, 1);
    expect(logic.friends.map((item) => item.userID), ['kept']);
    await logic.loadFriends();
    expect(fetches, 1);
  });

  testWidgets(
      'friend bursts update additions, deletion and remarks without SDK reload',
      (tester) async {
    var fetches = 0;
    final snapshot = <FriendInfo>[];
    final logic = ContactsLogic(
      fetchFriendsPage: (_, __) async {
        fetches++;
        return snapshot;
      },
      directoryIndexer: ContactDirectoryIndexer(
        worker: (names) async => buildContactNameIndex(names),
      ),
    )..onInit();
    for (var i = 0; i < 50; i++) {
      final friend = FriendInfo(userID: 'friend$i', nickname: 'Friend $i');
      snapshot.add(friend);
      im.friendAdded(friend);
    }
    await tester.pump();
    expect(fetches, 0);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(fetches, 0);
    expect(logic.friends.length, 50);
    im.friendDeleted(FriendInfo(userID: 'friend0'));
    im.friendInfoChanged(
        FriendInfo(userID: 'friend1', nickname: 'Friend 1', remark: '阿强'));
    im.friendAdded(FriendInfo(userID: 'new', nickname: 'Zed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(fetches, 0);
    expect(logic.friends.length, 50);
    expect(logic.friends.any((friend) => friend.userID == 'friend0'), isFalse);
    expect(logic.friends.first.userID, 'friend1');
    expect(logic.friends.first.showName, '阿强');
    expect(logic.friends.first.tagIndex, 'A');
    expect(logic.friends.last.userID, 'new');
    expect(logic.friends.last.tagIndex, 'Z');
    expect(
        logic.friends.where((friend) => friend.isShowSuspension), hasLength(3));
    logic.onDelete();
    expect(im.friendAddSubject.hasListener, isFalse);
  });

  testWidgets('closing contacts cancels a queued friend calibration',
      (tester) async {
    var fetches = 0;
    final logic = ContactsLogic(fetchFriendsPage: (_, __) async {
      fetches++;
      return [FriendInfo(userID: 'queued', nickname: 'Queued')];
    })
      ..onInit();
    im.friendAdded(FriendInfo(userID: 'queued', nickname: 'Queued'));
    await tester.pump();
    logic.onDelete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fetches, 0);
    expect(logic.friends, isEmpty);
  });
}
