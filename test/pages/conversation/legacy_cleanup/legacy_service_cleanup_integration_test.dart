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
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  Future<void> onApplicationSessionReady({bool authenticated = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _IM im;
  late _Home home;
  late ConversationInfo legacy;
  late ConversationInfo ordinary;
  late LegacyServiceConversationCleanup cleanup;
  late bool serverPresent;
  late int deleteCalls;
  late int historyReads;
  Completer<AdvancedMessage>? pendingHistory;
  Completer<void>? pendingHide;
  late Completer<void> hideStarted;
  Future<Object?> Function(MethodCall)? conversationRead;
  late int conversationReads;
  late Completer<void> cleanupCompleted;
  late List<ConversationInfo> local;
  Completer<void>? serverGate;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    Get.put<AppController>(_App());
    im = _IM();
    home = _Home();
    Get.put<IMController>(im);
    Get.put<HomeLogic>(home);
    final peer = LegacyServiceConversationCleanup.peers.first;
    final pair = ['self', peer]..sort();
    legacy = ConversationInfo(
      conversationID: 'si_${pair.join('_')}',
      conversationType: ConversationType.single,
      userID: peer,
      draftTextTime: 0,
      latestMsgSendTime: LegacyServiceConversationCleanup.cutoffMilliseconds,
    );
    ordinary = ConversationInfo(
      conversationID: 'ordinary',
      conversationType: ConversationType.single,
      userID: 'ordinary',
      draftTextTime: 0,
      latestMsgSendTime: 1,
    );
    local = [legacy, ordinary];
    serverPresent = false;
    deleteCalls = 0;
    serverGate = null;
    historyReads = 0;
    pendingHistory = null;
    pendingHide = null;
    hideStarted = Completer<void>();
    conversationRead = null;
    conversationReads = 0;
    cleanupCompleted = Completer<void>();
    cleanup = LegacyServiceConversationCleanup(
      session: () =>
          (owner: 'self', token: 'test', server: 'http://129.226.192.93:10002'),
      readPage: (offset, count) async =>
          local.skip(offset).take(count).toList(),
      readConversation: (id) async =>
          local.where((item) => item.conversationID == id).toList(),
      readHistory: (_, __) async {
        historyReads++;
        return pendingHistory == null
            ? AdvancedMessage(messageList: [], isEnd: true)
            : await pendingHistory!.future;
      },
      deleteMessage: (_, __) async {},
      hideConversation: (id) async {
        deleteCalls++;
        if (!hideStarted.isCompleted) hideStarted.complete();
        if (pendingHide != null) await pendingHide!.future;
        local.removeWhere((item) => item.conversationID == id);
      },
      post: (_, __, ___) async {
        await serverGate?.future;
        return {
          'errCode': 0,
          'data': {
            'versionID': 'v',
            'conversationIDs': [if (serverPresent) legacy.conversationID],
          },
        };
      },
      isCompleted: (_) async => false,
      markCompleted: (_) async {
        if (!cleanupCompleted.isCompleted) cleanupCompleted.complete();
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      expect(call.method, 'getConversationListSplit');
      conversationReads++;
      if (conversationRead != null) return conversationRead!(call);
      // Deliberately stale native snapshot exercises the controller's delete guard.
      return jsonEncode([legacy.toJson(), ordinary.toJson()]);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    ChatHistoryCache.clear();
    Get.reset();
  });

  test(
      'pull refresh clears successful cleanup from UI, home, history and draft',
      () async {
    final logic = ConversationLogic(legacyCleanup: cleanup);
    home.conversationsAtFirstPage.addAll([legacy, ordinary]);
    logic.list.addAll([legacy, ordinary]);
    logic.tempDraftText[legacy.conversationID] = 'old cached draft';
    ChatHistoryCache.write(
        'self', legacy.conversationID, [Message(clientMsgID: 'old-message')]);
    await logic.onRefresh();
    await cleanupCompleted.future;
    expect(deleteCalls, 1);
    expect(logic.list.map((item) => item.conversationID), ['ordinary']);
    expect(home.conversationsAtFirstPage.map((item) => item.conversationID),
        ['ordinary']);
    expect(logic.tempDraftText, isEmpty);
    expect(ChatHistoryCache.read('self', legacy.conversationID), isEmpty);
    logic.onClose();
  });

  test('background cleanup updates the cached first page after it is published',
      () async {
    final logic = ConversationLogic(legacyCleanup: cleanup);
    home.conversationsAtFirstPage.addAll([legacy, ordinary]);
    await logic.getFirstPage();
    await cleanupCompleted.future;
    expect(deleteCalls, 1);
    expect(logic.list.map((item) => item.conversationID), ['ordinary']);
    logic.onClose();
  });

  for (final source in ['cache', 'sdk', 'refresh']) {
    test('$source rows are visible while cleanup waits on the server',
        () async {
      serverGate = Completer<void>();
      final logic = ConversationLogic(legacyCleanup: cleanup);
      if (source == 'cache') {
        home.conversationsAtFirstPage.addAll([legacy, ordinary]);
      }
      final pending =
          source == 'refresh' ? logic.onRefresh() : logic.getFirstPage();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(deleteCalls, 0);
      expect(logic.list.map((item) => item.conversationID),
          contains(ordinary.conversationID));
      serverGate!.complete();
      await pending;
      await cleanupCompleted.future;
      expect(deleteCalls, 1);
      expect(logic.list.map((item) => item.conversationID), ['ordinary']);
      logic.onClose();
    });
  }

  for (final cached in [true, false]) {
    test(
        'first page publishes while legacy history is pending (cached: $cached)',
        () async {
      pendingHistory = Completer<AdvancedMessage>();
      final logic = ConversationLogic(legacyCleanup: cleanup);
      if (cached) home.conversationsAtFirstPage.addAll([legacy, ordinary]);
      var firstPageCompleted = false;
      final firstPage = logic.getFirstPage().then((_) {
        firstPageCompleted = true;
      });
      try {
        for (var i = 0; i < 20 && historyReads == 0; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(historyReads, 1);
        expect(firstPageCompleted, isTrue,
            reason: 'Maintenance history must not gate conversation display');
        expect(logic.list.map((row) => row.conversationID),
            contains(ordinary.conversationID));
        expect(deleteCalls, 0);
      } finally {
        pendingHistory!.complete(AdvancedMessage(messageList: [], isEnd: true));
        await firstPage;
        await cleanupCompleted.future;
        logic.onClose();
      }
    });
  }

  test('refresh publishes and preserves drafts while legacy history is pending',
      () async {
    pendingHistory = Completer<AdvancedMessage>();
    final logic = ConversationLogic(legacyCleanup: cleanup);
    logic.tempDraftText[legacy.conversationID] = 'cached draft';
    var refreshCompleted = false;
    final refresh = logic.onRefresh().then((_) => refreshCompleted = true);
    try {
      for (var i = 0; i < 20 && historyReads == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(historyReads, 1);
      expect(refreshCompleted, isTrue);
      expect(logic.list.map((row) => row.conversationID),
          contains(ordinary.conversationID));
      expect(logic.tempDraftText[legacy.conversationID], 'cached draft');
    } finally {
      pendingHistory!.complete(AdvancedMessage(messageList: [], isEnd: true));
      await refresh;
      await cleanupCompleted.future;
      expect(logic.list.map((row) => row.conversationID), ['ordinary']);
      expect(logic.tempDraftText, isEmpty);
      logic.onClose();
    }
  });

  test('cleanup cannot hide while a refresh is between SDK pages', () async {
    pendingHistory = Completer<AdvancedMessage>();
    final secondPageStarted = Completer<void>();
    final secondPage = Completer<String>();
    local.addAll(List.generate(
        399,
        (index) => ConversationInfo(
              conversationID: 'ordinary-$index',
              conversationType: ConversationType.single,
              userID: 'ordinary-$index',
              draftTextTime: 0,
              latestMsgSendTime: 1,
            )));
    conversationRead = (_) async {
      if (conversationReads == 1) {
        return jsonEncode(local.take(400).map((row) => row.toJson()).toList());
      }
      if (!secondPageStarted.isCompleted) secondPageStarted.complete();
      return secondPage.future;
    };
    final logic = ConversationLogic(legacyCleanup: cleanup);
    home.conversationsAtFirstPage.addAll([legacy, ordinary]);
    await logic.getFirstPage();
    for (var i = 0; i < 20 && historyReads == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final refresh = logic.onRefresh();
    await secondPageStarted.future;
    pendingHistory!.complete(AdvancedMessage(messageList: [], isEnd: true));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(deleteCalls, 0,
        reason:
            'Hiding shifts native page offsets and may skip ordinary chats');
    expect(local, hasLength(401));
    secondPage.complete(
        jsonEncode(local.skip(400).map((row) => row.toJson()).toList()));
    await refresh;
    await cleanupCompleted.future;
    expect(logic.list, hasLength(400));
    expect(
        logic.list.map((row) => row.conversationID), contains('ordinary-398'));
    expect(deleteCalls, 1);
    logic.onClose();
  });

  test('refresh waits only for a local hide already started before the read',
      () async {
    pendingHide = Completer<void>();
    final logic = ConversationLogic(legacyCleanup: cleanup);
    home.conversationsAtFirstPage.addAll([legacy, ordinary]);
    await logic.getFirstPage();
    await hideStarted.future;
    var refreshCompleted = false;
    final refresh = logic.onRefresh().then((_) => refreshCompleted = true);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(conversationReads, 0);
    expect(refreshCompleted, isFalse);
    pendingHide!.complete();
    await refresh;
    await cleanupCompleted.future;
    expect(conversationReads, 1);
    expect(logic.list.map((row) => row.conversationID), ['ordinary']);
    expect(deleteCalls, 1);
    logic.onClose();
  });

  test('failed maintenance hide cannot fail or block a waiting list refresh',
      () async {
    pendingHide = Completer<void>();
    final logic = ConversationLogic(legacyCleanup: cleanup);
    home.conversationsAtFirstPage.addAll([legacy, ordinary]);
    await logic.getFirstPage();
    await hideStarted.future;
    var refreshCompleted = false;
    final refresh = logic.onRefresh().then((_) => refreshCompleted = true);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(conversationReads, 0);
    expect(refreshCompleted, isFalse);
    pendingHide!.completeError(StateError('Maintenance SDK hide failed'));
    await refresh;
    expect(refreshCompleted, isTrue);
    expect(conversationReads, 1);
    expect(logic.list.map((row) => row.conversationID),
        contains(ordinary.conversationID));
    expect(logic.canShowEmptyFeed, isTrue,
        reason:
            'A failed maintenance write cannot mark a successful read failed');
    expect(local.map((row) => row.conversationID),
        contains(legacy.conversationID));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    logic.onClose();
  });

  test('ordinary reconnect sync completion retries without requiring reinstall',
      () async {
    serverPresent = true;
    final logic = ConversationLogic(legacyCleanup: cleanup);
    home.conversationsAtFirstPage.addAll([legacy, ordinary]);
    logic.onInit();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(deleteCalls, 0);
    serverPresent = false;
    im.imSdkStatus(IMSdkStatus.syncEnded, reInstall: false);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(deleteCalls, 1);
    expect(logic.list.map((item) => item.conversationID), ['ordinary']);
    logic.onClose();
  });
}
