import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/core/session/message_events.dart';
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

// Simulated SDK callbacks exercise production ChatLogic, ingress and bubbles.
// No real account login, SDK database writes or messages to other users.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('local calls remain chronological after incoming images',
      (tester) async {
    await DataSp.init();
    Get.testMode = true;
    const channel = MethodChannel('flutter_openim_sdk');
    final imageBytes = await rootBundle.load('assets/img/99chat_logo.png');
    final imageServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final imageURL = 'http://127.0.0.1:${imageServer.port}/test.png';
    final imageRequests = imageServer.listen((request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(imageBytes.buffer.asUint8List());
      await request.response.close();
    });
    addTearDown(() async {
      await imageRequests.cancel();
      await imageServer.close(force: true);
    });
    for (final syncing in [false]) {
      for (var run = 0; run < 1; run++) {
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
            4,
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
                  'textElem': {'content': 'Message ${i + 1}'},
                }));
        for (final (id, type, time) in [
          ('old-audio', 'audio', 1700000000000),
          ('old-video', 'video', 1700000000002),
        ]) {
          rows.add(Message.fromJson({
            'clientMsgID': id,
            'seq': 0,
            'sendTime': time,
            'status': MessageStatus.succeeded,
            'isRead': true,
            'contentType': MessageType.custom,
            'sessionType': ConversationType.single,
            'sendID': 'peer',
            'recvID': 'self',
            'customElem': {
              'data': jsonEncode({
                'customType': CustomMessageType.call,
                'data': {
                  'roomID': id,
                  'duration': 0,
                  'state': 'cancel',
                  'type': type
                }
              })
            },
          }));
        }
        var reads = 0;
        var localReads = 0;
        final window = {
          'version': 1,
          'conversationID': 'chat',
          'targetWatermark': 4,
          'latestServerSeq': 4,
          'lowerBound': 1,
          'covered': [
            [1, 4]
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
                                    title: const Text('Call order test')),
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
        expect(logic.messageList.length, 6);
        await tester.pump(const Duration(milliseconds: 400));
        final before = logic.messageList.map((m) => m.clientMsgID).toList();
        expect(
            before.indexOf('old-audio'), lessThan(before.indexOf('profile-4')));
        expect(
            before.indexOf('old-video'), lessThan(before.indexOf('profile-4')));
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('call-order-before-images');
        for (var seq = 5; seq <= 7; seq++) {
          final picture = Message.fromJson({
            'clientMsgID': 'incoming-image-$seq',
            'seq': seq,
            'sendTime': 1700000000000 + seq,
            'status': MessageStatus.succeeded,
            'isRead': false,
            'contentType': MessageType.picture,
            'sessionType': ConversationType.single,
            'sendID': 'peer',
            'recvID': 'self',
            'pictureElem': {
              'sourcePath': '',
              'sourcePicture': {
                'width': 160,
                'height': 100,
                'type': 'image/png',
                'url': imageURL
              },
              'bigPicture': {
                'width': 160,
                'height': 100,
                'type': 'image/png',
                'url': imageURL
              },
              'snapshotPicture': {
                'width': 160,
                'height': 100,
                'type': 'image/png',
                'url': imageURL
              },
            },
          });
          im.publishChatMessage(picture, ChatMessageSource.live);
          await tester.pump(const Duration(milliseconds: 300));
          expect(logic.messageList.map((m) => m.clientMsgID), [
            ...before,
            for (var n = 5; n <= seq; n++) 'incoming-image-$n',
          ]);
        }
        logic.scrollBottom();
        await tester.pump(const Duration(milliseconds: 500));
        debugPrint(
            'CALL_ORDER_DEVICE_PASS: old audio/video retain positions, three incoming images append after history');
        await tester.pump();
        await binding.takeScreenshot('call-order-after-three-images');
        binding.reportData!.addAll({
          'scope':
              'simulated receive callbacks, production ChatLogic and bubbles on emulator',
          'before': before,
          'after': logic.messageList.map((m) => m.clientMsgID).toList(),
          'historyQueries': reads,
          'localQueries': localReads,
          'passed': true,
        });
        syncTimer?.cancel();
        logic.onDelete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 400));
        Get.reset();
      }
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
