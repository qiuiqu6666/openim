import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/legacy_cleanup/legacy_service_conversation_cleanup.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/home/home_logic.dart';

class _App extends GetxController implements AppController {
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

  // Keep the real SDK list reads and lifecycle subscriptions, without business
  // HTTP or legacy maintenance unrelated to startup recovery.
  @override
  Future<void> refreshOrganizer() async {}
  final _testGroupFeatures = GroupFeatureStore(
    api: GroupFeatureApi(
      baseUrl: 'https://fixture.example',
      tokenProvider: () => '',
      userProvider: () => '',
    ),
    sessionCurrent: () => false,
    fetchGroups: (_) async => [],
  );

  @override
  GroupFeatureStore get groupFeatures => _testGroupFeatures;

  @override
  void onClose() {
    groupFeatures.dispose();
    super.onClose();
  }
}

ConversationInfo _row(String id, {int time = 1}) => ConversationInfo(
      conversationID: id,
      conversationType: ConversationType.single,
      userID: id,
      latestMsgSendTime: time,
      draftTextTime: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _IM im;
  late _Conversations logic;
  late List<Completer<String>> reads;

  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    Get.put<AppController>(_App());
    im = Get.put<IMController>(_IM()) as _IM;
    Get.put<HomeLogic>(_Home());
    reads = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      expect(call.method, 'getConversationListSplit');
      final reply = Completer<String>();
      reads.add(reply);
      return reply.future;
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
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  void complete(int index, List<ConversationInfo> rows) => reads[index]
      .complete(jsonEncode(rows.map((row) => row.toJson()).toList()));

  Future<void> failInitialRead() async {
    logic.onInit();
    await flush();
    reads.single.completeError(PlatformException(code: '10009'));
    await flush();
    expect(logic.list, isEmpty);
    expect(logic.canShowEmptyFeed, isFalse);
  }

  for (final delivery in ['sync snapshot', 'late callback']) {
    test('pinned group receives missing latest message through $delivery',
        () async {
      ConversationInfo group(String id, int seq, {bool pinned = false}) =>
          ConversationInfo(
            conversationID: 'sg_$id',
            conversationType: ConversationType.superGroup,
            groupID: id,
            isPinned: pinned,
            latestMsgSendTime: seq,
            draftTextTime: 0,
            latestMsg: Message(
              clientMsgID: '$id-$seq',
              groupID: id,
              sessionType: ConversationType.superGroup,
              contentType: MessageType.text,
              sendID: 'peer',
              seq: seq,
              sendTime: seq,
            ),
          );
      logic.onInit();
      await flush();
      complete(0, [group('pinned', 1, pinned: true), group('normal', 5)]);
      await flush();
      expect(logic.feedSnapshot.groups.first.latestMsg?.seq, 1);
      im.imSdkStatus(IMSdkStatus.syncStart);
      im.imSdkStatus(IMSdkStatus.syncEnded);
      await flush();
      complete(1, [
        group('pinned', delivery == 'sync snapshot' ? 4 : 1, pinned: true),
        group('normal', 6),
      ]);
      await flush();
      if (delivery == 'late callback') {
        logic.queueChanges([group('pinned', 4, pinned: true)]);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(logic.list.map((row) => row.conversationID),
          ['sg_pinned', 'sg_normal']);
      expect(logic.feedSnapshot.groups.first.latestMsg?.clientMsgID, 'pinned-4');
      expect(logic.feedSnapshot.groups.first.isPinned, isTrue);
      expect(logic.feedSnapshot.groups.last.latestMsg?.seq, 6);
      expect(reads, hasLength(2));
    });
  }

  for (final failure in [false, true]) {
    test('normal sync restores an initially empty/failed feed ($failure)',
        () async {
      im.imSdkStatus(IMSdkStatus.syncStart, reInstall: false);
      logic.onInit();
      await flush();
      if (failure) {
        reads.single.completeError(PlatformException(code: '10009'));
      } else {
        complete(0, []);
      }
      await flush();
      im.imSdkStatus(IMSdkStatus.syncEnded, reInstall: false);
      await flush();
      expect(reads, hasLength(2));
      final restored = _row('existing')
        ..unreadCount = 3
        ..draftText = 'unsent draft';
      complete(1, [restored]);
      await flush();
      expect(logic.list.single.conversationID, 'existing');
      expect(logic.list.single.unreadCount, 3);
      expect(logic.list.single.draftText, 'unsent draft');
      expect(logic.canShowEmptyFeed, isTrue);
      expect(logic.imStatus.value, IMSdkStatus.syncEnded);
    });
  }

  test('sync completion wins over an older pending initial read', () async {
    logic.onInit();
    await flush();
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await flush();
    expect(reads, hasLength(2));
    logic.queueChanges([_row('live', time: 3)]);
    complete(1, [_row('stored', time: 2)]);
    await flush();
    complete(0, []);
    await flush();
    expect(logic.list.map((row) => row.conversationID), ['live', 'stored']);
  });

  test('sync completed before page creation still reloads the SDK snapshot',
      () async {
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await flush();
    logic.onInit();
    await flush();
    expect(reads, hasLength(2));
    complete(1, [_row('restored')]);
    complete(0, []);
    await flush();
    expect(logic.list.single.conversationID, 'restored');
  });

  for (final trigger in ['reconnect', 'resume']) {
    test('$trigger retries a failed list without overlapping retries',
        () async {
      await failInitialRead();
      void recover() {
        if (trigger == 'reconnect') {
          im.imSdkStatus(IMSdkStatus.connectionSucceeded);
        } else {
          logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
        }
      }

      recover();
      await flush();
      expect(reads, hasLength(2));
      recover();
      await flush();
      expect(reads, hasLength(2));
      complete(1, [_row('restored')]);
      await flush();
      recover();
      await flush();
      expect(reads, hasLength(2));
      expect(logic.list.single.conversationID, 'restored');
    });
  }

  test('duplicate sync finish does not repeatedly scan the list', () async {
    logic.onInit();
    await flush();
    complete(0, [_row('existing')]);
    await flush();
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await flush();
    expect(reads, hasLength(2));
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await flush();
    expect(reads, hasLength(2));
    complete(1, [_row('existing')]);
    await flush();
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await flush();
    expect(reads, hasLength(2));
    im.imSdkStatus(IMSdkStatus.syncStart);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await flush();
    expect(reads, hasLength(3));
    complete(2, [_row('new-cycle')]);
    await flush();
    expect(logic.list.single.conversationID, 'new-cycle');
  });

  test('failed recovery preserves displayed conversations', () async {
    logic.onInit();
    await flush();
    complete(0, [_row('existing')]);
    await flush();
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await flush();
    expect(reads, hasLength(2));
    reads.last.completeError(PlatformException(code: 'read-failed'));
    await flush();
    expect(logic.list.single.conversationID, 'existing');
    expect(logic.canShowEmptyFeed, isFalse);
    // A query may emit another finish callback. A persistent storage error
    // must not turn those callbacks into an unbounded retry loop.
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await flush();
    expect(reads, hasLength(2));
  });

  test('an old account cannot start recovery or accept a late snapshot',
      () async {
    await failInitialRead();
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await flush();
    expect(reads, hasLength(2));
    OpenIM.iMManager.userID = 'another';
    complete(1, [_row('old-account')]);
    await flush();
    im.imSdkStatus(IMSdkStatus.syncStart);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flush();
    expect(logic.list, isEmpty);
    expect(reads, hasLength(2));
  });
}
