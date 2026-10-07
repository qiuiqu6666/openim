import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import '../../support/conversation_live_fixture.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/conversation_view.dart';
import 'package:openim_common/openim_common.dart';

class _ConversationLogic extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  @override
  final list = <ConversationInfo>[].obs;
  @override
  final folders = <ChatFolder>[].obs;
  @override
  final popCtrl = CustomPopupMenuController();
  final connection = 'ready'.obs;
  int searches = 0;

  @override
  String? get imSdkStatus =>
      connection.value == 'ready' ? null : connection.value;
  @override
  bool get isFailedSdkStatus => connection.value == 'failed';
  @override
  bool get reInstall => false;
  @override
  bool get isSessionActive => true;
  @override
  void globalSearch() => searches++;
  @override
  void addFriend() {}
  @override
  void addGroup() {}
  @override
  void createGroup() {}
  @override
  Future<void> refreshOrganizer() async {}
  @override
  bool isArchived(ConversationInfo info) => false;
  @override
  String? folderID(ConversationInfo info) => null;
  @override
  bool isGroupChat(ConversationInfo info) => info.isGroupChat;
  @override
  bool isNotDisturb(ConversationInfo info) => false;
  @override
  int getUnreadCount(ConversationInfo info) => info.unreadCount;
  @override
  String getShowName(ConversationInfo info) => info.showName ?? '';
  @override
  String getContent(ConversationInfo info) => IMUtils.parseMsg(info.latestMsg!);
  @override
  String getTime(ConversationInfo info) => '18:29';
  @override
  String? getPrefixTag(ConversationInfo info) => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    popCtrl.dispose();
    super.onClose();
  }
}

const _previewOutput = String.fromEnvironment('CONVERSATION_CHROME_PREVIEW');
bool _previewFontsLoaded = false;

Widget _host({
  required bool dark,
  bool groupChats = false,
  double textScale = 1,
  GlobalKey? boundaryKey,
}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: _previewFontsLoaded ? 'ChromePreviewFont' : null,
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(375, 812),
              padding: const EdgeInsets.only(top: 24),
              textScaler: TextScaler.linear(textScale),
            ),
            child: ConversationPage(groupChats: groupChats),
          ),
        ),
      ),
    );

void _configureView(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<ui.Image> _snapshot(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() => boundary.toImage()))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'preview-viewer';
  });
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  for (final dark in [false, true]) {
    testWidgets('actual header matches reference decoration and states ($dark)',
        (tester) async {
      _configureView(tester);
      Styles.isDark = dark;
      final logic = Get.put<ConversationLogic>(_ConversationLogic())
          as _ConversationLogic;
      final key = GlobalKey();
      await tester.pumpWidget(_host(dark: dark, boundaryKey: key));
      await tester.pumpAndSettle();

      final title = tester
          .widget<Text>(find.byKey(const ValueKey('main-tab-title-text')));
      expect(title.data, '消息');
      expect(title.style?.fontSize, 22);
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(title.style?.height, 1);
      expect(title.style?.color, AppTokens.textPrimary(dark: dark));
      final line = find.byKey(const ValueKey('main-tab-title-indicator-line'));
      final dot = find.byKey(const ValueKey('main-tab-title-indicator-dot'));
      expect(tester.getSize(line), const Size(32, 4));
      expect(tester.getSize(dot), const Size(8, 8));
      expect(tester.getRect(dot).left - tester.getRect(line).right, 8);
      final appBar = tester
          .widget<AppBar>(find.byWidgetPredicate((widget) => widget is AppBar));
      expect(appBar.elevation, 0);
      expect(appBar.backgroundColor, Colors.transparent);
      expect(appBar.flexibleSpace, isA<LiquidGlassSurface>());
      expect((appBar.flexibleSpace! as LiquidGlassSurface).tint,
          dark ? AppTokens.backgroundDark : AppTokens.surfaceLight);
      for (final tooltip in ['在线客服', '编辑', '添加']) {
        expect(find.byTooltip(tooltip), findsOneWidget);
      }
      expect(tester.getCenter(find.byTooltip('在线客服')).dx,
          lessThan(tester.getCenter(find.byTooltip('编辑')).dx));
      expect(tester.getCenter(find.byTooltip('编辑')).dx,
          lessThan(tester.getCenter(find.byTooltip('添加')).dx));

      // Verify the rendered accent, not only the Container's declared color.
      final image = await _snapshot(tester, key);
      final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      final center = tester.getCenter(line);
      final pixel = (center.dy.floor() * image.width + center.dx.floor()) * 4;
      expect(bytes.buffer.asUint8List().sublist(pixel, pixel + 4),
          [30, 144, 255, 255]);
      image.dispose();

      await tester.tap(find.text('搜索'));
      expect(logic.searches, 1);
      logic.connection.value = 'connecting';
      await tester.pump();
      expect(find.text('正在连接'), findsOneWidget);
      expect(find.text('消息'), findsNothing);
      expect(line, findsNothing);
      expect(dot, findsNothing);
      final spinner =
          tester.widget<FadingArcSpinner>(find.byType(FadingArcSpinner));
      expect(spinner.size, closeTo(15.84, .001));
      expect(spinner.color, AppTokens.accent);

      logic.connection.value = 'failed';
      await tester.pumpAndSettle();
      expect(find.text('消息'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byType(FadingArcSpinner), findsNothing);
      expect(line, findsNothing);
      expect(dot, findsNothing);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      expect(find.text('完成'), findsOneWidget);
      for (final tooltip in ['在线客服', '编辑', '添加']) {
        expect(find.byTooltip(tooltip), findsNothing);
      }
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('完成'), findsNothing);
      for (final tooltip in ['在线客服', '编辑', '添加']) {
        expect(find.byTooltip(tooltip), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('group tab uses its own title and keeps reference decoration',
      (tester) async {
    _configureView(tester);
    Get.put<ConversationLogic>(_ConversationLogic());
    await tester.pumpWidget(_host(dark: false, groupChats: true));
    await tester.pumpAndSettle();
    expect(find.text('群聊'), findsOneWidget);
    expect(find.text('消息'), findsNothing);
    expect(find.byKey(const ValueKey('main-tab-title-indicator-line')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dark in [false, true]) {
    for (final textScale in [1.0, 1.5]) {
      testWidgets(
          'conversation rows retain reference layout ($dark, $textScale)',
          (tester) async {
        _configureView(tester);
        Styles.isDark = dark;
        final logic = _ConversationLogic();
        final messages = ['你好，今天有空吗？', '下次见'];
        final names = ['日常聊天', '置顶聊天'];
        for (var index = 0; index < 2; index++) {
          logic.list.add(ConversationInfo(
            conversationID: 'conversation-$index',
            conversationType: ConversationType.single,
            userID: 'friend-$index',
            showName: names[index],
            isPinned: index == 1,
            latestMsg: Message.fromJson({
              'contentType': MessageType.text,
              'sendID': 'friend-$index',
              'textElem': {'content': messages[index]},
            }),
          ));
        }
        Get.put<ConversationLogic>(logic);
        final key = GlobalKey();
        await tester.pumpWidget(
            _host(dark: dark, textScale: textScale, boundaryKey: key));
        await tester.pumpAndSettle();
        final dividers = <Finder>[];
        for (var index = 0; index < 2; index++) {
          final row = find.byKey(ValueKey('conversation-$index'));
          expect(tester.getSize(row).height, textScale == 1 ? 72 : 80);
          final title = tester.widget<Text>(find.text(names[index]));
          expect(title.style?.fontSize, 16);
          expect(title.style?.height, 1.2);
          final preview = tester.widget<MatchTextView>(
              find.descendant(of: row, matching: find.byType(MatchTextView)));
          expect(preview.text, messages[index]);
          expect(preview.textStyle?.fontSize, 14);
          expect(preview.textStyle?.height, 1.2);
          final surface = tester.widget<Material>(find.descendant(
              of: row,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Material &&
                  widget.child is InkWell &&
                  (widget.child! as InkWell).onLongPress != null)));
          expect(
              surface.color,
              index == 1
                  ? AppTokens.surfaceAlt(dark: dark)
                  : dark
                      ? AppTokens.backgroundDark
                      : AppTokens.surfaceLight);
          dividers.add(find.descendant(
              of: row,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Positioned &&
                  widget.left == 82 &&
                  widget.bottom == 0)));
        }
        expect(dividers.first, findsOneWidget);
        expect(dividers.last, findsNothing);
        final divider = tester.widget<Container>(find.descendant(
            of: dividers.first, matching: find.byType(Container)));
        expect(divider.color,
            dark ? AppTokens.borderDark : const Color(0xFFEAEAEA));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('render review sheet of actual light and dark header states',
      (tester) async {
    _configureView(tester);
    await tester.runAsync(() async {
      final file = File('C:/Windows/Fonts/msyh.ttc');
      if (await file.exists()) {
        await (FontLoader('ChromePreviewFont')
              ..addFont(file.readAsBytes().then(ByteData.sublistView)))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
        _previewFontsLoaded = true;
      }
    });
    final logic =
        Get.put<ConversationLogic>(_ConversationLogic()) as _ConversationLogic;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final images = <ui.Image>[];
    final paint = Paint();
    const panelHeight = 144.0;
    for (var column = 0; column < 2; column++) {
      final dark = column == 1;
      Styles.isDark = dark;
      final key = GlobalKey();
      logic.connection.value = 'ready';
      await tester.pumpWidget(_host(dark: dark, boundaryKey: key));
      await tester.pumpAndSettle();
      await tester.runAsync(() => precacheImage(
            const AssetImage('assets/images/home_nav_plus_99chat.png',
                package: 'openim_common'),
            key.currentContext!,
          ));
      for (var row = 0; row < 3; row++) {
        logic.connection.value = ['ready', 'connecting', 'failed'][row];
        await tester.pump(const Duration(milliseconds: 90));
        final image = await _snapshot(tester, key);
        images.add(image);
        canvas.drawImageRect(
          image,
          const Rect.fromLTWH(0, 0, 375, panelHeight),
          Rect.fromLTWH(column * 375, row * panelHeight, 375, panelHeight),
          paint,
        );
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final image = await picture.toImage(750, 432);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(_previewOutput);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      for (final captured in images) {
        captured.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  }, skip: _previewOutput.isEmpty);
}
