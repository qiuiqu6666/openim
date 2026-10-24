import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openim/main.dart' as app;
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/media/upload/chat_media_outbox.dart';
import 'package:openim/pages/chat/media/upload/chat_media_upload.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_tile.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim/services/favorite_send_coordinator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path_provider/path_provider.dart';

// Real account, SDK, media upload and route lifecycle. No platform fakes.
// Requires an explicitly authorized exact conversation name; never picks first.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('real picture recall survives route reentry', (tester) async {
    const target = String.fromEnvironment('RECALL_TEST_CONVERSATION');
    expect(target.trim(), isNotEmpty);
    final results = <Map<String, Object?>>[];
    final report = <String, Object?>{'completed': false, 'results': results};
    binding.reportData = report;
    void phase(String value) {
      report['phase'] = value;
      debugPrint('RECALL_DEVICE_PHASE $value');
    }

    Future<void> waitFor(bool Function() ready, {int seconds = 30}) async {
      final clock = Stopwatch()..start();
      while (!ready() && clock.elapsed < Duration(seconds: seconds)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ready(), isTrue, reason: 'Real-device condition timed out');
    }

    final errorHandler = FlutterError.onError;
    phase('awaiting_login');
    app.main();
    FlutterError.onError = errorHandler;
    await waitFor(
        () =>
            Get.isRegistered<ConversationLogic>() &&
            Get.currentRoute == AppRoutes.home,
        seconds: 300);
    final feed = Get.find<ConversationLogic>();
    await waitFor(() => feed.list.any((c) => c.showName == target));
    phase('destination_resolved');
    final matches = feed.list.where((c) => c.showName == target).toList();
    expect(matches, hasLength(1), reason: 'Destination must be unambiguous');
    final conversationID = matches.single.conversationID;
    final account = OpenIM.iMManager.userID;
    final token = OpenIM.iMManager.token;
    void checkSession() {
      expect(OpenIM.iMManager.userID, account);
      expect(OpenIM.iMManager.token, token);
    }

    final recalled = <String>{};
    var sampling = true;
    var samples = 0, staleRows = 0, staleTiles = 0;
    binding.addPersistentFrameCallback((_) {
      if (!sampling) return;
      binding.addPostFrameCallback((_) {
        if (!sampling) return;
        for (final e in find.byType(ChatMessageList).evaluate()) {
          final logic = (e.widget as ChatMessageList).logic;
          if (logic.conversationInfo.conversationID != conversationID) continue;
          samples++;
          for (final m in logic.messageList) {
            if (recalled.contains(m.clientMsgID) &&
                (m.contentType == MessageType.picture ||
                    m.pictureElem != null)) {
              staleRows++;
            }
          }
        }
        for (final e in find.byType(ChatMessageTile).evaluate()) {
          final m = (e.widget as ChatMessageTile).message;
          if (recalled.contains(m.clientMsgID) &&
              (m.contentType == MessageType.picture || m.pictureElem != null)) {
            staleTiles++;
          }
        }
      });
    });
    addTearDown(() => sampling = false);
    ChatLogic? active() {
      final elements = find.byType(ChatMessageList).evaluate();
      for (final e in elements) {
        final logic = (e.widget as ChatMessageList).logic;
        if (!logic.isClosed &&
            logic.conversationInfo.conversationID == conversationID &&
            ModalRoute.of(e)?.isCurrent == true) {
          return logic;
        }
      }
      return null;
    }

    Future<ChatLogic> open() async {
      checkSession();
      final c =
          feed.list.singleWhere((c) => c.conversationID == conversationID);
      unawaited(AppNavigator.startChat<void>(conversationInfo: c));
      await waitFor(() => active() != null);
      final logic = active()!;
      await waitFor(() => logic.initialWindowReady.value);
      return logic;
    }

    Future<void> back() async {
      AppNavigator.startBackMain();
      await waitFor(
          () => Get.currentRoute == AppRoutes.home && active() == null);
      await tester.pump(const Duration(milliseconds: 350));
    }

    final bytes = await rootBundle.load('assets/img/99chat_logo.png');
    final temp = await getTemporaryDirectory();
    final file = File(
        '${temp.path}/recall-regression-${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });

    for (final leavePending in [false, true]) {
      phase(leavePending ? 'immediate_exit_send' : 'confirmed_exit_send');
      final logic = await open();
      final before = logic.messageList.map((m) => m.clientMsgID).toSet();
      // Exercise the album's real outbox/upload/SDK path. sendPicture alone
      // uses direct delivery and cannot reproduce the retained-outbox defect.
      final destination =
          feed.list.singleWhere((c) => c.conversationID == conversationID);
      final task = ChatMediaOutbox.instance.accept(FavoriteTarget(
          conversationID: conversationID,
          userID: destination.userID,
          groupID: destination.groupID,
          sessionType: destination.conversationType));
      final outgoing = await OpenIM.iMManager.messageManager
          .createImageMessageFromFullPath(imagePath: file.path);
      task.stage(outgoing);
      await ChatMediaUpload(
              isClosed: () => !task.current, onTransfer: task.transfer)
          .prepare(outgoing);
      await task.send(outgoing);
      await waitFor(
          () => logic.messageList.any((m) =>
              !before.contains(m.clientMsgID) &&
              m.sendID == account &&
              m.contentType == MessageType.picture &&
              m.status == MessageStatus.succeeded),
          seconds: 90);
      final photo = logic.messageList.singleWhere((m) =>
          !before.contains(m.clientMsgID) &&
          m.sendID == account &&
          m.contentType == MessageType.picture);
      final id = photo.clientMsgID!;
      await waitFor(() => logic.canRevoke(photo));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
          find.byWidgetPredicate((w) =>
              w is ChatMessageTile &&
              w.message.clientMsgID == id &&
              w.message.contentType == MessageType.picture),
          findsOneWidget,
          reason: 'Original picture must actually mount before recall');
      await binding.takeScreenshot(
          '${leavePending ? 'immediate' : 'confirmed'}_before_recall');
      var completed = false;
      var disposedBeforeCompletion = false;
      final request = logic.revokeMessage(photo).whenComplete(() {
        completed = true;
        disposedBeforeCompletion = logic.isClosed;
      });
      await waitFor(() => find
          .byKey(const ValueKey('message-revoke-confirmation-sheet'))
          .evaluate()
          .isNotEmpty);
      final confirm =
          find.widgetWithText(CupertinoActionSheetAction, StrRes.menuRevoke);
      expect(confirm, findsOneWidget);
      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 16));
      final pendingAtExit = !completed;
      if (leavePending) await back();
      await request;
      // Do not query history here: that read could repair stale storage and
      // hide the entry defect. Check only the already accepted recall fact.
      expect(ChatHistoryCache.applyRevocation(account, photo).contentType,
          MessageType.revokeMessageNotification);
      recalled.add(id);
      phase(
          leavePending ? 'immediate_exit_recalled' : 'confirmed_exit_recalled');
      if (!leavePending) await back();
      final initialSamples = samples;
      for (var entry = 0; entry < 5; entry++) {
        phase('${leavePending ? 'immediate' : 'confirmed'}_reentry_$entry');
        final reentered = await open();
        if (entry == 0) {
          await binding.takeScreenshot(
              '${leavePending ? 'immediate' : 'confirmed'}_first_reentry');
        }
        await tester.pump(Duration(milliseconds: entry == 4 ? 3000 : 500));
        expect(reentered.messageList.any((m) => m.clientMsgID == id), isTrue);
        expect(
            find.byWidgetPredicate((w) =>
                w is ChatMessageTile &&
                w.message.clientMsgID == id &&
                w.message.contentType == MessageType.revokeMessageNotification),
            findsOneWidget);
        expect(staleRows, 0);
        expect(staleTiles, 0);
        await back();
      }
      expect(samples, greaterThan(initialSamples));
      // Verify real SDK persistence; a swallowed/failed UI request is not success.
      final page = await OpenIM.iMManager.messageManager
          .getAdvancedHistoryMessageList(
              conversationID: conversationID, count: 40);
      final stored = page.messageList!.singleWhere((m) => m.clientMsgID == id);
      expect(stored.contentType, MessageType.revokeMessageNotification);
      expect(stored.pictureElem, isNull);
      results.add({
        'leaveImmediatelyAfterConfirmation': leavePending,
        'requestPendingBeforeExit': pendingAtExit,
        'routeDisposedBeforeRequestCompleted': disposedBeforeCompletion,
        'reentries': 5,
        'sampledFrames': samples - initialSamples,
        'staleRows': staleRows,
        'staleTiles': staleTiles,
        'nativeHistoryConfirmed': true
      });
    }
    phase('complete');
    report['completed'] = true;
  }, timeout: const Timeout(Duration(minutes: 12)));
}
