import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_controller.dart';
import 'package:openim/pages/chat/voice/voice_transcription_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

const markdownPreviewDirectory =
    String.fromEnvironment('CHAT_MARKDOWN_PREVIEW_DIR');
const markdownPreviewKey = ValueKey('markdown-preview');

Message markdownMessage(String text,
        {String id = 'markdown',
        int type = MessageType.text,
        bool outgoing = false,
        Map<String, dynamic> extra = const {}}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': type,
      'sendID': outgoing ? 'me' : 'peer',
      'recvID': outgoing ? 'peer' : 'me',
      'senderNickname': outgoing ? '我' : '聊天好友',
      'senderFaceUrl': '',
      'sessionType': ConversationType.single,
      'sendTime': DateTime(2026, 10, 6, 14, 8).millisecondsSinceEpoch,
      'status': MessageStatus.succeeded,
      'isRead': true,
      if (type == MessageType.text) 'textElem': {'content': text},
      if (type == MessageType.atText) 'atTextElem': {'text': text},
      if (type == MessageType.quote) 'quoteElem': {'text': text},
      if (type == MessageType.advancedText)
        'advancedTextElem': {'text': text, 'messageEntityList': []},
      ...extra,
    });

Future<void> setupMarkdownFixture() async {
  Get.testMode = true;
  OpenIM.iMManager.userID = 'me';
  OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: '我');
  SharedPreferences.setMockInitialValues({});
  await SpUtil().init();
}

Future<void> mountMarkdown(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light,
    double width = 375,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    bool scroll = true}) async {
  tester.view.physicalSize = Size(width, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previous = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = previous);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      builder: EasyLoading.init(),
      theme: ThemeData(
          brightness: brightness,
          fontFamily:
              markdownPreviewDirectory.isEmpty ? null : 'MarkdownPreviewFont',
          fontFamilyFallback: markdownPreviewDirectory.isEmpty
              ? null
              : const ['MarkdownPreviewFont', 'MarkdownPreviewArabic']),
      home: MediaQuery(
        data: MediaQueryData(
            size: Size(width, 960), textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: RepaintBoundary(
              key: markdownPreviewKey,
              child: Builder(
                builder: (context) => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: scroll
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: child)
                      : Center(
                          child: SizedBox(width: width - 32, child: child)),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

String renderedMarkdownText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((widget) => widget.text.toPlainText().replaceAll('\u200B', ''))
    .join('\n');

Future<void> loadMarkdownPreviewFonts() async {
  if (markdownPreviewDirectory.isEmpty) return;
  for (final entry in {
    'MarkdownPreviewFont': 'C:/Windows/Fonts/msyh.ttc',
    'MarkdownPreviewArabic': 'C:/Windows/Fonts/arial.ttf',
    'monospace': 'C:/Windows/Fonts/consola.ttf',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(Future.value(
          ByteData.sublistView(await File(entry.value).readAsBytes())));
    await loader.load();
  }
}

Future<void> saveMarkdownPreview(WidgetTester tester, String name) async {
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(markdownPreviewKey));
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('$markdownPreviewDirectory/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

class MarkdownTileLogic extends GetxController implements ChatLogic {
  MarkdownTileLogic(Message message) {
    messageList.add(message);
    messageSelection = MessageSelectionController(
        messages: () => messageList,
        isClosed: () => false,
        onStart: () {},
        deleteMessages: (_) async => true,
        forwardMessages: (_, {required merged}) async => false);
    voiceTranscriptions = VoiceTranscriptionController(
        transcribe: (_, {cancelToken}) async => '');
    voicePlayback = VoicePlaybackController(messages: () => messageList);
  }
  @override
  final messageList = <Message>[].obs;
  @override
  final scaleFactor = 1.0.obs;
  @override
  final copyTextMap = <String?, String?>{};
  @override
  final sendStatusSub = PublishSubject<MsgStreamEv<bool>>();
  @override
  late final MessageSelectionController messageSelection;
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
  String? get senderName => '我';
  @override
  ValueKey itemKey(Message message) => ValueKey(message.clientMsgID!);
  @override
  Map<String, String> getAtMapping(Message message) => {};
  @override
  String? getShowTime(Message message) => null;
  @override
  String? getNewestNickname(Message message) => message.senderNickname;
  @override
  String? getNewestFaceURL(Message message) => '';
  @override
  bool canForward(Message message) => false;
  @override
  bool canFavorite(Message message) => false;
  @override
  bool canAddMessageToStickers(Message message) => false;
  @override
  bool canRevoke(Message message) => false;
  @override
  bool canTranscribeVoice(Message message) => false;
  @override
  VoiceTranscriptionState? displayedVoiceTranscription(Message message) => null;
  @override
  void setFundMessageVisible(Message message, bool visible) {}
  @override
  void onTapRightAvatar() {}
  @override
  void clickLinkText(String url, Object? type) {}

  Future<void> disposeFixture() async {
    messageSelection.dispose();
    voiceTranscriptions.dispose();
    voicePlayback.dispose();
    await sendStatusSub.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
