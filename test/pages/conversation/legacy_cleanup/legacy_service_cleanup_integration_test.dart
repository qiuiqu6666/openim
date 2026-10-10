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
    cleanup = LegacyServiceConversationCleanup(
      session: () =>
          (owner: 'self', token: 'test', server: 'http://129.226.192.93:10002'),
      readPage: (offset, count) async =>
          local.skip(offset).take(count).toList(),
      readConversation: (id) async =>
          local.where((item) => item.conversationID == id).toList(),
      readHistory: (_, __) async =>
          AdvancedMessage(messageList: [], isEnd: true),
      deleteMessage: (_, __) async {},
      hideConversation: (id) async {
        deleteCalls++;
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
      markCompleted: (_) async {},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      expect(call.method, 'getConversationListSplit');
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
    expect(deleteCalls, 1);
    expect(logic.list.map((item) => item.conversationID), ['ordinary']);
    expect(home.conversationsAtFirstPage.map((item) => item.conversationID),
        ['ordinary']);
    expect(logic.tempDraftText, isEmpty);
    expect(ChatHistoryCache.read('self', legacy.conversationID), isEmpty);
    logic.onClose();
  });

  test('first page still removes authorized legacy rows from the cached page',
      () async {
    final logic = ConversationLogic(legacyCleanup: cleanup);
    home.conversationsAtFirstPage.addAll([legacy, ordinary]);
    await logic.getFirstPage();
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
      expect(deleteCalls, 1);
      expect(logic.list.map((item) => item.conversationID), ['ordinary']);
      logic.onClose();
    });
  }

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
