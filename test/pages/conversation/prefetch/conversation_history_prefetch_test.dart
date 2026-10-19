import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:openim/pages/conversation/prefetch/conversation_history_prefetch.dart';

void main() {
  setUp(() {
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.token = 'token';
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(() {
    VisibilityDetectorController.instance.updateInterval =
        const Duration(milliseconds: 500);
  });

  testWidgets('only visible rows warm, with two simultaneous reads',
      (tester) async {
    final pending = <Completer<void>>[];
    final ids = <String>[];
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                height: 210,
                child: ConversationHistoryPrefetch(
                    active: true,
                    sessionCurrent: () => true,
                    warmLocal: (info) {
                      ids.add(info.conversationID);
                      final done = Completer<void>();
                      pending.add(done);
                      return done.future;
                    },
                    child: ListView.builder(
                        controller: scroll,
                        itemExtent: 100,
                        itemCount: 100,
                        itemBuilder: (_, i) => ConversationHistoryPrefetchItem(
                            conversation:
                                ConversationInfo(conversationID: '$i'),
                            child: Text('row $i'))))))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(ids, ['0', '1']);
    pending[0].complete();
    await tester.pump();
    expect(ids, ['0', '1', '2']);
    pending[1].complete();
    pending[2].complete();
    await tester.pump(const Duration(seconds: 1));
    expect(ids, ['0', '1', '2'],
        reason: 'cache-extent rows must not start reads');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a screen of small rows is capped at eight; inactive feed stays quiet',
      (tester) async {
    final ids = <String>[];
    Widget view(bool active) => MaterialApp(
        home: Scaffold(
            body: ConversationHistoryPrefetch(
                active: active,
                sessionCurrent: () => true,
                warmLocal: (info) async {
                  ids.add(info.conversationID);
                },
                child: ListView.builder(
                    itemExtent: 20,
                    itemCount: 100,
                    itemBuilder: (_, i) => ConversationHistoryPrefetchItem(
                        conversation: ConversationInfo(conversationID: '$i'),
                        child: Text('$i'))))));
    await tester.pumpWidget(view(false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(ids, isEmpty);
    await tester.pumpWidget(view(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(ids.length, 8);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('hiding the feed stops queued reads; disposal cancels delay',
      (tester) async {
    final pending = Completer<void>();
    var count = 0;
    Widget view(bool active) => MaterialApp(
        home: Scaffold(
            body: ConversationHistoryPrefetch(
                active: active,
                sessionCurrent: () => true,
                warmLocal: (_) {
                  count++;
                  return pending.future;
                },
                child: ListView(children: [
                  for (var i = 0; i < 8; i++)
                    ConversationHistoryPrefetchItem(
                        conversation: ConversationInfo(conversationID: '$i'),
                        child: SizedBox(height: 30, child: Text('$i')))
                ]))));
    await tester.pumpWidget(view(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(count, 2);
    await tester.pumpWidget(view(false));
    pending.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 2);
    await tester.pumpWidget(view(true));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(count, 2);
    expect(tester.takeException(), isNull);
  });
}
