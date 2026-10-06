import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/drafts/conversation_draft_text.dart';
import 'package:openim/pages/conversation/summary/conversation_latest_message_text.dart';
import 'package:openim/pages/conversation/widgets/conversation_feed_row.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

import '../../../support/conversation_live_fixture.dart';

const _previewDirectory =
    String.fromEnvironment('CONVERSATION_MENTION_PREVIEW_DIR');

class _Logic extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  _Logic(List<ConversationInfo> data) : list = data.obs;

  @override
  final RxList<ConversationInfo> list;
  @override
  bool isGroupChat(ConversationInfo info) => info.isGroupChat;
  @override
  bool isNotDisturb(ConversationInfo info) => false;
  @override
  int getUnreadCount(ConversationInfo info) => info.unreadCount;
  @override
  String getShowName(ConversationInfo info) => info.showName ?? '';
  @override
  String getContent(ConversationInfo info) =>
      conversationDraftText(info.draftText) ??
      conversationLatestMessageText(info);
  @override
  String getTime(ConversationInfo info) => '14:08';
  @override
  String? getPrefixTag(ConversationInfo info) => conversationPrefixTag(info);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationInfo _conversation(String id, int atType,
        {int unread = 3, String? draft, String? text, bool group = true}) =>
    ConversationInfo(
      conversationID: id,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      groupID: group ? id : null,
      userID: group ? null : id,
      showName: switch (id) {
        'me' => '项目协作群',
        'all' => '产品需求讨论群',
        'both' => '研发与设计讨论群',
        'literal' => '日常交流',
        _ => '小林',
      },
      groupAtType: atType,
      unreadCount: unread,
      draftText: draft,
      latestMsg: Message.fromJson({
        'clientMsgID': 'latest-$id',
        'contentType': MessageType.text,
        'sendID': 'peer',
        'senderNickname': '陈晨',
        'textElem': {'content': text ?? '稍后发一下新的会议安排。'},
      }),
    );

List<ConversationInfo> _samples() => [
      _conversation('me', GroupAtType.atMe),
      _conversation('all', GroupAtType.atAll, unread: 5),
      _conversation('both', GroupAtType.atAllAtMe,
          unread: 8, draft: '下午再补充一下修改意见'),
      _conversation('literal', GroupAtType.atNormal,
          unread: 0, text: '正文写着 @我、@所有人 和 [有人@我]'),
      _conversation('single', GroupAtType.atMe,
          unread: 0, group: false, text: '单聊不应出现群提醒'),
    ];

Finder _row(String id) => find.byKey(ValueKey('mention-row-$id'));
Finder _paragraph(String id) => find.descendant(
      of: find.descendant(of: _row(id), matching: find.byType(MatchTextView)),
      matching: find.byType(RichText),
    );

String _summary(WidgetTester tester, String id) =>
    tester.widget<RichText>(_paragraph(id)).text.toPlainText();

List<Color?> _colors(WidgetTester tester, String id) {
  final colors = <Color?>[];
  void collect(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) return;
    final style = inherited.merge(span.style);
    colors.addAll(List.filled(
        span.text?.length ?? 0, style.foreground?.color ?? style.color));
    for (final child in span.children ?? const <InlineSpan>[]) {
      collect(child, style);
    }
  }

  collect(tester.widget<RichText>(_paragraph(id)).text, const TextStyle());
  return colors;
}

void _expectRedRange(
    WidgetTester tester, String id, String unread, String redPrefix) {
  final text = _summary(tester, id);
  expect(text, startsWith('$unread$redPrefix'));
  final colors = _colors(tester, id);
  expect(colors.take(unread.length), everyElement(isNot(Styles.c_FF381F)));
  expect(colors.sublist(unread.length, unread.length + redPrefix.length),
      everyElement(Styles.c_FF381F));
  final bodyColors = colors.skip(unread.length + redPrefix.length);
  expect(bodyColors, isNotEmpty);
  expect(bodyColors, everyElement(isNot(Styles.c_FF381F)));
  expect(bodyColors, everyElement(isNotNull));
}

Future<_Logic> _open(WidgetTester tester,
    {required Brightness brightness,
    bool archived = false,
    double width = 390,
    double textScale = 1,
    String? fontFamily,
    GlobalKey? boundary}) async {
  Get.testMode = true;
  OpenIM.iMManager.userID = 'self';
  final oldDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  final logic = _Logic(_samples());
  Get.put<ConversationLogic>(logic);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    Get.reset();
    Styles.isDark = oldDark;
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  final surface =
      brightness == Brightness.dark ? const Color(0xFF202A36) : Colors.white;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        brightness: brightness,
        fontFamily: fontFamily,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0089FF),
            brightness: brightness,
            surface: surface),
        canvasColor: surface,
        appBarTheme: const AppBarTheme(scrolledUnderElevation: 0),
      ),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: RepaintBoundary(
        key: boundary,
        child: Scaffold(
          appBar: AppBar(title: const Text('会话')),
          body: Obx(() => ListView(
                children: [
                  for (final info in logic.list)
                    ConversationFeedRow(
                      key: ValueKey('mention-row-${info.conversationID}'),
                      logic: logic,
                      info: info,
                      archivedLayout: archived,
                      showDivider: true,
                      editing: false,
                      selected: false,
                      onTap: () {},
                      onLongPress: null,
                    ),
                ],
              )),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return logic;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    for (final archived in [false, true]) {
      testWidgets('${brightness.name} archived=$archived renders SDK mentions',
          (tester) async {
        final logic = await _open(tester,
            brightness: brightness, archived: archived, width: 320);
        String unread(int count) => '[${sprintf(StrRes.nPieces, [count])}] ';
        final atMe = '[${StrRes.someoneMentionMe}]';
        final atAll = '[@${StrRes.everyone}]';
        _expectRedRange(tester, 'me', unread(3), atMe);
        _expectRedRange(tester, 'all', unread(5), atAll);
        _expectRedRange(
            tester, 'both', unread(8), '$atAll$atMe[${StrRes.draftText}]');
        expect(_summary(tester, 'both'), endsWith('下午再补充一下修改意见'));
        for (final id in ['literal', 'single']) {
          expect(_colors(tester, id), everyElement(isNot(Styles.c_FF381F)));
        }
        expect(_summary(tester, 'literal'), contains('@我、@所有人'));
        expect(_summary(tester, 'single'), '单聊不应出现群提醒');
        final render = tester.renderObject<RenderParagraph>(_paragraph('both'));
        expect(render.maxLines, 1);
        expect(render.overflow, TextOverflow.ellipsis);
        expect(render.didExceedMaxLines, isTrue);
        expect(
            tester.getRect(_paragraph('both')).right, lessThanOrEqualTo(320));

        logic.list[0] = _conversation('me', GroupAtType.atMe,
            text: '之后收到的普通消息，不能覆盖尚未清除的提醒');
        await tester.pumpAndSettle();
        _expectRedRange(tester, 'me', unread(3), atMe);
        expect(_summary(tester, 'me'), contains('之后收到的普通消息'));
        logic.list[0].groupAtType = GroupAtType.atNormal;
        logic.list.refresh();
        await tester.pumpAndSettle();
        expect(_summary(tester, 'me'), isNot(contains(atMe)));
        expect(_summary(tester, 'me'), contains('之后收到的普通消息'));
        expect(_colors(tester, 'me'), everyElement(isNot(Styles.c_FF381F)));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('export ${brightness.name} conversation mention previews',
        skip: _previewDirectory.isEmpty, (tester) async {
      await tester.runAsync(() async {
        for (final font in {
          'ConversationMentionCjk': 'C:/Windows/Fonts/msyh.ttc',
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
              ..addFont(rootBundle.load(
                  'packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf')))
            .load();
      });
      final boundary = GlobalKey();
      await _open(tester,
          brightness: brightness,
          fontFamily: 'ConversationMentionCjk',
          boundary: boundary);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory(_previewDirectory);
        await output.create(recursive: true);
        await File(
                '${output.path}/conversation-mentions-${brightness.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
