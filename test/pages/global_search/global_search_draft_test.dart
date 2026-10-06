import 'dart:convert';
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
import 'package:openim/pages/global_search/global_search_logic.dart';
import 'package:openim/pages/global_search/global_search_view.dart';
import 'package:openim_common/openim_common.dart';

class _SearchSource extends GlobalSearchSource {
  _SearchSource(this.items);

  final List<ConversationInfo> items;

  @override
  Future<List<FriendInfo>> friends(String query) async => [];

  @override
  Future<List<GroupInfo>> groups(String query) async => [];

  @override
  Future<List<ConversationInfo>> conversations(String query) async => items;

  @override
  Future<List<SearchResultItems>> messages(String query, bool files) async =>
      [];
}

ConversationInfo _conversation(String name,
        {String? draft, bool group = false}) =>
    ConversationInfo(
      conversationID: name,
      showName: name,
      userID: group ? null : name,
      groupID: group ? name : null,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      draftText: draft,
      unreadCount: 0,
    );

String _subtitle(WidgetTester tester, String name) {
  final row = _row(name);
  final subtitle = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .last;
  return subtitle.data ?? subtitle.textSpan!.toPlainText();
}

Finder _row(String name) => find.byWidgetPredicate((widget) =>
    widget is ListTile &&
    widget.title is Text &&
    (widget.title! as Text).data == name);

const _previewOutput = String.fromEnvironment('GLOBAL_SEARCH_PREVIEW');
bool _fontsLoaded = false;

Future<void> _mount(WidgetTester tester,
    {required List<ConversationInfo> items,
    bool dark = false,
    GlobalKey? boundaryKey,
    Size size = const Size(375, 812),
    double textScale = 1}) async {
  Get.testMode = true;
  Styles.isDark = dark;
  Get.put(GlobalSearchLogic(source: _SearchSource(items)));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (_previewOutput.isNotEmpty && !_fontsLoaded) {
    await tester.runAsync(_loadPreviewFonts);
    _fontsLoaded = true;
  }
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) {
      final app = GetMaterialApp(
        debugShowCheckedModeBanner: false,
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: _previewOutput.isNotEmpty ? 'SearchPreviewFont' : null,
          brightness: dark ? Brightness.dark : Brightness.light,
          colorScheme: ColorScheme.fromSeed(
              seedColor: AppTokens.accent,
              brightness: dark ? Brightness.dark : Brightness.light),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 34),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: GlobalSearchPage(),
      );
      return boundaryKey == null
          ? app
          : RepaintBoundary(key: boundaryKey, child: app);
    },
  ));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '冬');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  Get.find<GlobalSearchLogic>().focusNode.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  for (final dark in [false, true]) {
    testWidgets(
        'plain and composer drafts show in all and conversation tabs: $dark',
        (tester) async {
      final boundaryKey = GlobalKey();
      await _mount(tester, dark: dark, boundaryKey: boundaryKey, items: [
        _conversation('冬', draft: '明天见，这条还没有发出去'),
        _conversation('测试222',
            group: true,
            draft: jsonEncode({
              'text': '@冬 帮我看看这份资料',
              'mentions': {'friend-id': '冬'}
            })),
        _conversation('普通会话'),
      ]);

      expect(_subtitle(tester, '冬'), contains('明天见，这条还没有发出去'));
      expect(_subtitle(tester, '测试222'), contains('@冬 帮我看看这份资料'));
      expect(_subtitle(tester, '测试222'), isNot(contains('mentions')));
      expect(_subtitle(tester, '普通会话'), StrRes.singleChat);

      if (_previewOutput.isNotEmpty) {
        await _export(tester, boundaryKey, dark ? 'dark' : 'light');
      }

      Get.find<GlobalSearchLogic>().index.value = 3;
      await tester.pumpAndSettle();
      expect(_subtitle(tester, '冬'), contains('明天见，这条还没有发出去'));
      expect(_subtitle(tester, '测试222'), contains('@冬 帮我看看这份资料'));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'search navigation has centered title and blue back arrow: $dark',
        (tester) async {
      await _mount(tester, dark: dark, items: []);
      final appBar = tester.widget<GlassAppBar>(find.byType(GlassAppBar));
      expect(appBar.centerTitle, isTrue);
      final arrow = find.byIcon(Icons.arrow_back_ios_new_rounded);
      expect(arrow, findsOneWidget);
      expect(tester.widget<Icon>(arrow).color, AppTokens.accent);
      final title = find.descendant(
          of: find.byType(GlassAppBar), matching: find.text(StrRes.search));
      final center = tester.getCenter(title);
      expect(center.dx, closeTo(375 / 2, 1));
      final back = find.ancestor(of: arrow, matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(back).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty drafts retain single and group conversation labels',
      (tester) async {
    await _mount(tester, items: [
      _conversation('未保存草稿'),
      _conversation('清空草稿', draft: ''),
      _conversation('空白草稿', draft: ' \n\t'),
      _conversation('空结构化草稿', draft: jsonEncode({'text': '', 'mentions': {}})),
      _conversation('普通群聊', group: true),
    ]);
    for (final name in ['未保存草稿', '清空草稿', '空白草稿', '空结构化草稿']) {
      expect(_subtitle(tester, name), StrRes.singleChat);
    }
    expect(_subtitle(tester, '普通群聊'), StrRes.globalSearchGroup);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long drafts stay bounded with large text on a narrow screen',
      (tester) async {
    await _mount(tester,
        size: const Size(320, 720),
        textScale: 1.6,
        items: [_conversation('冬', draft: List.filled(50, '这是一条长草稿').join())]);
    final row = _row('冬');
    final subtitle = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .last;
    expect(subtitle.maxLines, inInclusiveRange(1, 2));
    expect(subtitle.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _loadPreviewFonts() async {
  final chinese = File('C:/Windows/Fonts/msyh.ttc');
  if (await chinese.exists()) {
    final bytes = ByteData.sublistView(await chinese.readAsBytes());
    await (FontLoader('SearchPreviewFont')..addFont(Future.value(bytes)))
        .load();
  }
  final icons = File(
      'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final bytes = await icons.exists()
      ? ByteData.sublistView(await icons.readAsBytes())
      : await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')..addFont(Future.value(bytes))).load();
  final groupIcons = await rootBundle
      .load('packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf');
  await (FontLoader('packages/font_awesome_flutter/FontAwesomeSolid')
        ..addFont(Future.value(groupIcons)))
      .load();
}

Future<void> _export(
    WidgetTester tester, GlobalKey key, String themeName) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('$_previewOutput/global-search-draft-$themeName.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
