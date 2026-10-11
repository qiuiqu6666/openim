import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/conversation_reads/conversation_read_request.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/legacy_cleanup/legacy_service_conversation_cleanup.dart';
import 'package:openim/pages/conversation/unread/conversation_unread_sync.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/home/home_logic.dart';

class _App extends GetxController implements AppController {
  final badges = <int>[];

  @override
  void showBadge(int count) => badges.add(count);
  @override
  Future<void> onApplicationSessionReady({bool authenticated = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends GetxController implements HomeLogic {
  @override
  final conversationsAtFirstPage = <ConversationInfo>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations extends ConversationLogic {
  _Conversations()
      : super(
            legacyCleanup:
                LegacyServiceConversationCleanup(session: () => null));

  // Preserve production subscriptions, native reads, merge and lifecycle;
  // organizer HTTP and legacy maintenance are unrelated to unread sync.
  @override
  Future<void> refreshOrganizer() async {}

  final _testFeatures = GroupFeatureStore(
    api: GroupFeatureApi(
        baseUrl: 'https://fixture.example',
        tokenProvider: () => '',
        userProvider: () => ''),
    sessionCurrent: () => false,
    fetchGroups: (_) async => [],
  );
  bool closed = false;

  @override
  GroupFeatureStore get groupFeatures => _testFeatures;

  @override
  void onClose() {
    if (closed) return;
    closed = true;
    _testFeatures.dispose();
    super.onClose();
  }
}

ConversationInfo _row({
  String id = 'sg_remote-group',
  int unread = 120,
  int time = 10,
  int sequence = 10,
  String message = 'original-message',
  int receive = 0,
  bool group = true,
}) =>
    ConversationInfo(
      conversationID: id,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      groupID: group ? id.substring(3) : null,
      userID: group ? null : id,
      unreadCount: unread,
      recvMsgOpt: receive,
      latestMsgSendTime: time,
      draftTextTime: 0,
      latestMsg: Message(clientMsgID: message, seq: sequence, sendTime: time),
    );

String _json(List<ConversationInfo> rows) =>
    jsonEncode(rows.map((row) => row.toJson()).toList());

int _groupBadge(ConversationLogic logic) => logic.list
    .where((row) => row.isGroupChat && !logic.isArchived(row))
    .fold(0, (count, row) => count + row.unreadCount);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _App app;
  late _IM im;
  late _Conversations logic;
  late List<MethodCall> calls;
  late List<Completer<String>> reads;

  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    app = Get.put<AppController>(_App()) as _App;
    im = Get.put<IMController>(_IM()) as _IM;
    Get.put<HomeLogic>(_Home());
    calls = [];
    reads = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      // Reconciliation invokes this handler from inside tester.pump. Use the
      // synchronous matcher so native callbacks do not nest test async guards.
      expectSync(call.method, 'getConversationListSplit');
      calls.add(call);
      final read = Completer<String>();
      reads.add(read);
      return read.future;
    });
    logic = _Conversations();
  });

  tearDown(() {
    logic.onClose();
    for (final read in reads) {
      if (!read.isCompleted) read.complete('[]');
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
    OpenIM.iMManager.userID = 'self';
  });

  void complete(int index, List<ConversationInfo> rows) =>
      reads[index].complete(_json(rows));

  Future<void> flush(WidgetTester tester) async {
    // Subject delivery and the resulting MethodChannel call cross separate
    // asynchronous boundaries without advancing either reconciliation timer.
    await tester.pump();
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await flush(tester);
    await tester.pump(ConversationUnreadSync.settleDelay);
    await flush(tester);
  }

  Future<void> start(WidgetTester tester, List<ConversationInfo> rows) async {
    logic.onInit();
    await flush(tester);
    expect(reads, hasLength(1));
    complete(0, rows);
    await flush(tester);
    expect(logic.list, hasLength(rows.length));
  }

  Future<void> total(WidgetTester tester, int value) async {
    im.totalUnreadMsgCountChanged(value);
    await settle(tester);
  }

  Future<void> confirmThenIncrease(WidgetTester tester) async {
    await start(tester, [_row(unread: 3)]);
    final request = ConversationReadRequest.capture(logic.list.single);
    final confirming = logic.onConversationReadRequested(request);
    request.complete(true);
    await confirming;
    expect(logic.list.single.unreadCount, 0);

    im.conversationChanged([_row(unread: 4)]);
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 16));
    await flush(tester);
    expect(logic.list.single.unreadCount, 4,
        reason: 'The same message target has a count beyond the local ack.');
  }

  testWidgets('remote all-read repairs the row and group badge from SDK state',
      (tester) async {
    await start(tester, [_row()]);
    expect(_groupBadge(logic), 120);
    await total(tester, 0);
    expect(app.badges.last, 0);
    expect(reads, hasLength(2));
    expect(_groupBadge(logic), 120,
        reason: 'An aggregate zero alone does not acknowledge any row.');
    complete(1, [_row(unread: 0)]);
    await flush(tester);
    expect(logic.list.single.unreadCount, 0);
    expect(_groupBadge(logic), 0);

    for (var index = 0; index < 3; index++) {
      im.totalUnreadMsgCountChanged(0);
    }
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(reads, hasLength(2),
        reason: 'A query repeating the same aggregate cannot trigger itself.');
    final arguments = Map<String, dynamic>.from(calls.last.arguments as Map);
    expect(arguments['offset'], 0);
    expect(arguments['count'], 400);
  });

  testWidgets(
      'a queued row callback is flushed before the aggregate comparison',
      (tester) async {
    await start(tester, [_row()]);
    im.totalUnreadMsgCountChanged(0);
    await flush(tester);
    await tester.pump(
        ConversationUnreadSync.settleDelay - const Duration(milliseconds: 1));
    im.conversationChanged([_row(unread: 0)]);
    await flush(tester);
    expect(logic.list.single.unreadCount, 120);
    // The regular row-buffer timer has not reached its 16 ms publication yet.
    await tester.pump(const Duration(milliseconds: 1));
    await flush(tester);
    expect(logic.list.single.unreadCount, 0);
    expect(_groupBadge(logic), 0);
    expect(reads, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(reads, hasLength(1));
  });

  testWidgets(
      'SDK count matching includes receive 1 but excludes muted and empty',
      (tester) async {
    await start(tester, [
      _row(unread: 3),
      _row(id: 'single-chat', unread: 2, receive: 1, group: false),
      _row(id: 'sg_muted-group', unread: 75, receive: 2),
      _row(id: 'sg_empty-group', unread: 40, time: 0),
    ]);
    await total(tester, 5);
    expect(reads, hasLength(1));
    expect(
        logic.list.map((row) => row.unreadCount), containsAll([3, 2, 75, 40]));
  });

  testWidgets(
      'a new row during unread calibration wins over its older snapshot',
      (tester) async {
    await start(tester, [_row()]);
    await total(tester, 0);
    expect(reads, hasLength(2));
    im.conversationChanged([
      _row(unread: 1, time: 11, sequence: 11, message: 'new-unread-message'),
    ]);
    im.totalUnreadMsgCountChanged(1);
    await flush(tester);
    complete(1, [_row(unread: 0)]);
    await flush(tester);
    expect(logic.list.single.latestMsg!.clientMsgID, 'new-unread-message');
    expect(logic.list.single.unreadCount, 1);
    expect(_groupBadge(logic), 1);
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(reads, hasLength(2));
    await total(tester, 1);
    expect(reads, hasLength(2));
  });

  testWidgets('a newer ordinary read inherits pending unread authority',
      (tester) async {
    await confirmThenIncrease(tester);
    await total(tester, 0);
    expect(reads, hasLength(2));
    expect(logic.list.single.unreadCount, 4);

    final refreshing = logic.onRefresh();
    await flush(tester);
    expect(reads, hasLength(3));
    complete(2, [_row(unread: 0)]);
    await flush(tester);
    await refreshing;
    expect(logic.list.single.unreadCount, 0,
        reason: 'The latest SDK snapshot must retain calibration authority.');
    expect(_groupBadge(logic), 0);

    complete(1, [_row(unread: 4)]);
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(reads, hasLength(3));
    expect(logic.list.single.unreadCount, 0,
        reason: 'The superseded calibration cannot restore its stale count.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed row during calibration permits one fresh zero read',
      (tester) async {
    await confirmThenIncrease(tester);
    await total(tester, 0);
    expect(reads, hasLength(2));

    im.conversationChanged([_row(unread: 0)]);
    await flush(tester);
    complete(1, [_row(unread: 0)]);
    await flush(tester);
    expect(logic.list.single.unreadCount, 4,
        reason: 'A callback during the read fences its older snapshot.');
    expect(reads, hasLength(2));
    await settle(tester);
    expect(reads, hasLength(3),
        reason: 'One fresh snapshot resolves the count left behind the fence.');
    complete(2, [_row(unread: 0)]);
    await flush(tester);
    expect(logic.list.single.unreadCount, 0);
    expect(_groupBadge(logic), 0);

    await total(tester, 0);
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(reads, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('callbacks during the followup cannot create an unread scan loop',
      (tester) async {
    await confirmThenIncrease(tester);
    await total(tester, 0);
    expect(reads, hasLength(2));
    im.conversationChanged([_row(unread: 0)]);
    await flush(tester);
    complete(1, [_row(unread: 0)]);
    await flush(tester);
    await settle(tester);
    expect(reads, hasLength(3));

    im.conversationChanged([_row(unread: 0)]);
    await flush(tester);
    complete(2, [_row(unread: 0)]);
    await flush(tester);
    expect(logic.list.single.unreadCount, 4);
    for (var index = 0; index < 3; index++) {
      im.totalUnreadMsgCountChanged(0);
    }
    await flush(tester);
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(reads, hasLength(3),
        reason: 'Repeated zero and read callbacks exhaust the one followup.');
    expect(logic.list.single.unreadCount, 4);

    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle(tester);
    expect(reads, hasLength(4),
        reason: 'A later external foreground signal permits recovery.');
    complete(3, [_row(unread: 0)]);
    await flush(tester);
    expect(logic.list.single.unreadCount, 0);
    expect(_groupBadge(logic), 0);
    await tester.pump(const Duration(seconds: 1));
    await flush(tester);
    expect(reads, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  for (final snapshotUnread in [0, 120]) {
    testWidgets(
        'pending SDK read defers aggregate calibration ($snapshotUnread)',
        (tester) async {
      await start(tester, [_row()]);
      final refreshing = logic.onRefresh();
      await flush(tester);
      expect(reads, hasLength(2));
      await total(tester, 0);
      expect(reads, hasLength(2),
          reason: 'Calibration must not overlap a page snapshot read.');
      complete(1, [_row(unread: snapshotUnread)]);
      await flush(tester);
      await refreshing;
      await settle(tester);
      if (snapshotUnread == 0) {
        expect(reads, hasLength(2));
      } else {
        expect(reads, hasLength(3));
        complete(2, [_row(unread: 0)]);
        await flush(tester);
      }
      expect(logic.list.single.unreadCount, 0);
      expect(_groupBadge(logic), 0);
    });
  }

  testWidgets(
      'a failed calibration preserves rows and same totals do not retry',
      (tester) async {
    await start(tester, [_row()]);
    await total(tester, 0);
    expect(reads, hasLength(2));
    await total(tester, 0);
    expect(reads, hasLength(2));
    reads.last.completeError(PlatformException(code: 'READ_FAILED'));
    await flush(tester);
    expect(logic.list.single.unreadCount, 120);
    await total(tester, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(reads, hasLength(2));
    expect(tester.takeException(), isNull);

    await total(tester, 1);
    expect(reads, hasLength(3),
        reason: 'A new aggregate still permits a later recovery attempt.');
    complete(2, [_row(unread: 1)]);
    await flush(tester);
    expect(logic.list.single.unreadCount, 1);
  });

  for (final trigger in ['resume', 'reconnect']) {
    testWidgets('$trigger forces one read when the SDK aggregate is unchanged',
        (tester) async {
      await start(tester, [_row(receive: 2)]);
      await total(tester, 0);
      expect(reads, hasLength(1));
      if (trigger == 'reconnect') {
        im.imSdkStatus(IMSdkStatus.connectionSucceeded);
        await flush(tester);
        await settle(tester);
        expect(reads, hasLength(1),
            reason: 'Initial connection success is not a reconnection.');
        im.imSdkStatus(IMSdkStatus.connecting);
        im.imSdkStatus(IMSdkStatus.connectionSucceeded);
        im.imSdkStatus(IMSdkStatus.connectionSucceeded);
      } else {
        logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
        logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
      }
      await flush(tester);
      await settle(tester);
      expect(reads, hasLength(2));
      complete(1, [_row(unread: 0, receive: 2)]);
      await flush(tester);
      expect(_groupBadge(logic), 0);
      await total(tester, 0);
      expect(reads, hasLength(2));
    });
  }

  for (final stop in ['clear', 'close', 'account']) {
    void stopSession() {
      switch (stop) {
        case 'clear':
          logic.clearConversations();
        case 'close':
          logic.onClose();
        case 'account':
          OpenIM.iMManager.userID = 'another-account';
      }
    }

    testWidgets('$stop rejects an aggregate timer before it starts a read',
        (tester) async {
      await start(tester, [_row()]);
      im.totalUnreadMsgCountChanged(0);
      await flush(tester);
      stopSession();
      await settle(tester);
      expect(reads, hasLength(1));
      if (stop == 'account') {
        expect(logic.list.single.unreadCount, 120);
      } else {
        expect(logic.list, isEmpty);
      }
    });

    testWidgets('$stop rejects the late unread calibration snapshot',
        (tester) async {
      await start(tester, [_row()]);
      await total(tester, 0);
      expect(reads, hasLength(2));
      stopSession();
      if (stop == 'account') {
        logic.list.assignAll([_row(unread: 8, message: 'replacement-account')]);
      }
      complete(1, [_row(unread: 0)]);
      await flush(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(reads, hasLength(2));
      if (stop == 'account') {
        expect(logic.list.single.latestMsg!.clientMsgID, 'replacement-account');
        expect(logic.list.single.unreadCount, 8);
      } else {
        expect(logic.list, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
