import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/send_verification_application/widgets/verification_application_form.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  for (final dark in [false, true]) {
    testWidgets('target and manual submission remain readable in $dark theme',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var sends = 0;
      final previewKey = GlobalKey();
      await _mount(tester,
          controller: controller,
          onSend: () => sends++,
          dark: dark,
          previewKey: previewKey);

      expect(find.text('添加好友'), findsOneWidget);
      expect(find.text('测试好友'), findsOneWidget);
      expect(find.textContaining('demo_account'), findsOneWidget);
      expect(find.byKey(_target), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(_message));
      expect(field.autofocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
          tester.widget<FilledButton>(find.byKey(_send)).onPressed, isNotNull);
      if (_exportPreview) {
        await _export(tester, previewKey, dark ? 'dark' : 'light');
      }

      await tester.enterText(find.byKey(_message), '你好，想加你为好友');
      await tester.pump();
      expect(sends, 0);
      expect(controller.text, '你好，想加你为好友');

      await tester.ensureVisible(find.byKey(_send));
      await tester.tap(find.byKey(_send));
      await tester.pump();
      expect(sends, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('sending disables duplicate submission and editing in $dark',
        (tester) async {
      final controller = TextEditingController(text: '保留这段验证信息');
      addTearDown(controller.dispose);
      var sends = 0;
      await _mount(tester,
          controller: controller,
          onSend: () => sends++,
          dark: dark,
          sending: true);

      final send = tester.widget<FilledButton>(find.byKey(_send));
      expect(send.onPressed, isNull);
      final field = tester.widget<TextField>(find.byKey(_message));
      expect(field.enabled, isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.ensureVisible(find.byKey(_send));
      await tester.tap(find.byKey(_send));
      await tester.pump();
      expect(sends, 0);
      expect(controller.text, '保留这段验证信息');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('unavailable entry shows friendly guidance upfront in $dark',
        (tester) async {
      final controller = TextEditingController(text: '保留我的申请');
      addTearDown(controller.dispose);
      var sends = 0;
      const message = '请通过对方的聊天号、二维码或好友名片添加。';
      await _mount(tester,
          controller: controller,
          onSend: () => sends++,
          dark: dark,
          canSubmit: false,
          unavailableMessage: message);

      expect(find.text(message), findsOneWidget);
      expect(find.byKey(const ValueKey('verification-unavailable')),
          findsOneWidget);
      expect(find.textContaining('凭证'), findsNothing);
      expect(find.textContaining('grant'), findsNothing);
      expect(find.textContaining('FriendGrantRequired'), findsNothing);
      final guidance = tester.widget<Text>(find.text(message));
      expect(guidance.style?.color, AppTokens.textPrimary(dark: dark));
      expect(tester.widget<FilledButton>(find.byKey(_send)).onPressed, isNull);
      expect(tester.widget<TextField>(find.byKey(_message)).enabled, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.ensureVisible(find.byKey(_send));
      await tester.tap(find.byKey(_send));
      await tester.pump();
      expect(sends, 0);
      expect(controller.text, '保留我的申请');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('twenty-character limit preserves complete combined emoji',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller, onSend: () {});
    const family = '👨‍👩‍👧‍👦';
    final twenty = List.filled(20, family).join();
    final tooLong = '$twenty👋🏽';
    await tester.enterText(find.byKey(_message), tooLong);
    await tester.pump();

    expect(controller.text, twenty);
    expect(controller.text.characters.length, 20);
    expect(find.text('20/20'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('group verification keeps the correct title and prompt',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _mount(tester,
        controller: controller,
        onSend: () {},
        isEnterGroup: true,
        targetName: '测试群聊',
        targetAccount: '');

    expect(find.text('群聊验证'), findsOneWidget);
    expect(find.text('测试群聊'), findsOneWidget);
    expect(find.text('好友验证'), findsNothing);
    expect(find.textContaining('demo_account'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dark in [false, true]) {
    testWidgets(
        'small screen, large text and keyboard allow submission ($dark)',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var sends = 0;
      await _mount(tester,
          controller: controller,
          onSend: () => sends++,
          dark: dark,
          size: const Size(320, 640),
          textScale: 2,
          keyboardHeight: 280,
          targetName: '这是一个用于测试换行布局的较长好友昵称',
          targetAccount: 'a_long_display_account_12345678');

      await tester.enterText(find.byKey(_message), '换行验证信息\n第二行');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(_send));
      await tester.pumpAndSettle();
      final buttonRect = tester.getRect(find.byKey(_send));
      expect(buttonRect.top, greaterThanOrEqualTo(0));
      expect(buttonRect.bottom, lessThanOrEqualTo(640 - 280));
      await tester.tap(find.byKey(_send));
      await tester.pump();
      expect(sends, 1);
      expect(controller.text, '换行验证信息\n第二行');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

const _message = ValueKey('verification-message');
const _send = ValueKey('verification-send');
const _target = ValueKey('verification-target');

Future<void> _mount(
  WidgetTester tester, {
  required TextEditingController controller,
  required VoidCallback onSend,
  bool dark = false,
  bool sending = false,
  bool canSubmit = true,
  String? unavailableMessage,
  bool isEnterGroup = false,
  String targetName = '测试好友',
  String targetAccount = 'demo_account',
  Size size = const Size(375, 812),
  double textScale = 1,
  double keyboardHeight = 0,
  GlobalKey? previewKey,
}) async {
  Get.testMode = true;
  Styles.isDark = dark;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (_exportPreview && !_fontsLoaded) {
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
          fontFamily: _exportPreview ? 'VerificationPreviewFont' : null,
          brightness: dark ? Brightness.dark : Brightness.light,
          colorScheme: ColorScheme.fromSeed(
              seedColor: AppTokens.accent,
              brightness: dark ? Brightness.dark : Brightness.light),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 24, bottom: 34),
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          child: child!,
        ),
        home: VerificationApplicationForm(
          controller: controller,
          onSend: onSend,
          sending: sending,
          canSubmit: canSubmit,
          unavailableMessage: unavailableMessage,
          isEnterGroup: isEnterGroup,
          targetName: targetName,
          targetAccount: targetAccount,
        ),
      );
      return previewKey == null
          ? app
          : RepaintBoundary(key: previewKey, child: app);
    },
  ));
  // Sending intentionally keeps an animated progress indicator active.
  if (sending) {
    await tester.pump(const Duration(milliseconds: 100));
  } else {
    await tester.pumpAndSettle();
  }
}

final _exportPreview =
    Platform.environment['EXPORT_VERIFICATION_PREVIEW'] == '1';
bool _fontsLoaded = false;

Future<void> _loadPreviewFonts() async {
  final chinese = File('C:/Windows/Fonts/msyh.ttc');
  if (await chinese.exists()) {
    final bytes = ByteData.sublistView(await chinese.readAsBytes());
    await (FontLoader('VerificationPreviewFont')..addFont(Future.value(bytes)))
        .load();
  }
  final icons = File(
      'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final bytes = await icons.exists()
      ? ByteData.sublistView(await icons.readAsBytes())
      : await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')..addFont(Future.value(bytes))).load();
}

Future<void> _export(
    WidgetTester tester, GlobalKey key, String themeName) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final output =
          File('build/verification-preview/verification-99chat-$themeName.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
