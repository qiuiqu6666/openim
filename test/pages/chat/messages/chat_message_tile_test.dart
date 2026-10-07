import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_tile.dart';
import 'package:openim/pages/chat/voice/voice_transcription_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:visibility_detector/visibility_detector.dart';

Message _message({bool voice = false}) => Message.fromJson({
      'clientMsgID': voice ? 'voice-tile' : 'text-tile',
      'contentType': voice ? MessageType.voice : MessageType.text,
      'sendID': 'me',
      'recvID': 'peer',
      'senderNickname': 'Me',
      'sessionType': ConversationType.single,
      'sendTime': 1700000000000,
      'isRead': true,
      'status': MessageStatus.succeeded,
      if (voice) 'soundElem': {'duration': 6},
      if (!voice) 'textElem': {'content': 'A real message tile'},
    });

/// Provides only the public UI facade. Constructing a real ChatLogic would
/// unnecessarily register route/SDK dependencies for a message-row test.
class _TileLogic extends GetxController implements ChatLogic {
  _TileLogic(Message message, {Future<String> Function()? transcript}) {
    messageList.add(message);
    voiceTranscriptions = VoiceTranscriptionController(
      transcribe: (_, {cancelToken}) =>
          transcript?.call() ?? Future.value('Recognized voice'),
    );
    voicePlayback = VoicePlaybackController(messages: () => messageList);
  }

  Message? repliedMessage;
  Message? collectedSticker;
  Message? collectedFavorite;
  bool showCollectionActions = false;
  final readVisibility = <bool>[];

  @override
  final conversationInfo = ConversationInfo(conversationID: 'chat-peer');

  @override
  final messageList = <Message>[].obs;
  @override
  final scaleFactor = 1.0.obs;
  @override
  final copyTextMap = <String?, String?>{};
  @override
  final sendStatusSub = PublishSubject<MsgStreamEv<bool>>();
  @override
  late final VoicePlaybackController voicePlayback;
  @override
  late final VoiceTranscriptionController voiceTranscriptions;
  @override
  bool get isSingleChat => true;
  @override
  bool get isGroupChat => false;
  @override
  bool get isOfficialNotificationChat => false;
  @override
  String? get senderName => 'Me';
  @override
  ValueKey itemKey(Message message) => ValueKey(message.clientMsgID!);
  @override
  Map<String, String> getAtMapping(Message message) => {};
  @override
  String? getShowTime(Message message) => null;
  @override
  String? getNewestNickname(Message message) => message.senderNickname;
  @override
  String? getNewestFaceURL(Message message) => null;
  @override
  bool canForward(Message message) => message.contentType == MessageType.text;
  @override
  bool canFavorite(Message message) => showCollectionActions;
  @override
  bool canAddMessageToStickers(Message message) => showCollectionActions;
  @override
  Future<void> addMessageToStickers(Message message) async =>
      collectedSticker = message;
  @override
  Future<void> favoriteMessage(Message message) async =>
      collectedFavorite = message;
  @override
  bool canRevoke(Message message) => false;
  @override
  bool canTranscribeVoice(Message message) =>
      voiceTranscriptions.canTranscribe(message);
  @override
  VoiceTranscriptionState? displayedVoiceTranscription(Message message) {
    final state = voiceTranscriptions.stateFor(message);
    return state.loading || state.hasText || state.error != null ? state : null;
  }

  @override
  Future<void> transcribeVoice(Message message) =>
      voiceTranscriptions.transcribe(message);
  @override
  void replyToMessage(Message message) => repliedMessage = message;
  @override
  void markMessageAsRead(Message message, bool visible) =>
      readVisibility.add(visible);
  @override
  void setFundMessageVisible(Message message, bool visible) {}
  @override
  void onTapRightAvatar() {}
  @override
  void clickLinkText(String url, Object? type) {}

  void disposeFixture() {
    voiceTranscriptions.dispose();
    voicePlayback.dispose();
    sendStatusSub.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
    WidgetTester tester, _TileLogic logic, Message message) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData.light(),
      home: Scaffold(
        body: ChatMessageTile(logic: logic, message: message),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: 'Me');
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(Get.reset);

  for (final exit in ['back', 'drag', 'interrupted']) {
    testWidgets(
        'returning photo keeps the decoded bubble on every frame / $exit',
        (tester) async {
      final file = File('openim_common/assets/images/ic_archive_99chat.png');
      final message = _message()
        ..clientMsgID = 'picture-tile'
        ..contentType = MessageType.picture
        ..pictureElem = PictureElem(
          sourcePath: file.path,
          sourcePicture: PictureInfo(width: 120, height: 200),
        );
      final logic = _TileLogic(message);
      addTearDown(logic.disposeFixture);
      await _mount(tester, logic, message);
      final bubble = find.descendant(
          of: find.byType(ChatMessageTile),
          matching: find.byType(ChatPictureView));
      final bubbleImage =
          find.descendant(of: bubble, matching: find.byType(ExtendedImage));
      await tester.runAsync(() async {
        expect(await file.exists(), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      await tester.pump();
      expect(bubble, findsOneWidget);
      expect(tester.widget<ChatPictureView>(bubble).isISend, isTrue);
      expect(
          tester
              .widget<ChatPictureView>(bubble)
              .message
              .pictureElem!
              .sourcePath,
          file.path);
      expect(bubbleImage, findsOneWidget);
      for (var attempt = 0; attempt < 30; attempt++) {
        if ((tester.state(bubbleImage) as ExtendedImageState)
                .extendedImageInfo !=
            null) {
          break;
        }
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final stateBeforeReturn = tester.state(bubble);
      final imageBeforeReturn =
          (tester.state(bubbleImage) as ExtendedImageState)
              .extendedImageInfo!
              .image;
      final navigator = Navigator.of(tester.element(bubble));
      navigator.push(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (_, __, ___) => MediaBrowser(initialIndex: 0, sources: [
          MediaSource(file: file, thumbnail: '', tag: message.clientMsgID),
        ]),
      ));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      if (exit == 'interrupted') {
        await tester.pump(const Duration(milliseconds: 100));
      } else {
        await tester.pumpAndSettle();
      }
      if (exit == 'drag') {
        final slide = tester.state<ExtendedImageSlidePageState>(
            find.byType(ExtendedImageSlidePage));
        slide.slide(Offset(0, slide.pageSize.height / 2));
        slide.endSlide(ScaleEndDetails());
      } else {
        navigator.pop();
      }
      await tester.pump();
      for (var frame = 0; frame < 21; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.state(bubble), same(stateBeforeReturn),
            reason: 'Landing must not restart the bubble file check');
        expect(bubbleImage, findsOneWidget);
        expect(
            (tester.state(bubbleImage) as ExtendedImageState)
                .extendedImageInfo!
                .image,
            same(imageBeforeReturn),
            reason: 'The already decoded picture must survive landing');
      }
      expect(find.byType(MediaBrowser), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('text tile renders its DTO and delegates the real reply menu',
      (tester) async {
    final message = _message();
    final logic = _TileLogic(message);
    addTearDown(logic.disposeFixture);
    await _mount(tester, logic, message);

    expect(find.byType(ChatMessageTile), findsOneWidget);
    expect(find.text('A real message tile'), findsOneWidget);
    // A tile cannot determine whether the latest conversation message was
    // painted. Reads belong to ChatListViewport, including oversized bubbles.
    expect(logic.readVisibility, isEmpty);
    await tester.longPress(find.text('A real message tile'));
    await tester.pumpAndSettle();
    expect(find.text(StrRes.menuReply), findsOneWidget);
    await tester.tap(find.text(StrRes.menuReply));
    await tester.pumpAndSettle();
    expect(logic.repliedMessage, same(message));
    expect(find.text(StrRes.menuReply), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('collection menu labels delegate and dismiss the menu',
      (tester) async {
    final message = _message();
    final logic = _TileLogic(message)..showCollectionActions = true;
    addTearDown(logic.disposeFixture);
    await _mount(tester, logic, message);
    await tester.longPress(find.text('A real message tile'));
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('添加到表情'), findsOneWidget);
    await tester.tap(find.text('添加到表情'));
    await tester.pumpAndSettle();
    expect(logic.collectedSticker, same(message));
    expect(find.text('添加到表情'), findsNothing);
    await tester.longPress(find.text('A real message tile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(logic.collectedFavorite, same(message));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('voice tile listens to transcription completion and collapse',
      (tester) async {
    // Folding is available only when the result exceeds the three-line preview.
    const transcript = 'First line.\nSecond line.\nThird line.\nFourth line.';
    final message = _message(voice: true);
    final answer = Completer<String>();
    final logic = _TileLogic(message, transcript: () => answer.future);
    addTearDown(logic.disposeFixture);
    await _mount(tester, logic, message);

    await tester.longPress(find.byType(ChatBubble));
    await tester.pumpAndSettle();
    await tester.tap(find.text('转文字'));
    await tester.pump();
    expect(find.text('转文字中…'), findsOneWidget);
    answer.complete(transcript);
    await tester.pumpAndSettle();
    expect(find.text(transcript), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).maxLines,
        isNull);
    await tester.tap(find.text('收起文字'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).maxLines, 3);
    expect(find.text('展开文字'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
