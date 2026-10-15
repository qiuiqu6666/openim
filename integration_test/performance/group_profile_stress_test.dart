import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/widgets/conversation_feed_row.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/chat/group/chat_group_controller.dart';
import 'package:openim_common/openim_common.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation value) => super.noSuchMethod(value);
}

class _Home extends GetxController implements HomeLogic {
  @override
  dynamic noSuchMethod(Invocation value) => super.noSuchMethod(value);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  dynamic noSuchMethod(Invocation value) => super.noSuchMethod(value);
  @override
  void onClose() {
    close();
    super.onClose();
  }
}

class _Feed extends ConversationLogic {
  // Intentionally suppress application startup networking in this fixture.
  @override
  // ignore: must_call_super
  void onInit() {}
  final _testFeatures = GroupFeatureStore(
    api: GroupFeatureApi(
        baseUrl: 'http://127.0.0.1:1',
        tokenProvider: () => '',
        userProvider: () => ''),
    sessionCurrent: () => true,
    fetchGroups: (_) async => [],
  );
  @override
  GroupFeatureStore get groupFeatures => _testFeatures;
  @override
  String getTime(ConversationInfo info) => '13:22';
  @override
  void onClose() {
    groupFeatures.dispose();
    super.onClose();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('large account profile callback pressure', (tester) async {
    await DataSp.init();
    Get.testMode = true;
    OpenIM.iMManager.userID = 'synthetic-stress';
    Get.put<AppController>(_App());
    Get.put<HomeLogic>(_Home());
    Get.put<IMController>(_IM());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=');
    server.listen((request) {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(png);
      request.response.close();
    });
    final results = <Map<String, dynamic>>[];
    const mode =
        String.fromEnvironment('STRESS_PAGE_MODE', defaultValue: 'compare');
    for (final count in mode == 'compare' ? [1000, 5000] : [5000]) {
      for (final pageSize in mode == 'bulk'
          ? [count]
          : mode == 'paged'
              ? [128]
              : [count, 128]) {
        debugPrint('STRESS_BEGIN $count/$pageSize');
        final logic = _Feed();
        logic.onStart();
        final oldFace = 'http://127.0.0.1:${server.port}/old.png';
        final newFace = 'http://127.0.0.1:${server.port}/new.png';
        final payload = List.filled(2048, 'x').join();
        logic.list.assignAll(List.generate(
            count * 4,
            (i) => ConversationInfo(
                  conversationID: i < count ? 'sg_g$i' : 'si_p$i',
                  groupID: i < count ? 'g$i' : null,
                  userID: i < count ? null : 'p$i',
                  conversationType: i < count
                      ? ConversationType.superGroup
                      : ConversationType.single,
                  showName: 'Before $i',
                  faceURL: oldFace,
                  latestMsgSendTime: count * 4 - i,
                  draftTextTime: 0,
                  unreadCount: 7,
                  latestMsg: Message(
                      clientMsgID: 'm$i',
                      contentType: MessageType.text,
                      textElem: TextElem(content: payload),
                      sendID: 'peer',
                      senderNickname: 'Peer'),
                )));
        for (var i = 0; i < count; i++) {
          logic.groupFeatures.seed(GroupInfo(
              groupID: 'g$i', groupName: 'Before $i', faceURL: oldFace));
        }
        final chatName = 'Before 0'.obs, chatFace = oldFace.obs;
        final events = StreamController<GroupInfo>.broadcast(sync: true);
        final chat = ChatGroupController.withSources(
          groupID: () => 'g0',
          currentUserID: () => OpenIM.iMManager.userID,
          messages: <Message>[].obs,
          clearInput: () {},
          onGroupProfileChanged: (name, face) {
            chatName.value = name;
            chatFace.value = face;
          },
          events: ChatGroupEvents(
              joined: const Stream.empty(),
              left: const Stream.empty(),
              memberAdded: const Stream.empty(),
              memberDeleted: const Stream.empty(),
              memberChanged: const Stream.empty(),
              groupChanged: events.stream),
          queries: ChatGroupQueries(
              isJoined: (_) async => true,
              groupInfo: (_) async => [],
              selfMember: (_, __) async => [],
              ownerAndAdmin: (_) async => []),
        );
        chat.initialize();
        final scroll = ScrollController();
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => GetMaterialApp(
                    home: Scaffold(
                  appBar: PreferredSize(
                      preferredSize: const Size.fromHeight(64),
                      child: Obx(() => TitleBar.chat(
                          title: chatName.value,
                          avatarUrl: chatFace.value,
                          member: '20',
                          showCallBtn: false))),
                  body: Obx(() {
                    final rows = logic.feedSnapshot.groups;
                    return ListView.builder(
                        controller: scroll,
                        itemExtent: 78,
                        itemCount: rows.length,
                        itemBuilder: (_, i) => ConversationFeedRow(
                            key: ValueKey(rows[i].conversationID),
                            logic: logic,
                            info: rows[i],
                            showDivider: true,
                            editing: false,
                            selected: false,
                            onTap: () {},
                            onLongPress: () {}));
                  }),
                ))));
        await tester.pumpAndSettle();
        final wires = <String>[];
        for (var start = 0; start < count; start += pageSize) {
          final changes = <Map<String, dynamic>>[];
          for (var i = start; i < min(start + pageSize, count); i++) {
            final row = ConversationInfo.fromJson(logic.list[i].toJson());
            row.showName = 'After $i';
            row.faceURL = i % 11 == 0 ? '' : newFace;
            final json = row.toJson();
            json['latestMsg'] = jsonEncode(json['latestMsg']);
            changes.add(json);
          }
          wires.add(jsonEncode(changes));
        }
        final frames = <FrameTiming>[];
        void record(List<FrameTiming> values) => frames.addAll(values);
        SchedulerBinding.instance.addTimingsCallback(record);
        final gaps = <double>[];
        final clock = Stopwatch()..start();
        var last = 0;
        var peakRss = ProcessInfo.currentRss;
        final ticker = Ticker((_) {
          final now = clock.elapsedMicroseconds;
          if (last > 0) gaps.add((now - last) / 1000);
          last = now;
          peakRss = max(peakRss, ProcessInfo.currentRss);
        })
          ..start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final startRss = ProcessInfo.currentRss;
        var maxDecodeUs = 0, decodeUs = 0;
        final applied = Stopwatch()..start();
        final movement = scroll.animateTo(1800,
            duration: const Duration(seconds: 2), curve: Curves.linear);
        for (final raw in wires) {
          final decode = Stopwatch()..start();
          final rows = (jsonDecode(raw) as List)
              .map((e) => ConversationInfo.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList();
          decode.stop();
          decodeUs += decode.elapsedMicroseconds;
          maxDecodeUs = max(maxDecodeUs, decode.elapsedMicroseconds);
          logic.queueChanges(rows);
          for (final row in rows) {
            final info = GroupInfo(
                groupID: row.groupID!,
                groupName: row.showName,
                faceURL: row.faceURL);
            logic.groupFeatures.seed(info);
            events.add(info);
          }
          await Future<void>.delayed(const Duration(milliseconds: 4));
        }
        await Future<void>.delayed(const Duration(milliseconds: 180));
        applied.stop();
        await movement;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        ticker.dispose();
        SchedulerBinding.instance.removeTimingsCallback(record);
        clock.stop();
        final indexed = {for (final row in logic.list) row.conversationID: row};
        for (var i = 0; i < count; i++) {
          final row = indexed['sg_g$i']!;
          expect(row.showName, 'After $i');
          expect(row.faceURL, i % 11 == 0 ? '' : newFace);
          expect(row.unreadCount, 7);
        }
        expect(chatName.value, 'After 0');
        expect(chatFace.value, '');
        double percentile(List<double> xs, double p) {
          if (xs.isEmpty) return 0;
          xs.sort();
          return xs[(p * (xs.length - 1)).round()];
        }

        final build =
            frames.map((e) => e.buildDuration.inMicroseconds / 1000).toList();
        final result = <String, dynamic>{
          'groups': count,
          'conversations': count * 4,
          'callback_rows': pageSize,
          'verified': count,
          'wire_MiB': wires.fold<int>(0, (s, v) => s + v.length) / 1048576,
          'apply_ms': applied.elapsedMilliseconds,
          'decode_total_ms': decodeUs / 1000,
          'decode_max_ms': maxDecodeUs / 1000,
          'build_p95_ms': percentile(build, .95),
          'build_max_ms': percentile(build, 1),
          'ticker_p95_ms': percentile(gaps, .95),
          'ticker_max_ms': percentile(gaps, 1),
          'ticker_gaps_over_33ms': gaps.where((e) => e > 33.4).length,
          'frames': frames.length,
          'rss_start_MiB': startRss / 1048576,
          'rss_peak_MiB': peakRss / 1048576
        };
        results.add(result);
        debugPrint('STRESS_RESULT ${jsonEncode(result)}');
        chat.close();
        await events.close();
        logic.onDelete();
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      }
    }
    await server.close(force: true);
    Get.reset();
    binding.reportData = {'groupProfileStress': results};
  }, timeout: const Timeout(Duration(minutes: 10)));
}
