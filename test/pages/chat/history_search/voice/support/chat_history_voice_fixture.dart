import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/chat_history_category.dart';
import 'package:openim/pages/chat/history_search/chat_history_results_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const voicePreviewDirectory = String.fromEnvironment('CHAT_VOICE_PREVIEW_DIR');
const voiceConversationID = 'voice-test-chat';
const voiceLongSender = '项目工作讨论群里名称特别长的发送人 Long sender name';

Message voiceMessage(String id, int seconds,
    {String sender = '小林', bool private = false, bool expired = false}) {
  final today = DateTime.now();
  return Message.fromJson({
    'clientMsgID': id,
    'contentType': MessageType.voice,
    'sessionType': ConversationType.single,
    'sendID': 'peer',
    'recvID': 'self',
    'senderNickname': sender,
    'sendTime': DateTime(today.year, today.month, today.day, 14, 8 + seconds)
        .millisecondsSinceEpoch,
    'status': MessageStatus.succeeded,
    'soundElem': {
      'duration': seconds,
      'sourceUrl': 'https://example.invalid/voice-test/$id.m4a',
      'soundPath': '',
    },
    if (private || expired)
      'attachedInfoElem': {
        'isPrivateChat': true,
        'burnDuration': 60,
        if (expired) 'hasReadTime': DateTime(2020).millisecondsSinceEpoch,
      },
  });
}

List<Message> voiceSamples() => [
      voiceMessage('voice-seven', 7),
      voiceMessage('voice-four', 4, sender: '陈晨'),
      voiceMessage('voice-two', 2, sender: voiceLongSender),
    ];

class VoiceTestSource implements ChatHistorySearchSource {
  List<Message> messages = [];
  final queries = <ChatHistorySearchQuery>[];

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    expect(conversationID, voiceConversationID);
    queries.add(query);
    return messages;
  }
}

Finder voiceResult(String id) =>
    find.byKey(ValueKey('chat-history-result-$id'));

Future<void> loadVoicePreviewFonts() async {
  if (voicePreviewDirectory.isEmpty) return;
  for (final font in {
    'ChatVoicePreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    await (FontLoader(font.key)
          ..addFont(File(font.value)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes))))
        .load();
  }
}

Future<void> pumpVoicePage(
  WidgetTester tester,
  VoiceTestSource source, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double textScale = 1,
  Locale locale = const Locale('zh', 'CN'),
  GlobalKey? boundaryKey,
  String? fontFamily,
}) async {
  Get.testMode = true;
  OpenIM.iMManager.userID = 'self';
  OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
  SharedPreferences.setMockInitialValues({});
  await SpUtil().init();
  final previousDark = Styles.isDark;
  final dark = brightness == Brightness.dark;
  Styles.isDark = dark;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    Styles.isDark = previousDark;
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    Get.reset();
  });

  // Same base palette as the host app; the page chooses its shared surfaces.
  final surface = dark ? const Color(0xFF202A36) : Colors.white;
  final foreground = dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        fontFamily: fontFamily,
        colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF0089FF),
                brightness: brightness,
                surface: surface)
            .copyWith(onSurface: foreground),
        scaffoldBackgroundColor:
            dark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA),
        canvasColor: surface,
        appBarTheme: const AppBarTheme(scrolledUnderElevation: 0),
      ),
      translations: TranslationService(),
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: RepaintBoundary(
        key: boundaryKey,
        child: ChatHistoryResultsPage(
          conversationID: voiceConversationID,
          category: ChatHistoryCategory.voice,
          source: source,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}
