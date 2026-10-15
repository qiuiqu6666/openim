import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openim/main.dart' as app;
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/session/message_events.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';
import 'package:openim/pages/chat/navigation/chat_entry_trace.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';

import 'live_chat_audit.dart';
import 'live_sdk_reconnect_probe.dart';

/// Runs the full application against its existing login, database and native
/// SDK. Never replaces platform channels and never sends messages to users.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('real SDK chat entry and live stream', (tester) async {
    final start = Stopwatch()..start();
    final results = <Map<String, Object?>>[];
    final reconnectSamples = <Map<String, Object?>>[];
    final payload = <String, Object?>{
      'scope': 'full application, real SDK and account, profile',
      'results': results
    };
    binding.reportData = payload;
    final reconnectProbe = const bool.fromEnvironment('CHAT_LIVE_RECONNECT')
        ? LiveSdkReconnectProbe()
        : null;
    if (reconnectProbe != null) {
      reconnectProbe.attach(binding.defaultBinaryMessenger);
      payload['nativeFailures'] = reconnectProbe.failures;
      payload['reconnectSamples'] = reconnectSamples;
    }
    var announcementConfirmations = 0;
    Future<void> waitUntil(bool Function() ready,
        {int timeoutMs = 30000}) async {
      final watch = Stopwatch()..start();
      while (!ready() && watch.elapsedMilliseconds < timeoutMs) {
        await tester.pump(const Duration(milliseconds: 16));
        // Freshly restored accounts can have a real unread group announcement.
        // Acknowledge only this known UI, and record its effect on entry timing.
        final confirm = find.text('我知道了').hitTestable();
        if (find.text('群公告').evaluate().isNotEmpty &&
            confirm.evaluate().length == 1) {
          await tester.tap(confirm);
          announcementConfirmations++;
          await tester.pump(const Duration(milliseconds: 300));
        }
      }
      if (!ready()) throw StateError('Condition timed out after $timeoutMs ms');
    }

    final testErrorHandler = FlutterError.onError;
    app.main();
    // main installs the production error logger; test failures must still
    // reach the test binding instead of being turned into log-only success.
    FlutterError.onError = testErrorHandler;
    await waitUntil(
        () =>
            Get.isRegistered<ConversationLogic>() &&
            Get.find<ConversationLogic>()
                .list
                .any((c) => c.latestMsg != null) &&
            Get.currentRoute == AppRoutes.home,
        timeoutMs: 90000);
    payload['startupToConversationListMs'] = start.elapsedMilliseconds;
    final feed = Get.find<ConversationLogic>();
    final im = Get.find<IMController>();
    final incoming = <String, int>{};
    final liveSequences = <String, Set<int>>{};
    final liveText = <String, Map<String, int>>{};
    final receiveSub = im.chatMessageEvents.listen((e) {
      if (e.source != ChatMessageSource.live) return;
      final group = e.message.groupID;
      if (group == null || group.isEmpty) return;
      incoming[group] = (incoming[group] ?? 0) + 1;
      if ((e.message.seq ?? 0) > 0) {
        (liveSequences[group] ??= {}).add(e.message.seq!);
        if (e.message.contentType == MessageType.text &&
            e.message.clientMsgID != null) {
          (liveText[group] ??= {})[e.message.clientMsgID!] = e.message.seq!;
        }
      }
    });
    addTearDown(receiveSub.cancel);
    final a = feed.list.firstWhere((c) =>
        c.conversationType == ConversationType.single &&
        (c.latestMsg?.seq ?? 0) > 0 &&
        c.userID != 'assistant');
    LiveChatAudit? audit;
    ChatEntryTrace? pendingTrace;
    var sampling = true;
    binding.addPersistentFrameCallback((_) {
      if (sampling) {
        binding.addPostFrameCallback((_) {
          if (audit == null && pendingTrace != null) {
            for (final e in find.byType(ChatMessageList).evaluate()) {
              final logic = (e.widget as ChatMessageList).logic;
              if (identical(logic.entryTrace, pendingTrace)) {
                audit = LiveChatAudit(logic, e);
                break;
              }
            }
          }
          audit?.sample();
        });
      }
    });
    addTearDown(() {
      sampling = false;
      audit = null;
    });
    Future<ChatLogic> open(ConversationInfo c, String label,
        {int holdMs = 1500, bool interrupt = false}) async {
      final trace = ChatEntryTrace(c.conversationType);
      final frames = <FrameTiming>[];
      void record(List<FrameTiming> f) => frames.addAll(f);
      binding.addTimingsCallback(record);
      final beforeReceived = incoming[c.groupID] ?? 0;
      final beforeConfirmations = announcementConfirmations;
      audit = null;
      pendingTrace = trace;
      unawaited(AppNavigator.startChat<void>(
          conversationInfo: c, offUntilHome: true, entryTrace: trace));
      await waitUntil(() => find.byType(ChatMessageList).evaluate().any((e) =>
          identical((e.widget as ChatMessageList).logic.entryTrace, trace)));
      final element = find.byType(ChatMessageList).evaluate().firstWhere((e) =>
          identical((e.widget as ChatMessageList).logic.entryTrace, trace));
      final logic = (element.widget as ChatMessageList).logic;
      audit ??= LiveChatAudit(logic, element);
      if (!interrupt) await waitUntil(() => trace.complete, timeoutMs: 30000);
      await tester.pump(Duration(milliseconds: holdMs));
      expect(logic.isClosed, isFalse,
          reason: '$label route was externally closed during measurement');
      expect(element.mounted, isTrue);
      expect(ModalRoute.of(element)?.isCurrent, isTrue,
          reason: '$label route must remain visible for the whole sample');
      final result = <String, Object?>{
        'case': label,
        'stagesMs': trace.milliseconds,
        'group': c.groupID?.isNotEmpty == true,
        'memberCount': logic.groupInfo?.memberCount,
        'syncStatus': logic.syncStatus.value.name,
        'receivedDuringEntry': (incoming[c.groupID] ?? 0) - beforeReceived,
        'announcementConfirmations':
            announcementConfirmations - beforeConfirmations,
        'audit': audit!.report(),
      };
      double p95(List<int> values) {
        if (values.isEmpty) return 0;
        values.sort();
        return values[
                math.min(values.length - 1, (values.length * .95).ceil() - 1)] /
            1000;
      }

      result.addAll({
        'frames': frames.length,
        'buildP95Ms':
            p95(frames.map((f) => f.buildDuration.inMicroseconds).toList()),
        'rasterP95Ms':
            p95(frames.map((f) => f.rasterDuration.inMicroseconds).toList()),
        'framesOver16ms': frames
            .where((f) =>
                f.buildDuration.inMicroseconds > 16667 ||
                f.rasterDuration.inMicroseconds > 16667)
            .length
      });
      binding.removeTimingsCallback(record);
      results.add(result);
      debugPrint('CHAT_LIVE_PROFILE ${jsonEncode(result)}');
      return logic;
    }

    await open(a, 'cold_first_entry');
    AppNavigator.startBackMain();
    await tester.pump(const Duration(milliseconds: 400));
    final groups = await OpenIM.iMManager.groupManager.getJoinedGroupList();
    final counts = {for (final g in groups) g.groupID: g.memberCount ?? 0};
    final candidates = feed.list
        .where(
            (c) => c.groupID?.isNotEmpty == true && (c.latestMsg?.seq ?? 0) > 0)
        .toList();
    candidates.sort(
        (x, y) => (counts[y.groupID] ?? 0).compareTo(counts[x.groupID] ?? 0));
    expect(candidates, isNotEmpty);
    final b = candidates.first;
    payload['availableGroups'] = groups.length;
    payload['largestMembership'] = counts.values.fold<int>(0, math.max);
    payload['selectedGroupMembers'] = counts[b.groupID];
    await open(b, 'group_first_entry');
    for (var i = 0; i < 6; i++) {
      await open(i.isEven ? b : a, 'rapid_switch_$i',
          holdMs: 80, interrupt: true);
    }
    liveText[b.groupID!] = {};
    final groupLogic = await open(b, 'continuous_group',
        holdMs: const int.fromEnvironment('CHAT_LIVE_HOLD_MS',
            defaultValue: 60000));
    final endSeq =
        groupLogic.messageList.map((m) => m.seq ?? 0).fold<int>(0, math.max);
    payload['selectedGroupReceivedTotal'] = incoming[b.groupID] ?? 0;
    payload['selectedGroupUniqueLiveSeqs'] =
        liveSequences[b.groupID]?.length ?? 0;
    payload['displayedLastSeq'] = endSeq;
    final displayed = groupLogic.messageList.map((m) => m.clientMsgID).toSet();
    payload['liveTextReceivedDuringGroup'] = liveText[b.groupID]?.length ?? 0;
    payload['liveTextMissingFromGroupWindow'] = liveText[b.groupID]
            ?.keys
            .where((id) => !displayed.contains(id))
            .length ??
        0;
    // Observe history reading while actual traffic continues, with no forced
    // return to the latest edge. Existing list scroll physics performs the move.
    if (groupLogic.scrollController.hasClients &&
        groupLogic.scrollController.position.maxScrollExtent > 300) {
      groupLogic.scrollController.jumpTo(250);
      await tester.pump(const Duration(milliseconds: 500));
      audit = LiveChatAudit(groupLogic, audit!.root);
      final startOffset = groupLogic.scrollController.offset;
      final received = incoming[b.groupID] ?? 0;
      await tester.pump(const Duration(seconds: 15));
      payload['readingHistory'] = {
        'offsetBefore': startOffset,
        'offsetAfter': groupLogic.scrollController.offset,
        'received': (incoming[b.groupID] ?? 0) - received,
        'audit': audit!.report()
      };
      expect(groupLogic.scrollController.offset, closeTo(startOffset, 1),
          reason: 'incoming messages preserve the history reading anchor');
    }
    audit = null;
    if (reconnectProbe != null) {
      for (var i = 0; i < 3; i++) {
        final reconnect = reconnectProbe.reconnect();
        await tester.pump(Duration(milliseconds: i * 50));
        final logic = await open(i.isEven ? a : b, 'reconnect_diagnostic_$i',
            holdMs: 500, interrupt: true);
        final sample = results.removeLast();
        await reconnect;
        await waitUntil(() => logic.initialWindowReady.value);
        await tester.pump(const Duration(seconds: 3));
        sample['audit'] = audit!.report();
        reconnectSamples.add(sample);
      }
      payload['reconnectCompleted'] = true;
    }
    AppNavigator.startBackMain();
    await tester.pump(const Duration(milliseconds: 500));
    debugPrint('CHAT_LIVE_RESULT ${jsonEncode(payload)}');
    for (final row in [...results, ...reconnectSamples]) {
      final data = row['audit'] as Map<String, Object?>;
      if ((row['stagesMs'] as Map).containsKey('first_correct_message_frame')) {
        expect(data['paintSamples'], greaterThan(0),
            reason: '${row['case']} observed actual route');
      }
      for (final k in [
        'orderErrors',
        'duplicateErrors',
        'foreignRows',
        'relativeOrderChanges',
        'identityChanges',
        'prematureRows',
        'maxSequenceRegression'
      ]) {
        expect(data[k], 0, reason: '${row['case']} $k');
      }
      expect(data['maxUnexplainedShiftPx'], lessThanOrEqualTo(1),
          reason: '${row['case']} stable screen geometry');
    }
    expect(payload['liveTextMissingFromGroupWindow'], 0);
    payload['runCompleted'] = true;
  }, timeout: const Timeout(Duration(minutes: 5)));
}
