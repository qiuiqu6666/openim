import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_view.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

const recentConversationPreviewDirectory =
    String.fromEnvironment('RECENT_CONVERSATION_PREVIEW_DIR');
const recentLongName = '项目协作与产品需求讨论群 Very long conversation name';
const recentLongPreview = '陈晨：周五之前请大家确认最新的产品说明、待办事项和会议安排。'
    'Please review the latest project details and meeting notes.';

class RecentConversationLive extends GetxController
    implements ConversationLogic {
  RecentConversationLive(List<ConversationInfo> data) : list = data.obs;

  @override
  final RxList<ConversationInfo> list;

  @override
  bool get isSessionActive => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecentConversationIM extends GetxController implements IMController {
  @override
  final revokedMessages = PublishSubject<RevokedInfo>();
  @override
  final deletedMessages = PublishSubject<Message>();

  @override
  void onClose() {
    revokedMessages.close();
    deletedMessages.close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Selection extends SelectContactsLogic {
  _Selection(List<ConversationInfo> data) {
    action = SelAction.forward;
    openSelectedSheet = false;
    ex = '待转发的测试消息';
    conversationList.assignAll(data);
  }

  @override
  // Only SDK/route initialization is replaced; selection and confirmation stay real.
  // ignore: must_call_super
  void onInit() {}

  @override
  void onReady() {}
}

Message recentMessage({
  String id = 'message',
  int type = MessageType.text,
  String text = '明天上午十点见。',
  String sender = '陈晨',
  String senderID = 'peer',
  bool group = false,
  Map<String, dynamic> extra = const {},
}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': type,
      'sessionType':
          group ? ConversationType.superGroup : ConversationType.single,
      'sendID': senderID,
      'recvID': 'self',
      'senderNickname': sender,
      'sendTime': DateTime.now().millisecondsSinceEpoch,
      'status': MessageStatus.succeeded,
      if (type == MessageType.text) 'textElem': {'content': text},
      ...extra,
    });

ConversationInfo recentConversation({
  required String id,
  String name = '小林',
  bool group = false,
  Message? message,
}) =>
    ConversationInfo(
      conversationID: id,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      userID: group ? null : 'user-$id',
      groupID: group ? 'group-$id' : null,
      showName: name,
      latestMsg: message,
      latestMsgSendTime: message?.sendTime,
    );

List<ConversationInfo> recentConversationSamples() => [
      recentConversation(id: 'single', name: '小林', message: recentMessage())
        ..unreadCount = 2,
      recentConversation(
          id: 'group',
          name: '项目协作群',
          group: true,
          message: recentMessage(group: true, text: '新版本的资料已经发到群里了。'))
        ..unreadCount = 5
        ..draftText = '我下午补充一下修改意见',
      recentConversation(
          id: 'voice',
          name: '张岚',
          message: recentMessage(type: MessageType.voice, extra: {
            'soundElem': {'duration': 7}
          })),
      recentConversation(
          id: 'file',
          name: '产品文档讨论',
          group: true,
          message: recentMessage(type: MessageType.file, group: true, extra: {
            'fileElem': {'fileName': '产品需求说明.pdf', 'fileSize': 4096}
          })),
      recentConversation(
          id: 'private',
          name: '小余',
          message: recentMessage(text: '这段私密正文不能出现在摘要里', extra: {
            'attachedInfoElem': {'isPrivateChat': true, 'burnDuration': 60}
          })),
      recentConversation(id: 'empty', name: '新的聊天'),
    ];

Finder recentConversationRow(String id) =>
    find.byKey(ValueKey('recent-conversation-row-$id'));

Finder recentConversationPreview(String id) =>
    find.byKey(ValueKey('recent-conversation-preview-$id'));

class RecentConversationFixture {
  RecentConversationFixture({List<ConversationInfo>? data})
      : data = data ?? recentConversationSamples() {
    conversations = RecentConversationLive(this.data);
    selection = _Selection(this.data);
  }

  final List<ConversationInfo> data;
  late final SelectContactsLogic selection;
  late final RecentConversationLive conversations;
  final im = RecentConversationIM();
  final navigator = GlobalKey<NavigatorState>();
  final boundary = GlobalKey();
  late final Future<dynamic> result;

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double width = 390,
    double textScale = 1,
    String? fontFamily,
    Locale locale = const Locale('zh', 'CN'),
    bool boldText = false,
  }) async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: '我');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'fixture-token',
      'imToken': 'fixture-im',
    }));
    Get.put<IMController>(im, permanent: true);
    Get.put<ConversationLogic>(conversations, permanent: true);
    Get.put<SelectContactsLogic>(selection, permanent: true);
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
        locale: locale,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale), boldText: boldText),
            child: child!),
        home: const Scaffold(body: Text('父聊天页面')),
      ),
    ));
    result = navigator.currentState!.push<dynamic>(MaterialPageRoute(
        builder: (_) => RepaintBoundary(
              key: boundary,
              child: SelectContactsPage(),
            )));
    await tester.pumpAndSettle();
  }
}

Future<void> loadRecentConversationPreviewFonts() async {
  if (recentConversationPreviewDirectory.isEmpty) return;
  for (final font in {
    'RecentConversationPreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    await (FontLoader(font.key)
          ..addFont(File(font.value)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes))))
        .load();
  }
  await (FontLoader('packages/font_awesome_flutter/FontAwesomeSolid')
        ..addFont(rootBundle
            .load('packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf')))
      .load();
}
