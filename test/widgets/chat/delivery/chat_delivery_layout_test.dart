import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/res/typography/chat_message_typography.dart';

import '../markdown/support/markdown_fixture.dart';

const _messageText = '15312312';

Message _message({required bool sending, bool read = false}) => markdownMessage(
      _messageText,
      outgoing: true,
      extra: {
        'status': sending ? MessageStatus.sending : MessageStatus.succeeded,
        'isRead': read,
      },
    );

Map<String, Rect> _geometry(WidgetTester tester) => {
      'bubble': tester.getRect(find.byType(ChatBubble)),
      'text': tester.getRect(find.descendant(
        of: find.byType(MatchTextView),
        matching: find.byType(RichText),
      )),
      'time': tester.getRect(find.text('14:08')),
    };

void _expectGeometry(
  WidgetTester tester,
  Map<String, Rect> initial,
  String phase,
) {
  final current = _geometry(tester);
  for (final part in initial.keys) {
    expect(current[part], initial[part],
        reason: '$part must stay in place during $phase');
  }
}

void main() {
  setUp(setupMarkdownFixture);
  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0]) {
      for (final withTransfer in [true, false]) {
        final scenario =
            '${brightness.name} width=$width transfer=$withTransfer';

        Future<
                ({
                  ValueChanged<Message> updateMessage,
                  ValueNotifier<ChatTransferStatus?> transfer
                })>
            mountSending(WidgetTester tester, {bool preview = false}) async {
          var message = _message(sending: true);
          late StateSetter rebuild;
          final transfer = ValueNotifier<ChatTransferStatus?>(null);
          addTearDown(transfer.dispose);
          await mountMarkdown(
            tester,
            StatefulBuilder(builder: (_, setState) {
              rebuild = setState;
              return ChatItemView(
                  message: message,
                  transferStatus: withTransfer ? transfer : null,
                  // Chat body text deliberately does not inherit Theme fonts.
                  textContentBuilder: preview
                      ? (context, message) => ChatText(
                            isISend: true,
                            text: message.textElem!.content!,
                            textStyle: chatMessageTextStyle(context)
                                .copyWith(fontFamily: 'MarkdownPreviewFont'),
                          )
                      : null,
                  onTapUserProfile: (_) {});
            }),
            brightness: brightness,
            width: width,
          );
          return (
            updateMessage: (value) => rebuild(() => message = value),
            transfer: transfer
          );
        }

        testWidgets('delivery changes preserve bubble geometry $scenario',
            (tester) async {
          final exportPreview = markdownPreviewDirectory.isNotEmpty &&
              brightness == Brightness.light &&
              width == 390 &&
              withTransfer;
          if (exportPreview) {
            await tester.runAsync(loadMarkdownPreviewFonts);
          }
          final state = await mountSending(tester, preview: exportPreview);
          final initial = _geometry(tester);
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          expect(find.byType(ChatReadReceiptIcon), findsNothing);
          if (exportPreview) {
            await tester.runAsync(
                () => saveMarkdownPreview(tester, 'delivery-waiting'));
          }

          // A transfer update must preserve the pending indicator's delay.
          state.transfer.value =
              const ChatTransferStatus(ChatTransferStage.confirming);
          await tester.pump(const Duration(milliseconds: 800));
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          _expectGeometry(tester, initial, 'the hidden sending indicator');

          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
          _expectGeometry(tester, initial, 'the visible sending indicator');
          if (exportPreview) {
            await tester.runAsync(
                () => saveMarkdownPreview(tester, 'delivery-spinner'));
          }

          state.updateMessage(_message(sending: false));
          await tester.pump();
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          expect(
              tester
                  .widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon))
                  .isRead,
              isFalse);
          _expectGeometry(tester, initial, 'the sent receipt');
          if (exportPreview) {
            await tester
                .runAsync(() => saveMarkdownPreview(tester, 'delivery-sent'));
          }

          state.updateMessage(_message(sending: false, read: true));
          await tester.pump();
          expect(
              tester
                  .widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon))
                  .isRead,
              isTrue);
          _expectGeometry(tester, initial, 'the read receipt');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });

        testWidgets('fast delivery never flashes or shifts $scenario',
            (tester) async {
          final state = await mountSending(tester);
          final initial = _geometry(tester);
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          _expectGeometry(tester, initial, 'fast sending');

          state.updateMessage(_message(sending: false));
          await tester.pump();
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          expect(find.byType(ChatReadReceiptIcon), findsOneWidget);
          _expectGeometry(tester, initial, 'fast delivery');

          // The cancelled sending timer must not reappear after success.
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          _expectGeometry(tester, initial, 'the old sending deadline');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
