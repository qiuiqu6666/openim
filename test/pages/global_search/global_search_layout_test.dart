import 'dart:async';
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
import 'package:openim/pages/official_account/widgets/official_account_name_label.dart';
import 'package:openim_common/openim_common.dart';

const _previewOutput = String.fromEnvironment('GLOBAL_SEARCH_PREVIEW');
bool _previewFontsLoaded = false;

class _Source extends GlobalSearchSource {
  final calls = <String, int>{};
  Completer<List<FriendInfo>>? pendingFriends;
  bool failFiles = false;
  List<FriendInfo>? friendResults;
  List<ConversationInfo>? conversationResults;

  void _count(String section) =>
      calls.update(section, (count) => count + 1, ifAbsent: () => 1);

  @override
  Future<List<FriendInfo>> friends(String query) async {
    _count('contacts');
    if (pendingFriends != null) return pendingFriends!.future;
    return friendResults ?? [FriendInfo(userID: 'friend', nickname: '冬')];
  }

  @override
  Future<List<GroupInfo>> groups(String query) async {
    _count('groups');
    return [GroupInfo(groupID: 'group', groupName: '搜索群聊')];
  }

  @override
  Future<List<ConversationInfo>> conversations(String query) async {
    _count('conversations');
    return conversationResults ??
        [
          ConversationInfo(
              conversationID: 'group-conversation',
              groupID: 'group',
              conversationType: ConversationType.superGroup,
              showName: '有草稿的群会话',
              draftText: '明天下午一起讨论新方案',
              unreadCount: 0),
        ];
  }

  @override
  Future<List<SearchResultItems>> messages(String query, bool files) async {
    _count(files ? 'files' : 'messages');
    if (files && failFiles) throw StateError('offline');
    return files
        ? [_result('群聊文件', 0, files: true)]
        : List.generate(9, (i) => _result(i == 0 ? '群聊测试' : '测试群聊 $i', i));
  }
}

SearchResultItems _result(String name, int index, {bool files = false}) =>
    SearchResultItems.fromJson({
      'conversationID': 'group-$index',
      'conversationType': ConversationType.superGroup,
      'showName': name,
      'messageCount': 7,
      'messageList': [
        {
          'clientMsgID': 'message-$index',
          'contentType': files ? MessageType.file : MessageType.text,
          'sessionType': ConversationType.superGroup,
          'sendID': 'friend',
          'recvID': 'group-$index',
          'senderNickname': '冬',
          'textElem': {'content': '@冬 帮我看看这份资料，这是一段用于预览的较长聊天摘要'},
          'fileElem': {'fileName': '团队报告.pdf', 'fileSize': 128000},
        }
      ],
    });

Finder get _header => find.byKey(const ValueKey('global-search-header'));
Finder get _results => find.byType(ListView);
Finder _section(int id) => find.byKey(ValueKey('global-search-section-$id'));
Finder _row(String title) => find.byWidgetPredicate((widget) =>
    widget is ListTile &&
    (widget.title is Text && (widget.title! as Text).data == title ||
        widget.title is OfficialAccountNameLabel &&
            (widget.title! as OfficialAccountNameLabel).name == title));
Finder _chip(String label) => find.byWidgetPredicate((widget) =>
    widget is ChoiceChip &&
    widget.label is Text &&
    (widget.label as Text).data == label);

Future<GlobalSearchLogic> _mount(WidgetTester tester, _Source source,
    {bool dark = false,
    Size size = const Size(375, 812),
    double scale = 1,
    GlobalKey? boundary}) async {
  Get.testMode = true;
  Styles.isDark = dark;
  final logic = Get.put(GlobalSearchLogic(source: source));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (_previewOutput.isNotEmpty && !_previewFontsLoaded) {
    await tester.runAsync(_loadPreviewFonts);
    _previewFontsLoaded = true;
  }
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) {
        final brightness = dark ? Brightness.dark : Brightness.light;
        final app = GetMaterialApp(
            debugShowCheckedModeBanner: false,
            translations: TranslationService(),
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(
                fontFamily: _previewOutput.isEmpty ? null : 'SearchLayoutFont',
                brightness: brightness,
                colorScheme: ColorScheme.fromSeed(
                        seedColor: const Color(0xFF0089FF),
                        brightness: brightness,
                        surface: dark ? const Color(0xFF202A36) : Colors.white)
                    .copyWith(
                        onSurface: dark
                            ? const Color(0xFFE8EDF5)
                            : const Color(0xFF0C1C33))),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 24, bottom: 34),
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: GlobalSearchPage());
        return boundary == null
            ? app
            : RepaintBoundary(key: boundary, child: app);
      }));
  await tester.pumpAndSettle();
  return logic;
}

Future<void> _search(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '1');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  Get.find<GlobalSearchLogic>().focusNode.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String category) async {
  final chip = _chip(category);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void _expectTopSection(WidgetTester tester, int id, String firstTitle) {
  final viewport = tester.getRect(_results);
  final section = tester.getRect(_section(id));
  final row = tester.getRect(_row(firstTitle));
  expect(section.top, greaterThanOrEqualTo(viewport.top + AppTokens.s3));
  expect(section.bottom, lessThanOrEqualTo(row.top));
  expect(row.bottom, lessThan(viewport.bottom));
  final title = find.descendant(of: _section(id), matching: find.byType(Text));
  expect(tester.getRect(title).top, greaterThanOrEqualTo(section.top));
  expect(tester.getRect(title).bottom, lessThanOrEqualTo(section.bottom));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  testWidgets('contact and conversation badges use identity and keep remarks',
      (tester) async {
    final source = _Source()
      ..friendResults = [
        FriendInfo(userID: '99Message', nickname: '99Message', remark: '公告备注'),
        FriendInfo(userID: 'ordinary', nickname: '99Message'),
        FriendInfo(
            userID: 'server-official',
            nickname: '运营通知',
            ex: '{"accountType":"official","officialRole":"message"}'),
      ]
      ..conversationResults = [
        ConversationInfo(
            conversationID: 'si_99Pay_self',
            userID: '99Pay',
            showName: '支付通知',
            conversationType: ConversationType.single),
        ConversationInfo(
            conversationID: 'group-99Message',
            groupID: '99Message',
            userID: '99Message',
            showName: '99Message群',
            ex: '{"accountType":"official"}',
            conversationType: ConversationType.superGroup),
      ];
    Finder badges() => find.byWidgetPredicate((widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage)
            .assetName
            .endsWith('official_account_verified.png'));
    await _mount(tester, source);
    await _search(tester);
    await _select(tester, StrRes.globalSearchContacts);
    expect(find.text('公告备注'), findsOneWidget);
    final ordinary = find.byWidgetPredicate((widget) =>
        widget is OfficialAccountNameLabel && widget.userID == 'ordinary');
    expect(ordinary, findsOneWidget);
    expect(find.descendant(of: ordinary, matching: find.text('99Message')),
        findsOneWidget);
    expect(badges(), findsNWidgets(2));
    expect(find.descendant(of: ordinary, matching: badges()), findsNothing);
    await _select(tester, 'globalSearchConversations'.tr);
    expect(badges(), findsOneWidget);
    expect(find.descendant(of: _row('99Message群'), matching: badges()),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('first result and category headers are fully visible: $dark',
        (tester) async {
      final source = _Source();
      await _mount(tester, source, dark: dark);
      await _search(tester);
      _expectTopSection(tester, 1, '冬');
      await _select(tester, StrRes.globalSearchChatHistory);
      _expectTopSection(tester, 4, '群聊测试');
      final headerRect = tester.getRect(_header);
      await tester.drag(_results, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(tester.getRect(_header), headerRect);
      await _select(tester, 'globalSearchConversations'.tr);
      _expectTopSection(tester, 3, '有草稿的群会话');
      await _select(tester, StrRes.globalSearchChatHistory);
      _expectTopSection(tester, 4, '群聊测试');
      expect(source.calls.values.every((count) => count == 1), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('all group search identities use circular avatars: $dark',
        (tester) async {
      await _mount(tester, _Source(), dark: dark);
      await _search(tester);
      for (final category in [
        StrRes.globalSearchGroup,
        'globalSearchConversations'.tr,
        StrRes.globalSearchChatHistory,
        StrRes.globalSearchChatFile,
      ]) {
        await _select(tester, category);
        final avatars = tester.widgetList<AvatarView>(find.byType(AvatarView));
        expect(avatars, isNotEmpty);
        expect(
            avatars
                .every((avatar) => avatar.isGroup && avatar.isCircle == true),
            isTrue);
        for (final element in find.byType(AvatarView).evaluate()) {
          expect(
              find.descendant(
                  of: find.byElementPredicate((e) => e == element),
                  matching: find.byType(ClipOval)),
              findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'narrow large text keeps categories and first row bounded: $dark',
        (tester) async {
      await _mount(tester, _Source(),
          dark: dark, size: const Size(320, 720), scale: 1.6);
      await _search(tester);
      await _select(tester, StrRes.globalSearchChatHistory);
      _expectTopSection(tester, 4, '群聊测试');
      final selected = _chip(StrRes.globalSearchChatHistory);
      expect(tester.getRect(selected).bottom,
          lessThan(tester.getRect(_header).bottom));
      final appBar = find.byType(GlassAppBar);
      final title =
          find.descendant(of: appBar, matching: find.text(StrRes.search));
      expect(tester.getCenter(title).dx, closeTo(160, 1));
      final back =
          find.widgetWithIcon(IconButton, Icons.arrow_back_ios_new_rounded);
      expect(tester.getSize(back),
          const Size.square(AppIconTokens.androidTouchTarget));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading slot stays stable and clear returns to empty search',
      (tester) async {
    final source = _Source()..pendingFriends = Completer<List<FriendInfo>>();
    final logic = await _mount(tester, source);
    final before = tester.getSize(_header);
    expect(find.byTooltip('globalSearchClear'.tr), findsNothing);
    await tester.enterText(find.byType(TextField), '1');
    await tester.pump(const Duration(milliseconds: 350));
    expect(logic.loading.value, isTrue);
    expect(tester.getSize(_header), before);
    source.pendingFriends!
        .complete([FriendInfo(userID: 'friend', nickname: '冬')]);
    await tester.pumpAndSettle();
    expect(tester.getSize(_header), before);
    await tester.tap(find.byTooltip('globalSearchClear'.tr));
    await tester.pumpAndSettle();
    expect(logic.query.value, isEmpty);
    expect(logic.loading.value, isFalse);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byTooltip('globalSearchClear'.tr), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial section failure keeps its heading and retry works',
      (tester) async {
    final source = _Source()..failFiles = true;
    await _mount(tester, source);
    await _search(tester);
    await _select(tester, StrRes.globalSearchChatFile);
    expect(_section(5), findsOneWidget);
    expect(find.text('globalSearchFailed'.tr), findsOneWidget);
    source.failFiles = false;
    await tester.tap(find.widgetWithText(TextButton, 'chatSearchRetry'.tr));
    await tester.pumpAndSettle();
    _expectTopSection(tester, 5, '群聊文件');
    expect(find.text('globalSearchFailed'.tr), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('export actual search results ${dark ? 'dark' : 'light'}',
        (tester) async {
      final boundary = GlobalKey();
      await _mount(tester, _Source(), dark: dark, boundary: boundary);
      await _search(tester);
      await _select(tester, StrRes.globalSearchChatHistory);
      await _export(tester, boundary, dark ? 'dark' : 'light');
      expect(tester.takeException(), isNull);
    },
        skip: _previewOutput.isEmpty,
        variant: TargetPlatformVariant(
            {TargetPlatform.android, TargetPlatform.iOS}));
  }
}

Future<void> _loadPreviewFonts() async {
  final chinese = File('C:/Windows/Fonts/msyh.ttc');
  if (await chinese.exists()) {
    final bytes = ByteData.sublistView(await chinese.readAsBytes());
    await (FontLoader('SearchLayoutFont')..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  await (FontLoader('packages/font_awesome_flutter/FontAwesomeSolid')
        ..addFont(rootBundle
            .load('packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf')))
      .load();
}

Future<void> _export(
    WidgetTester tester, GlobalKey key, String themeName) async {
  final platform =
      Theme.of(tester.element(find.byType(GlobalSearchPage))).platform.name;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File(
          '$_previewOutput/global-search-results-$themeName-$platform.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
