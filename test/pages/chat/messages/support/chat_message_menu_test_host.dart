import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

const menuPanelKey = ValueKey('chat-message-menu-panel');
const menuBubbleKey = ValueKey('menu-test-message');

const menuTestActions = <({String id, String text})>[
  (id: 'replyMessage', text: '引用'),
  (id: 'copyMessage', text: '复制'),
  (id: 'forwardMessage', text: '转发'),
  (id: 'revoke', text: '撤回'),
  (id: 'favorite_message', text: '收藏'),
  (id: 'mergeForward', text: '合并转发'),
  (id: 'delete', text: '删除'),
  (id: 'voiceToText', text: '转文字'),
];

Finder menuAction(String id) =>
    find.byKey(ValueKey('chat-message-menu-action-$id'));

Future<void> settleMenu(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

class MenuTestObserver extends NavigatorObserver {
  final events = <String>[];
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    events.add('push');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    events.add('pop');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    events.add('remove');
  }
}

class MenuTestHarness {
  final controller = CustomPopupMenuController();
  final navigator = GlobalKey<NavigatorState>();
  final boundary = GlobalKey();
  final showMessage = ValueNotifier(true);
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final observer = MenuTestObserver();
  final selected = <String>[];
  int backgroundTaps = 0, messageTaps = 0;
  bool? closedBeforeAction;

  List<PopMenuInfo> menus(int count, {bool explicitIcons = false}) =>
      List.generate(count, (index) {
        final action = menuTestActions[index % menuTestActions.length];
        final id = index < menuTestActions.length ? action.id : 'extra-$index';
        return PopMenuInfo(
            id: id,
            text: index < menuTestActions.length ? action.text : '操作 $index',
            iconWidget: explicitIcons
                ? Icon(Icons.chat_bubble_outline,
                    key: ValueKey('menu-test-icon-$id'))
                : null,
            onTap: () {
              closedBeforeAction =
                  !controller.menuIsShowing && observer.routes.length == 1;
              observer.events.add('action-$id');
              selected.add(id);
            });
      });

  Future<void> mount(WidgetTester tester,
      {required List<PopMenuInfo> menus,
      bool outgoing = false,
      Brightness brightness = Brightness.light,
      Offset anchor = const Offset(16, 300),
      Size screen = const Size(375, 812),
      double keyboardHeight = 0,
      TextScaler textScaler = TextScaler.noScaling,
      bool composer = false,
      bool realFonts = false}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (realFonts) await tester.runAsync(loadMenuFonts);
    addTearDown(() async {
      controller.hideMenu();
      await settleMenu(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await settleMenu(tester);
      controller.dispose();
      showMessage.dispose();
      input.dispose();
      inputFocus.dispose();
    });
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
            brightness: brightness,
            fontFamily: realFonts ? 'ChatMenuPreviewFont' : null),
        builder: (context, child) {
          ScreenUtil.init(context, designSize: const Size(375, 812));
          return RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: textScaler,
                      viewInsets: EdgeInsets.only(bottom: keyboardHeight),
                      padding: const EdgeInsets.only(top: 24, bottom: 16)),
                  child: child!));
        },
        home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => backgroundTaps++,
                child: Stack(children: [
                  Positioned(
                      left: anchor.dx,
                      top: anchor.dy,
                      child: ValueListenableBuilder<bool>(
                          valueListenable: showMessage,
                          builder: (_, show, __) => show
                              ? ChatMessageMenu(
                                  menus: menus,
                                  controller: controller,
                                  isOutgoing: outgoing,
                                  child: GestureDetector(
                                      onTap: () => messageTaps++,
                                      child: Container(
                                          key: menuBubbleKey,
                                          width: 180,
                                          height: 56,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                              color: outgoing
                                                  ? Colors.blue
                                                  : Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          child: const Text('这是一条聊天消息'))))
                              : const SizedBox.shrink())),
                  if (composer)
                    Positioned(
                        left: 12,
                        right: 12,
                        bottom: keyboardHeight + 12,
                        child: TextField(
                          key: const ValueKey('menu-test-input'),
                          controller: input,
                          focusNode: inputFocus,
                        )),
                ])))));
    await settleMenu(tester);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.longPress(find.byKey(menuBubbleKey));
    await settleMenu(tester);
    expect(find.byKey(menuPanelKey), findsOneWidget);
    expect(controller.menuIsShowing, isTrue);
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('.dart_tool/chat-message-menu-$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
}

Future<void> loadMenuFonts() async {
  final file = File('C:/Windows/Fonts/msyh.ttc');
  if (!await file.exists()) return;
  final bytes = ByteData.sublistView(await file.readAsBytes());
  for (final family in [
    'ChatMenuPreviewFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}
