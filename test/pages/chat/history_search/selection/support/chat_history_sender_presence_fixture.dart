import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_page.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../contacts/select_contacts/contact_card/support/contact_card_picker_fixture.dart';

const senderPresencePreviewDirectory =
    String.fromEnvironment('CHAT_SENDER_PRESENCE_PREVIEW_DIR');
const senderPresenceConversationID = 'sender-presence-chat';
const senderLongName = '丁一很长的发送人昵称与英文 Long sender name';

class SenderPresenceContacts extends ContactCardPickerContacts {
  bool currentSession = true;
  @override
  bool get isCurrentSession => currentSession;
}

List<ChatHistorySender> senderPresenceSamples() => const [
      ChatHistorySender(userID: '1001', displayName: '会话显示别名', nickname: '丁一'),
      ChatHistorySender(userID: '1002', displayName: 'David'),
      ChatHistorySender(userID: '2001', displayName: '钱七'),
      ChatHistorySender(userID: '4001', displayName: '张小明'),
    ];

class SenderPresenceSource implements ChatHistorySenderSource {
  SenderPresenceSource({List<ChatHistorySender>? members})
      : members = members ?? senderPresenceSamples();

  List<ChatHistorySender> members;
  final queries = <String>[];
  @override
  String currentUserID = 'self';

  @override
  Future<ChatHistorySenderPageData> load({
    required String conversationID,
    required String query,
    required int offset,
    required int count,
  }) async {
    expect(conversationID, senderPresenceConversationID);
    queries.add(query);
    final found = members
        .where((member) =>
            member.displayName.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ChatHistorySenderPageData(
      items: found.skip(offset).take(count).toList(),
      nextOffset: (offset + count).clamp(0, found.length),
      hasMore: found.length > offset + count,
    );
  }
}

Finder senderPresenceRow(String id) =>
    find.byKey(ValueKey('chat-history-sender-$id'));

class SenderPresenceFixture {
  SenderPresenceFixture({SenderPresenceSource? source})
      : source = source ?? SenderPresenceSource();

  final SenderPresenceSource source;
  final contacts = SenderPresenceContacts();
  final boundary = GlobalKey();
  final navigator = GlobalKey<NavigatorState>();
  ChatHistorySender? selected;

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double width = 390,
    double textScale = 1,
    String? fontFamily,
  }) async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    FriendDisplayPreferences.setOnlineStatus(true);
    Get.put<ContactsLogic>(contacts, permanent: true);
    final oldDark = Styles.isDark;
    final dark = brightness == Brightness.dark;
    Styles.isDark = dark;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      Styles.isDark = oldDark;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      Get.reset();
    });

    final surface = dark ? const Color(0xFF202A36) : Colors.white;
    final foreground = dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: brightness,
          fontFamily: fontFamily,
          colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF0089FF),
                  brightness: brightness,
                  surface: surface)
              .copyWith(onSurface: foreground),
          canvasColor: surface,
          appBarTheme: const AppBarTheme(scrolledUnderElevation: 0),
        ),
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: const Scaffold(body: Text('父聊天页面')),
      ),
    ));
    navigator.currentState!
        .push<ChatHistorySender>(MaterialPageRoute(
            builder: (_) => RepaintBoundary(
                  key: boundary,
                  child: ChatHistorySenderPage(
                    conversationID: senderPresenceConversationID,
                    source: source,
                  ),
                )))
        .then((value) => selected = value);
    await tester.pumpAndSettle();
  }
}

Future<void> loadSenderPresencePreviewFonts() async {
  if (senderPresencePreviewDirectory.isEmpty) return;
  for (final font in {
    'ChatSenderPreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
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
