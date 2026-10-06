import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/ai_assistant_chat_page.dart';
import 'package:openim/pages/ai_assistant/presentation/messages/ai_assistant_text.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../pages/ai_assistant/openim/support/ai_openim_test_fixture.dart';
import '../../pages/ai_assistant/presentation/support/ai_ui_test_host.dart';

/// Characterizes motion and a stable short-history control from the read-only
/// audit. Movement assertions should be inverted when those issues are fixed.
/// Real widgets and the existing SDK fixture are used, without HTTP.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeAiUiTests();
    PackageInfo.setMockInitialValues(
      appName: '99Chat',
      packageName: 'test.openim',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    await Config.init(() {});
  });

  for (final dark in [false, true]) {
    for (final longHistory in [false, true]) {
      testWidgets(
          'audit: SDK typing geometry without a new message '
          '(${dark ? 'dark' : 'light'}, ${longHistory ? 'full' : 'short'} history)',
          (tester) async {
        final fixture = AiOpenimTestFixture();
        await fixture.initialize();
        try {
          final logic = fixture.open();
          await tester.idle();
          fixture.histories.single.complete([
            if (longHistory)
              for (var i = 1; i <= 24; i++)
                aiOpenimText('old-$i', 'Existing historical message $i.',
                    time: i),
            aiOpenimText('unchanged-message', 'A message already on screen.',
                time: 30),
          ]);
          await AiUiTestHost(dark: dark, disableAnimations: true)
              .mount(tester, AiAssistantChatPage(logic: logic));

          final bubble = find.byWidgetPredicate((widget) =>
              widget is AiAssistantMarkdown &&
              widget.text == 'A message already on screen.');
          final timeline = find.byType(ChatMessageList);
          expect(bubble, findsOneWidget);
          final beforeBubble = tester.getRect(bubble);
          final beforeTimeline = tester.getRect(timeline);
          final messageIDs =
              logic.messageList.map((message) => message.clientMsgID).toList();

          fixture.im.recvNewMessage(aiOpenimTyping('transient-typing-yes'));
          await tester.pump();
          await tester.pump();
          final typingBubble = tester.getRect(bubble);
          final typingTimeline = tester.getRect(timeline);

          expect(logic.peerTyping.value, isTrue);
          expect(logic.messageList.map((message) => message.clientMsgID),
              messageIDs);
          expect(beforeTimeline.height - typingTimeline.height, greaterThan(16),
              reason: 'The typing card currently consumes timeline height.');
          debugPrint('motion audit AI typing: dark=$dark long=$longHistory '
              'timeline delta=${typingTimeline.height - beforeTimeline.height}, '
              'bubble delta=${typingBubble.top - beforeBubble.top}');
          if (longHistory) {
            expect(beforeBubble.top - typingBubble.top, greaterThan(16),
                reason: 'A full reverse timeline follows its moving bottom.');
          } else {
            expect(typingBubble.top, closeTo(beforeBubble.top, .5),
                reason:
                    'The adaptive viewport keeps short histories at the top.');
          }

          fixture.im.recvNewMessage(
              aiOpenimTyping('transient-typing-no', tips: 'no'));
          await tester.pump();
          await tester.pump();
          expect(logic.peerTyping.value, isFalse);
          expect(tester.getRect(timeline).height,
              closeTo(beforeTimeline.height, .5));
          expect(tester.getRect(bubble).top, closeTo(beforeBubble.top, .5));
          expect(logic.messageList.map((message) => message.clientMsgID),
              messageIDs);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          for (final logic in fixture.controllers.reversed) {
            if (!logic.isClosed) logic.onDelete();
          }
          await tester.pump(const Duration(milliseconds: 600));
          await dismissAiUiTestLoading();
          await fixture.dispose();
        }
      });
    }
  }

  testWidgets(
      'audit: decoded private Markdown image replaces a different ratio',
      (tester) async {
    final files = <String, Uint8List>{};
    final requested = <String>[];
    late StateSetter rebuild;
    final host = AiUiTestHost(disableAnimations: true);
    try {
      await host.mount(
        tester,
        host.scaffold((_) => Center(
              child: SizedBox(
                width: 200,
                child: StatefulBuilder(builder: (context, setState) {
                  rebuild = setState;
                  return AiAssistantMarkdown(
                    dark: false,
                    text:
                        '![image](/ai-assistant/api/v1/chat/files/audit-image)',
                    fileCache: files,
                    onNeedFile: requested.add,
                  );
                }),
              ),
            )),
        settle: false,
      );
      final markdown = find.byType(AiAssistantMarkdown);
      final before = tester.getSize(markdown);
      expect(requested, contains('audit-image'));

      // Encode with the engine used by this test, so the PNG is valid for the
      // same decoder. Its deterministic square ratio differs from 16:10.
      final bytes = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 16, 16), Paint());
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 16);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return data!.buffer.asUint8List();
        } finally {
          image.dispose();
          picture.dispose();
        }
      }))!;
      await tester.runAsync(
          () => precacheImage(MemoryImage(bytes), tester.element(markdown)));
      rebuild(() => files['audit-image'] = bytes);
      await tester.pump();
      await tester.pump();

      final after = tester.getSize(markdown);
      debugPrint('motion audit Markdown image: before=$before after=$after');
      expect(after.width, closeTo(before.width, .5));
      expect(after.height - before.height, greaterThan(60),
          reason: 'The waiting 16:10 slot becomes a square decoded image.');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await resetAiUiTests();
    }
  });
}
