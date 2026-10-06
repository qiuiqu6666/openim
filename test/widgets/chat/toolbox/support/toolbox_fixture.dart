import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

const toolboxPreviewKey = ValueKey('toolbox-preview');

Finder toolboxAction(String id) =>
    find.byKey(ValueKey('chat-toolbox-action-$id'));

class ToolboxFixture {
  final calls = <String, int>{};

  VoidCallback action(String id) =>
      () => calls.update(id, (count) => count + 1, ifAbsent: () => 1);

  ChatToolBox full(
          {bool group = false, List<ToolboxItemInfo> extras = const []}) =>
      ChatToolBox(
        isGroupChat: group,
        extraItems: extras,
        onTapAlbum: action('album'),
        onTapCamera: action('camera'),
        onTapFavorites: action('favorites'),
        onTapCall: action('call'),
        onTapCard: action('card'),
        onTapFile: action('file'),
        onTapRedPacket: action('red-packet'),
        onTapTransfer: action('transfer'),
        onTapRecord: action('record'),
        onTapAudio: action('audio'),
        onTapLocation: action('location'),
        onTapFormattedText: action('formatted-text'),
        onTapEmoji: action('emoji'),
      );
}

Future<void> mountToolbox(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light,
    Size size = const Size(375, 812),
    double textScale = 1,
    double safeBottom = 0,
    bool bottom = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(bottom: safeBottom);
  addTearDown(tester.view.reset);
  final wasDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = wasDark);
  final font = const bool.fromEnvironment('CHAT_TOOLBOX_PREVIEW')
      ? 'ToolboxPreviewFont'
      : null;
  await tester.runAsync(() async {
    for (final asset in ['photo', 'screen', 'video-call', 'card', 'file']) {
      final picture = await vg.loadPicture(
        SvgAssetLoader('assets/chat_toolbox/$asset.svg',
            packageName: 'openim_common'),
        null,
      );
      picture.picture.dispose();
    }
  });
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: brightness, fontFamily: font),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: bottom ? Alignment.bottomCenter : Alignment.topCenter,
          child: RepaintBoundary(key: toolboxPreviewKey, child: child),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(toolboxPreviewKey));
    for (final asset in ['favorites', 'red_packet', 'transfer', 'group_live']) {
      await precacheImage(
          AssetImage('assets/chat_toolbox/$asset.png',
              package: 'openim_common'),
          context);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> reachToolboxAction(WidgetTester tester, String id) async {
  final pages = tester.widget<PageView>(find.byType(PageView));
  pages.controller?.jumpToPage(0);
  await tester.pumpAndSettle();
  final action = toolboxAction(id);
  for (var page = 0; page < 6; page++) {
    if (action.hitTestable().evaluate().isNotEmpty) return;
    // Only the current grid handles vertical movement. Larger text/landscape
    // can require scrolling its second row inside the fixed-height panel.
    final grid = find
        .byWidgetPredicate((widget) =>
            widget is SingleChildScrollView &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('chat-toolbox-page-'))
        .hitTestable();
    if (grid.evaluate().isNotEmpty) {
      await tester.drag(grid.first, const Offset(0, -180));
      await tester.pumpAndSettle();
      if (action.hitTestable().evaluate().isNotEmpty) return;
    }
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
  }
  fail('toolbox action $id is not reachable');
}

class ToolboxPermissions {
  static const channel =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  int status = 1;
  final requests = <List<int>>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'requestPermissions':
          final permissions = List<int>.from(call.arguments as List);
          requests.add(permissions);
          return {for (final permission in permissions) permission: status};
        case 'checkPermissionStatus':
          return status;
        case 'openAppSettings':
          return true;
        default:
          throw MissingPluginException(call.method);
      }
    });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

Future<void> loadToolboxPreviewFonts() async {
  if (!const bool.fromEnvironment('CHAT_TOOLBOX_PREVIEW')) return;
  for (final font in {
    'ToolboxPreviewFont': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final loader = FontLoader(font.key)
      ..addFont(File(font.value)
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Future<void> captureToolbox(
    WidgetTester tester, Brightness brightness, int page) async {
  if (!const bool.fromEnvironment('CHAT_TOOLBOX_PREVIEW')) return;
  await tester.runAsync(() async {
    final boundary = tester
        .renderObject<RenderRepaintBoundary>(find.byKey(toolboxPreviewKey));
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('.dart_tool/chat-toolbox-${brightness.name}-page-$page.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
