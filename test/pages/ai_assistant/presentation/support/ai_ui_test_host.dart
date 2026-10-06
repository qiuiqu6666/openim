import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/ai_assistant/controller/ai_assistant_controller.dart';
import 'package:openim/pages/ai_assistant/models/ai_assistant_models.dart';
import 'package:openim/pages/ai_assistant/presentation/ai_assistant_widgets.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

final aiPreviewDirectory =
    Platform.environment['AI_ASSISTANT_PREVIEW_DIR'] ?? '';
late Uint8List aiTestImage;

Future<void> initializeAiUiTests() async {
  SharedPreferences.setMockInitialValues({});
  await SpUtil().init();
  await NavigationGlassController.instance
      .setMode(NavigationGlassMode.translucent);
  aiTestImage = await File('assets/ai/welcome.jpg').readAsBytes();
  Get.testMode = true;
}

Future<void> resetAiUiTests() async {
  await dismissAiUiTestLoading();
  Get.reset();
}

Future<void> dismissAiUiTestLoading() => EasyLoading.dismiss(animation: false);

/// This test controller uses a static session and disables all gateway requests.
class AiUiTestController extends AiAssistantController {
  AiUiTestController({
    List<AiAssistantMessage> initialMessages = const [],
    bool guide = false,
    bool welcome = false,
  }) : super(
          sessionProvider: () =>
              (userID: 'ui-test-user', token: 'ui-test-token'),
          serviceEnabled: false,
        ) {
    messages.addAll(initialMessages);
    guideVisible = guide;
    welcomeVisible = welcome;
    historyLoaded = true;
  }

  @override
  Future<void> initialize() async {}
}

class AiUiTestHost {
  AiUiTestHost({
    this.dark = false,
    this.size = const Size(375, 812),
    this.padding = const EdgeInsets.fromLTRB(0, 44, 0, 34),
    this.viewInsets = EdgeInsets.zero,
    this.textScale = 1,
    this.disableAnimations = false,
    this.locale = const Locale('zh', 'CN'),
    this.previewFont = false,
  });

  final bool dark;
  final Size size;
  final EdgeInsets padding;
  final EdgeInsets viewInsets;
  final double textScale;
  final bool disableAnimations;
  final Locale locale;
  final bool previewFont;
  final previewKey = GlobalKey();

  Future<void> mount(WidgetTester tester, Widget child,
      {bool settle = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
      key: previewKey,
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          translations: TranslationService(),
          locale: locale,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'TW'),
            Locale('en'),
            Locale('ja'),
            Locale('ko'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            platform: TargetPlatform.iOS,
            fontFamily: previewFont ? 'AiAssistantPreview' : null,
            colorSchemeSeed: AppTokens.accent,
          ),
          builder: EasyLoading.init(
              builder: (context, app) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: padding.copyWith(
                          bottom: (padding.bottom - viewInsets.bottom)
                              .clamp(0.0, double.infinity)),
                      viewPadding: padding,
                      viewInsets: viewInsets,
                      textScaler: TextScaler.linear(textScale),
                      disableAnimations: disableAnimations,
                    ),
                    child: app!,
                  )),
          home: child,
        ),
      ),
    ));
    final context = previewKey.currentContext!;
    await tester.runAsync(() => Future.wait([
          for (final asset in [
            ...AiFirstGuide.assets,
            'assets/ai/bg.png',
            'assets/ai/99chat.webp',
            'assets/ai/welcome.jpg',
          ])
            precacheImage(AssetImage(asset), context),
        ]));
    await tester.pump();
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Widget scaffold(WidgetBuilder builder) => Scaffold(
        backgroundColor: AiPalette.canvasBg(dark),
        body: SafeArea(child: Builder(builder: builder)),
      );

  Future<void> export(WidgetTester tester, String name) async {
    if (aiPreviewDirectory.isEmpty) return;
    final boundary =
        previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    _markSubtreeNeedsPaint(boundary);
    await tester.pump();
    final titleRect = tester.getRect(find.text('99ChatAI'));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final pixels =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        // Action-sheet dimming changes absolute colors but preserves contrast.
        final backgroundOffset =
            ((titleRect.center.dy * 2).floor() * image.width) * 4;
        final backgroundBrightness = (pixels!.getUint8(backgroundOffset) +
                pixels.getUint8(backgroundOffset + 1) +
                pixels.getUint8(backgroundOffset + 2)) /
            3;
        var titleInkPixels = 0;
        for (var y = (titleRect.top * 2).ceil();
            y < (titleRect.bottom * 2).floor();
            y++) {
          for (var x = (titleRect.left * 2).ceil();
              x < (titleRect.right * 2).floor();
              x++) {
            final offset = (y * image.width + x) * 4;
            final red = pixels.getUint8(offset);
            final green = pixels.getUint8(offset + 1);
            final blue = pixels.getUint8(offset + 2);
            final brightness = (red + green + blue) / 3;
            if ((brightness - backgroundBrightness).abs() > 40) {
              titleInkPixels++;
            }
          }
        }
        expect(titleInkPixels, greaterThan(50),
            reason:
                'The exported $name header must contain painted title text.');
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final target = File('$aiPreviewDirectory/ai-$name-'
            '${dark ? 'dark' : 'light'}.png');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(png!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
}

void _markSubtreeNeedsPaint(RenderObject object) {
  object.visitChildren(_markSubtreeNeedsPaint);
  object.markNeedsPaint();
}

Future<void> loadAiPreviewFonts() async {
  final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  for (final family in [
    'AiAssistantPreview',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final icons = File('E:/flutter/flutter/bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf');
  final iconBytes = await icons.exists()
      ? ByteData.sublistView(await icons.readAsBytes())
      : await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')..addFont(Future.value(iconBytes))).load();
  await (FontLoader('packages/font_awesome_flutter/FontAwesomeSolid')
        ..addFont(rootBundle
            .load('packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf')))
      .load();
}

const aiTestCard = AiAssistantCardRef(
  kind: AiAssistantCardKind.friend,
  id: 'fixture-friend',
  name: '测试好友',
);
const aiTestFile = AiAssistantFileRef(
  name: '项目计划.pdf',
  sizeLabel: '128 KB',
  kind: AiAssistantFileKind.pdf,
  fileId: 'fixture-pdf',
);

/// Conversation fixtures exist only in tests and are never production replies.
const aiTestConversation = <AiAssistantMessage>[
  AiAssistantMessage(
    role: AiAssistantRole.user,
    time: '14:30',
    text: '帮我整理这次讨论的重点。',
  ),
  AiAssistantMessage(
    role: AiAssistantRole.assistant,
    time: '14:30',
    outputKind: AiAssistantOutputKind.text,
    text: '**讨论重点**\n\n确认项目目标和下一步安排。',
  ),
  AiAssistantMessage(
    role: AiAssistantRole.user,
    time: '14:31',
    cards: [aiTestCard],
    files: [aiTestFile],
  ),
  AiAssistantMessage(
    role: AiAssistantRole.assistant,
    time: '14:31',
    outputKind: AiAssistantOutputKind.summary,
    summary: AiAssistantSummaryData(
      title: '讨论总结',
      meta: '项目讨论 · 2 个重点',
      items: ['明确本周计划', '确认负责人员'],
      footer: '也可以继续整理行动清单。',
    ),
  ),
];
