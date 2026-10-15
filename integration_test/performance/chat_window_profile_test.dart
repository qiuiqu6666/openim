import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/navigation/chat_entry_trace.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';

import '../../test/support/chat/chat_entry_sdk.dart';

// Synthetic SDK timings, production ChatLogic, message bubbles and viewport.
// Run in the separate performance application; never logs into a real account.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('chat window entry profile', (tester) async {
    await DataSp.init();
    Get.testMode = true;
    const channel = MethodChannel('flutter_openim_sdk');
    final results = <Map<String, Object>>[];
    for (final syncing in [false, true]) {
      for (var run = 0; run < 3; run++) {
        ChatHistoryCache.clear();
        ChatHistoryPrefetcher.shared.clear();
        OpenIM.iMManager.userID = 'self';
        OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
        Get.put<AppController>(EntryTestApp());
        final im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
        Get.put<ConversationLogic>(EntryTestConversation());
        Get.put<CacheController>(EntryTestCache());
        im.imSdkStatus(
            syncing ? IMSdkStatus.synchronizing : IMSdkStatus.syncEnded);
        final rows = List.generate(
            40,
            (i) => Message.fromJson({
                  'clientMsgID': 'profile-${i + 1}',
                  'seq': i + 1,
                  'sendTime': 1700000000000 + i,
                  'status': MessageStatus.succeeded,
                  'contentType': MessageType.text,
                  'sessionType': ConversationType.single,
                  'sendID': 'peer',
                  'recvID': 'self',
                  'senderNickname': 'Peer',
                  'textElem': {
                    'content':
                        'Message ${i + 1}. ${List.filled(i % 4 + 1, 'A stable message window.').join(' ')}'
                  },
                }));
        var reads = 0;
        var localReads = 0;
        final window = {
          'version': 1,
          'conversationID': 'chat',
          'targetWatermark': 40,
          'latestServerSeq': 40,
          'lowerBound': 1,
          'covered': [
            [1, 40]
          ],
          'missing': [],
          'publishable': true,
          'visibilityKey': 'fixture:1',
          'readiness': 'ready',
          'coverageStatus': 'covered',
          'snapshotRevision': 'fixture-40',
        };
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          if (call.method == 'getLocalHistorySnapshot') {
            localReads++;
            await Future<void>.delayed(const Duration(
                milliseconds: int.fromEnvironment('CHAT_ENTRY_LOCAL_DELAY_MS',
                    defaultValue: 5)));
            return jsonEncode({
              'localSnapshot': true,
              'snapshotReady': true,
              'window': {...window, 'source': 'local'},
              'errCode': 0,
              'messageList': rows.map((m) => m.toJson()).toList()
            });
          }
          if (call.method == 'getAdvancedHistoryMessageList') {
            reads++;
            await Future<void>.delayed(const Duration(
                milliseconds: int.fromEnvironment('CHAT_ENTRY_REMOTE_DELAY_MS',
                    defaultValue: 300)));
            return jsonEncode({
              'errCode': 0,
              'isEnd': true,
              'window': {...window, 'source': 'remote'},
              'messageList': rows.map((m) => m.toJson()).toList()
            });
          }
          if (call.method == 'getBlacklist') return '[]';
          if (call.method == 'getUsersInfo') {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return '[]';
          }
          return null;
        });
        final conversation = ConversationInfo(
            conversationID: 'chat',
            userID: 'peer',
            conversationType: ConversationType.single,
            showName: 'Peer',
            unreadCount: 0,
            groupAtType: GroupAtType.atNormal,
            latestMsg: rows.last);
        final frames = <FrameTiming>[];
        void record(List<FrameTiming> values) => frames.addAll(values);
        SchedulerBinding.instance.addTimingsCallback(record);
        late ChatEntryTrace trace;
        ChatLogic? controller;
        final chatRoute =
            AppPages.routes.firstWhere((p) => p.name == AppRoutes.chat);
        Timer? syncTimer;
        if (syncing) {
          syncTimer = Timer(const Duration(milliseconds: 1200),
              () => im.imSdkStatus(IMSdkStatus.syncEnded));
        }
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => GetMaterialApp(
                    getPages: [
                      GetPage(
                          name: AppRoutes.chat,
                          customTransition: chatRoute.customTransition,
                          transitionDuration: chatRoute.transitionDuration,
                          page: () {
                            final logic =
                                controller ??= (ChatLogic()..onInit());
                            return Scaffold(
                                appBar: AppBar(
                                    title: const Text(
                                        'Window performance fixture')),
                                body: ChatMessageList(logic: logic));
                          })
                    ],
                    home: Scaffold(
                        body: Center(
                            child: TextButton(
                                onPressed: () {
                                  trace =
                                      ChatEntryTrace(ConversationType.single);
                                  unawaited(AppNavigator.startChat<void>(
                                      conversationInfo: conversation,
                                      entryTrace: trace,
                                      offUntilHome: false));
                                },
                                child: const Text('Open chat')))))));
        await tester.pumpAndSettle();
        final watch = Stopwatch()..start();
        await tester.tap(find.text('Open chat'));
        while (!trace.complete && watch.elapsedMilliseconds < 5000) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final logic = controller!;
        expect(trace.complete, isTrue);
        expect(trace.milliseconds['first_correct_message_frame'], isNotNull);
        expect(logic.initialWindowReady.value, isTrue);
        expect(logic.messageList.length, 40);
        await tester.pump(const Duration(milliseconds: 400));
        SchedulerBinding.instance.removeTimingsCallback(record);
        double p95(Iterable<double> values) {
          final sorted = values.toList()..sort();
          return sorted.isEmpty
              ? 0
              : sorted[((sorted.length - 1) * .95).round()];
        }

        results.add({
          'globalSync': syncing,
          'run': run,
          'stagesMs': trace.milliseconds,
          'routeDurationMs': chatRoute.transitionDuration!.inMilliseconds,
          'frames': frames.length,
          'buildP95Ms':
              p95(frames.map((f) => f.buildDuration.inMicroseconds / 1000)),
          'rasterP95Ms':
              p95(frames.map((f) => f.rasterDuration.inMicroseconds / 1000)),
          'rssBytes': ProcessInfo.currentRss,
          'historyQueries': reads,
          'localQueries': localReads,
        });
        debugPrint('CHAT_WINDOW_PROFILE ${jsonEncode(results.last)}');
        syncTimer?.cancel();
        logic.onDelete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 400));
        Get.reset();
      }
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.reportData = {
      'scope': 'synthetic transport, production controller and bubbles',
      'results': results
    };
  });
}
