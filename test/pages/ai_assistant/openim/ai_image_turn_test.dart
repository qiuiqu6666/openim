import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/ai_assistant/attachments/ai_image_turn_sender.dart';
import 'package:openim/pages/ai_assistant/models/ai_assistant_models.dart';
import 'package:openim/pages/ai_assistant/protocol/ai_image_turn.dart';
import 'package:openim/pages/ai_assistant/history/ai_openim_message_text.dart';
import 'package:openim/pages/ai_assistant/presentation/messages/ai_image_turn_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final files = [
    for (var i = 0; i < 2; i++)
      AiAssistantFileRef(
          name: '$i.png',
          sizeLabel: '',
          kind: AiAssistantFileKind.image,
          localPath: '/$i.png')
  ];
  Future<List<PublicUserInfo>> profiles() async =>
      [PublicUserInfo(userID: 'assistant', ex: '{"assistantTurnVersion":1}')];
  Future<Message> picture(String path) async => Message(
      pictureElem: PictureElem(
          sourcePicture: PictureInfo(url: 'https://example.com$path')));

  test('all uploads complete before creating exactly one combined message',
      () async {
    var uploads = 0;
    var creates = 0;
    final gate = Completer<void>();
    final secondStarted = Completer<void>();
    final sender = AiImageTurnSender(
        isCurrent: () => true,
        profiles: profiles,
        preparePicture: picture,
        upload: (_) async {
          uploads++;
          if (uploads == 2) {
            secondStarted.complete();
            await gate.future;
          }
        },
        create: (data) async {
          creates++;
          return Message(
              contentType: MessageType.custom,
              customElem:
                  CustomElem(description: AiImageTurn.description, data: data));
        });
    final pending = sender.prepare('比较这两张图\n有什么不同', files);
    await secondStarted.future;
    expect(creates, 0);
    gate.complete();
    final message = await pending;
    final turn = AiImageTurn.parse(message.customElem!.data)!;
    expect(creates, 1);
    expect(turn.images.map((i) => i.url),
        ['https://example.com/0.png', 'https://example.com/1.png']);
    expect(turn.text, '比较这两张图\n有什么不同');
    expect(turn.turnID.length, 36);
    expect(aiOpenimMessageText(message), turn.text);
  });
  test('failed second upload submits neither image nor text', () async {
    var uploads = 0;
    var creates = 0;
    final sender = AiImageTurnSender(
        isCurrent: () => true,
        profiles: profiles,
        preparePicture: picture,
        upload: (_) async {
          if (++uploads == 2) throw StateError('upload');
        },
        create: (_) async {
          creates++;
          return Message();
        });
    await expectLater(sender.prepare('compare', files), throwsStateError);
    expect(creates, 0);
  });
  test('old server fails before uploads rather than splitting messages',
      () async {
    var uploads = 0;
    final sender = AiImageTurnSender(
        isCurrent: () => true,
        profiles: () async => [],
        preparePicture: picture,
        upload: (_) async {
          uploads++;
        });
    await expectLater(sender.prepare('compare', files),
        throwsA(isA<AiImageTurnUnsupported>()));
    expect(uploads, 0);
  });
  test('session change during upload cancels the entire question', () async {
    var current = true;
    var creates = 0;
    final sender = AiImageTurnSender(
        isCurrent: () => current,
        profiles: profiles,
        preparePicture: picture,
        upload: (_) async {
          current = false;
        },
        create: (_) async {
          creates++;
          return Message();
        });
    await expectLater(sender.prepare('compare', files), throwsStateError);
    expect(creates, 0);
  });
  test('malformed and unsupported envelopes are rejected', () {
    expect(AiImageTurn.parse('not json'), isNull);
    expect(AiImageTurn.parse('{"version":2}'), isNull);
    expect(AiImageTurn.supported('{}'), isFalse);
  });

  test('reference generation preserves intent and images in one message',
      () async {
    var creates = 0;
    final sender = AiImageTurnSender(
        isCurrent: () => true,
        profiles: () async => [
              PublicUserInfo(
                  userID: 'assistant',
                  ex: '{"assistantTurnVersion":1,"assistantImageEditVersion":1}')
            ],
        preparePicture: picture,
        upload: (_) async {},
        create: (data) async {
          creates++;
          return Message(customElem: CustomElem(data: data));
        });
    final message =
        await sender.prepare('参考这个生成一张图', files, generateImage: true);
    final turn = AiImageTurn.parse(message.customElem!.data)!;
    expect(turn.generateImage, isTrue);
    expect(turn.text, '参考这个生成一张图');
    expect(turn.images.length, 2);
    expect(creates, 1);
  });

  test(
      'vision-only servers cannot silently turn image generation into description',
      () async {
    var uploads = 0;
    final sender = AiImageTurnSender(
        isCurrent: () => true,
        profiles: profiles,
        preparePicture: picture,
        upload: (_) async {
          uploads++;
        });
    await expectLater(sender.prepare('参考这个生成一张图', files, generateImage: true),
        throwsA(isA<AiImageTurnUnsupported>()));
    expect(uploads, 0);
  });

  testWidgets(
      'combined message keeps text and both accessible previews in a narrow bubble',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
          width: 220,
          child: AiImageTurnMessage(
              turn: AiImageTurn(
                  turnID: 'test-turn-00000001',
                  text: '比较这两张图片',
                  images: [
                (url: 'https://example.com/1.png', name: '1.png'),
                (url: 'https://example.com/2.png', name: '2.png'),
              ]))),
    ))));
    await tester.pump();
    expect(find.text('比较这两张图片'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(2));
    final first = tester.getRect(find.byType(InkWell).at(0));
    final second = tester.getRect(find.byType(InkWell).at(1));
    expect(first.top, second.top);
    expect(second.left - first.right, 8);
    expect(first.width, greaterThanOrEqualTo(48));
    expect(tester.getTopLeft(find.text('比较这两张图片')).dx, first.left);
    expect(find.bySemanticsLabel(RegExp('.*1')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('.*2')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('single image uses a compact filled preview above its caption',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topRight,
      child: AiImageTurnMessage(
          turn:
              AiImageTurn(turnID: 'test-turn-00000001', text: '这个是什么', images: [
        (url: 'https://example.com/1.png', name: '1.png'),
      ])),
    ))));
    await tester.pump();
    final preview = tester.getRect(find.byType(InkWell));
    final caption = tester.getRect(find.text('这个是什么'));
    expect(preview.width, 240);
    expect(preview.height, 300);
    expect(caption.left, preview.left);
    expect(caption.top - preview.bottom, 10);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });
}
