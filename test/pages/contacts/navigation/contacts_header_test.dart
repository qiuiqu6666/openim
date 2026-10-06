import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/contacts/navigation/contacts_header.dart';
import 'package:openim/pages/home/home_quick_actions.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _previewDirectory =
    Platform.environment['CONTACTS_HEADER_PREVIEW_DIR'] ?? '';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });
  tearDown(Get.reset);

  for (final dark in [false, true]) {
    testWidgets('reference title and lone plus keep left alignment ($dark)',
        (tester) async {
      final h = _HeaderHost(dark: dark);
      await h.mount(tester);
      final title = tester.widget<Text>(_title);
      expect(title.data, '通讯录');
      expect(title.style?.fontSize, AppTokens.mainTabTitleFontSize);
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(title.style?.height, 1);
      expect(title.style?.color, AppTokens.textPrimary(dark: dark));
      expect(tester.getTopLeft(_title).dx, 16);
      expect(tester.getSize(_line), const Size(32, 4));
      expect(tester.getSize(_dot), const Size(8, 8));
      expect(tester.getTopLeft(_line).dx, tester.getTopLeft(_title).dx);
      expect(tester.getTopLeft(_dot).dx - tester.getTopRight(_line).dx, 8);
      final decoration =
          tester.widget<Container>(_line).decoration! as BoxDecoration;
      expect(decoration.color, AppTokens.accent);
      expect(tester.getSize(_plus), const Size(48, 48));
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byTooltip('在线客服'), findsNothing);
      expect(find.byTooltip('编辑'), findsNothing);
      final bar = tester.widget<AppBar>(find.byType(GlassAppBar));
      expect(bar.centerTitle, isFalse);
      expect(bar.automaticallyImplyLeading, isFalse);
      expect(bar.toolbarHeight, kToolbarHeight);
      expect(bar.systemOverlayStyle?.statusBarColor, Colors.transparent);
      expect(bar.systemOverlayStyle?.statusBarIconBrightness,
          dark ? Brightness.light : Brightness.dark);
      expect(bar.systemOverlayStyle?.statusBarBrightness,
          dark ? Brightness.dark : Brightness.light);
      expect(tester.getRect(_plus).top, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('four reference menu entries keep order and theme ($dark)',
        (tester) async {
      final h = _HeaderHost(dark: dark);
      await h.mount(tester);
      await h.openMenu(tester);
      expect(_menuIDs(tester),
          ['searchAdd', 'createGroup', 'createChannel', 'scanQRCode']);
      expect(find.text('搜索添加'), findsOneWidget);
      expect(find.text('创建群聊'), findsOneWidget);
      expect(find.text('创建频道'), findsOneWidget);
      expect(find.text('扫一扫'), findsOneWidget);
      final material = tester
          .widgetList<Material>(find.byType(Material))
          .singleWhere((widget) => widget.shape is HomeQuickMenuShape);
      expect(material.color,
          dark ? HomeQuickActionTokens.menuDark : AppTokens.surfaceLight);
      final menuRect = tester.getRect(find.byType(HomeQuickActionTile).first);
      expect(menuRect.right, lessThanOrEqualTo(h.size.width - 8));
      expect(menuRect.top, greaterThan(tester.getRect(_plus).bottom));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('English header and menu remain localized', (tester) async {
    final h = _HeaderHost(locale: const Locale('en'));
    await h.mount(tester);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.byTooltip('Add'), findsOneWidget);
    await h.openMenu(tester);
    expect(_menuIDs(tester),
        ['searchAdd', 'createGroup', 'createChannel', 'scanQRCode']);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SDK status changes update only the title and retain open menu',
      (tester) async {
    final statuses = StreamController<IMSdkStatus>.broadcast(sync: true);
    addTearDown(statuses.close);
    final h = _HeaderHost(sdkStatus: statuses.stream);
    await h.mount(tester);
    await h.openMenu(tester);
    final plusBefore = tester.widget<IconButton>(_plus);
    final bodyBuilds = h.bodyBuilds;
    for (final status in [
      IMSdkStatus.connecting,
      IMSdkStatus.syncStart,
      IMSdkStatus.synchronizing,
      IMSdkStatus.syncProgress,
    ]) {
      statuses.add(status);
      await tester.pump();
      expect(find.text('正在连接'), findsOneWidget);
      expect(find.byType(FadingArcSpinner), findsOneWidget);
      expect(_line, findsNothing);
      expect(_dot, findsNothing);
      expect(find.byType(HomeQuickActionTile), findsNWidgets(4));
      expect(identical(tester.widget<IconButton>(_plus), plusBefore), isTrue);
      expect(h.bodyBuilds, bodyBuilds);
    }
    for (final status in [
      IMSdkStatus.connectionFailed,
      IMSdkStatus.syncFailed,
    ]) {
      statuses.add(status);
      await tester.pump();
      expect(find.text('通讯录'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byType(FadingArcSpinner), findsNothing);
      expect(_line, findsNothing);
      expect(_dot, findsNothing);
    }
    for (final status in [
      IMSdkStatus.connectionSucceeded,
      IMSdkStatus.syncEnded,
    ]) {
      statuses.add(status);
      await tester.pump();
      expect(_line, findsOneWidget);
      expect(_dot, findsOneWidget);
      expect(find.byType(FadingArcSpinner), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    }
    await h.dismissMenu(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(statuses.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial SDK status is rendered before a stream event',
      (tester) async {
    final h = _HeaderHost(initialStatus: IMSdkStatus.connecting);
    await h.mount(tester, settle: false);
    expect(find.text('正在连接'), findsOneWidget);
    expect(find.byType(FadingArcSpinner), findsOneWidget);
    expect(_line, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final id in ['searchAdd', 'createGroup', 'scanQRCode']) {
    testWidgets('$id delegates once after menu selection', (tester) async {
      final h = _HeaderHost();
      await h.mount(tester);
      await h.openMenu(tester);
      final tile = _tile(id);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(h.calls, [id]);
      expect(find.byType(HomeQuickActionTile), findsNothing);
      expect(tester.widget<AnimatedRotation>(_rotation).turns, .25);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unavailable channel is disabled and does not navigate',
      (tester) async {
    final h = _HeaderHost();
    await h.mount(tester);
    await h.openMenu(tester);
    final channel = find.ancestor(
        of: _tile('createChannel'),
        matching: find.byType(PopupMenuItem<String>));
    expect(tester.widget<PopupMenuItem<String>>(channel).enabled, isFalse);
    await tester.tap(_tile('createChannel'));
    await tester.pumpAndSettle();
    expect(h.calls, isEmpty);
    expect(find.byType(HomeQuickActionTile), findsNWidgets(4));
    await h.dismissMenu(tester);
    expect(h.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plus rotates for open and dismissal and rapid taps share a menu',
      (tester) async {
    final h = _HeaderHost();
    await h.mount(tester);
    final button = tester.widget<IconButton>(_plus);
    expect(tester.widget<AnimatedRotation>(_rotation).turns, 0);
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(HomeQuickActionTile), findsNWidgets(4));
    final rotation = tester.widget<AnimatedRotation>(_rotation);
    expect(rotation.turns, .125);
    expect(rotation.duration, const Duration(milliseconds: 220));
    expect(rotation.curve, Curves.easeInOut);
    await h.dismissMenu(tester);
    expect(tester.widget<AnimatedRotation>(_rotation).turns, .25);
    await h.openMenu(tester);
    expect(tester.widget<AnimatedRotation>(_rotation).turns, .375);
    await h.dismissMenu(tester);
    expect(tester.widget<AnimatedRotation>(_rotation).turns, .5);
    expect(h.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final layout in [
    (
      name: 'portrait',
      size: const Size(375, 812),
      padding: const EdgeInsets.only(top: 44)
    ),
    (
      name: 'landscape',
      size: const Size(812, 375),
      padding: const EdgeInsets.fromLTRB(44, 24, 44, 21)
    ),
    (
      name: 'wide',
      size: const Size(1200, 800),
      padding: const EdgeInsets.only(top: 24)
    ),
  ]) {
    testWidgets('${layout.name} safe area keeps title and popup on screen',
        (tester) async {
      final h = _HeaderHost(size: layout.size, padding: layout.padding);
      await h.mount(tester);
      final title = tester.getRect(_title);
      final plus = tester.getRect(_plus);
      expect(title.left, greaterThanOrEqualTo(layout.padding.left));
      expect(title.top, greaterThanOrEqualTo(layout.padding.top));
      expect(plus.right,
          lessThanOrEqualTo(layout.size.width - layout.padding.right));
      expect(plus.top, greaterThanOrEqualTo(layout.padding.top));
      expect(tester.getSize(_plus), const Size(48, 48));
      await h.openMenu(tester);
      for (final tile in find.byType(HomeQuickActionTile).evaluate()) {
        final rect = tester.getRect(find.byWidget(tile.widget));
        expect(rect.left, greaterThanOrEqualTo(layout.padding.left));
        expect(rect.right,
            lessThanOrEqualTo(layout.size.width - layout.padding.right));
      }
      await h.dismissMenu(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large text uses an expanded toolbar without losing actions',
      (tester) async {
    final h = _HeaderHost(textScale: 2);
    await h.mount(tester);
    final bar = tester.getRect(find.byType(ContactsHeader));
    final title = tester.getRect(_title);
    final dot = tester.getRect(_dot);
    expect(title.top, greaterThanOrEqualTo(h.padding.top));
    expect(dot.bottom, lessThanOrEqualTo(bar.bottom));
    expect(tester.getSize(_plus), const Size(48, 48));
    await h.openMenu(tester);
    await tester.tap(_tile('searchAdd'));
    await tester.pumpAndSettle();
    expect(h.calls, ['searchAdd']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion removes the plus transition but keeps its action',
      (tester) async {
    final h = _HeaderHost(disableAnimations: true);
    await h.mount(tester);
    await h.openMenu(tester);
    expect(tester.widget<AnimatedRotation>(_rotation).duration, Duration.zero);
    await tester.tap(_tile('scanQRCode'));
    await tester.pumpAndSettle();
    expect(h.calls, ['scanQRCode']);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('export contacts header and menu (${dark ? 'dark' : 'light'})',
        (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await tester.runAsync(_loadPreviewFonts);
        final h = _HeaderHost(dark: dark, previewFont: 'ContactsHeaderPreview');
        await h.mount(tester);
        await _export(tester, h, 'header');
        await h.openMenu(tester);
        await _export(tester, h, 'menu');
        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = previousShadows;
      }
    }, skip: _previewDirectory.isEmpty);
  }
}

final _title = find.byKey(const ValueKey('contacts-title-text'));
final _line = find.byKey(const ValueKey('contacts-title-indicator-line'));
final _dot = find.byKey(const ValueKey('contacts-title-indicator-dot'));
final _plus = find.byWidgetPredicate((widget) =>
    widget is IconButton &&
    (widget.tooltip == '添加' || widget.tooltip == 'Add'));
final _rotation =
    find.descendant(of: _plus, matching: find.byType(AnimatedRotation));
Finder _tile(String id) => find.byWidgetPredicate(
    (widget) => widget is HomeQuickActionTile && widget.action.id == id);
List<String> _menuIDs(WidgetTester tester) => tester
    .widgetList<HomeQuickActionTile>(find.byType(HomeQuickActionTile))
    .map((widget) => widget.action.id)
    .toList();

class _HeaderHost {
  _HeaderHost({
    this.dark = false,
    this.size = const Size(375, 812),
    this.padding = const EdgeInsets.only(top: 44),
    this.locale = const Locale('zh', 'CN'),
    this.sdkStatus,
    this.initialStatus = IMSdkStatus.connectionSucceeded,
    this.textScale = 1,
    this.disableAnimations = false,
    this.previewFont,
  });

  final bool dark;
  final Size size;
  final EdgeInsets padding;
  final Locale locale;
  final Stream<IMSdkStatus>? sdkStatus;
  final IMSdkStatus initialStatus;
  final double textScale;
  final bool disableAnimations;
  final String? previewFont;
  final calls = <String>[];
  final previewKey = GlobalKey();
  int bodyBuilds = 0;

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fontSize = size.width > 900
        ? AppTokens.mainTabTitleDesktopFontSize
        : AppTokens.mainTabTitleFontSize;
    final toolbarHeight = math.max(kToolbarHeight, fontSize * textScale + 24);
    await tester.pumpWidget(RepaintBoundary(
      key: previewKey,
      child: GetMaterialApp(
        debugShowCheckedModeBanner: false,
        translations: TranslationService(),
        locale: locale,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          platform: TargetPlatform.iOS,
          fontFamily: previewFont,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: padding,
            viewPadding: padding,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor:
              dark ? AppTokens.backgroundDark : AppTokens.surfaceLight,
          appBar: ContactsHeader(
            onSearchAdd: () => calls.add('searchAdd'),
            onCreateGroup: () => calls.add('createGroup'),
            onScan: () => calls.add('scanQRCode'),
            sdkStatus: sdkStatus,
            initialStatus: initialStatus,
            toolbarHeight: toolbarHeight,
          ),
          body: Builder(builder: (_) {
            bodyBuilds++;
            return const SizedBox.expand();
          }),
        ),
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(_plus);
    await tester.pumpAndSettle();
  }

  Future<void> dismissMenu(WidgetTester tester) async {
    await tester.tapAt(Offset(5, size.height - 10));
    await tester.pumpAndSettle();
    expect(find.byType(HomeQuickActionTile), findsNothing);
  }
}

Future<void> _loadPreviewFonts() async {
  final file = File('C:/Windows/Fonts/msyh.ttc');
  if (await file.exists()) {
    final bytes = ByteData.sublistView(await file.readAsBytes());
    for (final family in [
      'ContactsHeaderPreview',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
  final icons = File(
      'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final iconBytes = await icons.exists()
      ? ByteData.sublistView(await icons.readAsBytes())
      : await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')..addFont(Future.value(iconBytes))).load();
}

Future<void> _export(WidgetTester tester, _HeaderHost h, String name) async {
  final boundary =
      h.previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File(
          '$_previewDirectory/contacts-$name-${h.dark ? 'dark' : 'light'}.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
