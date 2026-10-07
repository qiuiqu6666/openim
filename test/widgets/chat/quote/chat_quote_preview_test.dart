import 'dart:convert';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/quote/chat_quote_card.dart';
import 'package:openim_common/src/widgets/chat/quote/chat_quote_content.dart';
import 'package:openim_common/src/widgets/chat/quote/chat_quote_thumbnail.dart';

import '../markdown/support/markdown_fixture.dart';

Message _picture({String? path, bool expired = false}) =>
    markdownMessage('', type: MessageType.picture, id: 'picture', extra: {
      'pictureElem': {if (path != null) 'sourcePath': path},
      if (expired) ...{
        'hasReadTime': DateTime.now()
            .subtract(const Duration(seconds: 10))
            .millisecondsSinceEpoch,
        'attachedInfoElem': {'isPrivateChat': true, 'burnDuration': 1},
      },
    });

Message _reply(Message original, {bool outgoing = true}) =>
    markdownMessage('回复正文',
        id: 'reply-${original.clientMsgID}',
        type: MessageType.quote,
        outgoing: outgoing,
        extra: {
          'quoteElem': {'text': '回复正文', 'quoteMessage': original.toJson()}
        });

Widget _bubble(Message message) =>
    ChatItemView(message: message, onTapUserProfile: (_) {});

void main() {
  setUp(setupMarkdownFixture);
  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    Get.reset();
  });

  test('quote summaries preserve message types and packet remarks', () {
    final packet = markdownMessage('', type: MessageType.custom, extra: {
      'customElem': {
        'data': jsonEncode({
          'orderID': 'packet-order',
          'biz': 'packet_normal',
          'currency': 'USDT',
          'amount': '1',
          'status': 'open',
          'remark': '恭喜发财，大吉大利',
        })
      },
    });
    expect(chatQuoteSummary(packet), contains('恭喜发财，大吉大利'));
    expect(chatQuoteSummary(_picture()), StrRes.picture);
    expect(chatQuoteSummary(markdownMessage('第一行\n\n第二行')), '第一行 第二行');
    final card = markdownMessage('', type: MessageType.card, extra: {
      'cardElem': {'userID': 'friend', 'nickname': '秋啊'},
    });
    expect(chatQuoteSummary(card), contains('秋啊'));
    expect(chatQuoteSummary(null), StrRes.message);
    expect(ChatQuoteThumbnail.supports(_picture(expired: true)), isFalse);
    expect(chatQuoteSummary(_picture(expired: true)), isNot(StrRes.picture));
  });

  for (final dark in [false, true]) {
    testWidgets('cancel reply preserves the focused draft ($dark)',
        (tester) async {
      final controller = TextEditingController(text: '未发送的草稿');
      final focus = FocusNode();
      var quoted = true;
      final message = markdownMessage('原消息');
      await mountMarkdown(
          tester,
          StatefulBuilder(
              builder: (context, setState) => Column(
                    children: [
                      if (quoted)
                        ChatComposerContextPreview(
                            message: message,
                            onClose: () => setState(() => quoted = false)),
                      TextField(controller: controller, focusNode: focus),
                    ],
                  )),
          brightness: dark ? Brightness.dark : Brightness.light);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      controller.selection = const TextSelection.collapsed(offset: 3);
      await tester.tap(find.text('原消息'));
      await tester.pump();
      expect(quoted, isTrue);
      expect(focus.hasFocus, isTrue);
      final close = find.byKey(const ValueKey('chat-context-preview-close'));
      expect(tester.getSize(close).shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(close);
      await tester.pump();
      expect(quoted, isFalse);
      expect(controller.text, '未发送的草稿');
      expect(controller.selection.baseOffset, 3);
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      focus.dispose();
    });

    for (final width in [320.0, 812.0]) {
      testWidgets('quote cards and media fit large text ($dark, $width)',
          (tester) async {
        final original = markdownMessage('多行正文\n${'很长的引用内容' * 30}')
          ..senderNickname = '很长的群成员昵称' * 10;
        await mountMarkdown(
            tester,
            Column(children: [
              _bubble(_reply(original)),
              _bubble(_reply(_picture(), outgoing: false)),
              ChatComposerContextPreview(message: original, onClose: () {}),
              ChatComposerContextPreview(message: _picture(), onClose: () {}),
            ]),
            width: width,
            textScale: 2,
            brightness: dark ? Brightness.dark : Brightness.light);
        expect(find.byType(ChatQuoteCard), findsNWidgets(2));
        expect(find.byType(ChatQuoteThumbnail), findsNWidgets(2));
        final card = find.byType(ChatQuoteCard).first;
        final body = find.text('回复正文', findRichText: true).first;
        expect(tester.getBottomLeft(card).dy,
            lessThan(tester.getTopLeft(body).dy));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('export the reference-style quote states', (tester) async {
    await tester.runAsync(loadMarkdownPreviewFonts);
    const photo = String.fromEnvironment('CHAT_QUOTE_PREVIEW_IMAGE');
    if (photo.isNotEmpty) {
      await mountMarkdown(tester, const SizedBox());
      await tester.runAsync(() async {
        final thumbnail = ImageUtil.fileImage(
          file: File(photo),
          width: 40,
          height: 40,
          cacheWidth: 40,
          cacheHeight: 40,
          resizePolicy: ResizeImagePolicy.fit,
        ) as ExtendedImage;
        await precacheImage(
                thumbnail.image, tester.element(find.byType(Scaffold)))
            .timeout(const Duration(seconds: 10));
      });
    }
    final originals = [
      markdownMessage('', id: 'card', type: MessageType.card, extra: {
        'cardElem': {'userID': 'peer', 'nickname': '秋彬'},
      }),
      markdownMessage('', id: 'packet', type: MessageType.custom, extra: {
        'customElem': {
          'data': jsonEncode({
            'orderID': 'packet-order',
            'biz': 'packet_normal',
            'currency': 'USDT',
            'amount': '1',
            'status': 'open',
            'remark': '恭喜发财，大吉大利',
          })
        },
      }),
      _picture(path: photo.isEmpty ? null : photo),
      markdownMessage('京东积分小群${'～' * 40}', id: 'long'),
    ];
    for (final message in originals) {
      message.senderNickname = '南风_(现六合彩主管)_阿伦已忙其他不管事';
    }
    for (final dark in [false, true]) {
      await mountMarkdown(
          tester,
          Column(children: [
            for (final original in originals) _bubble(_reply(original)),
            const SizedBox(height: 24),
            ChatComposerContextPreview(message: originals[2], onClose: () {}),
            const ChatInputBox(toolbox: SizedBox(), voiceRecordBar: SizedBox()),
            const SizedBox(height: 24),
            ChatComposerContextPreview(message: originals.last, onClose: () {}),
            const ChatInputBox(toolbox: SizedBox(), voiceRecordBar: SizedBox()),
          ]),
          brightness: dark ? Brightness.dark : Brightness.light);
      await tester.pumpAndSettle();
      if (photo.isNotEmpty) {
        final images = tester
            .stateList(find.descendant(
                of: find.byType(ChatQuoteThumbnail),
                matching: find.byType(ExtendedImage)))
            .cast<ExtendedImageState>();
        expect(images, hasLength(2));
        expect(images.map((image) => image.extendedImageLoadState),
            everyElement(LoadState.completed));
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() =>
          saveMarkdownPreview(tester, 'quote-${dark ? 'dark' : 'light'}'));
    }
  }, skip: markdownPreviewDirectory.isEmpty);
}
