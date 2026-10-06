import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/moments/moments_detail_page.dart';
import 'package:openim/pages/moments/moments_page.dart';
import 'package:openim/pages/moments/media/moments_media_image.dart';
import 'package:openim/services/moments_models.dart';
import 'package:openim_common/openim_common.dart';

import 'moments_ui_fixture.dart';

enum MomentsUiSurface { feed, profile, detail }

/// Wait for the real protected descriptor and the displayed resize provider,
/// whose native codecs are not advanced by widget fake time. Screenshots must
/// capture loaded pixels rather than a success state with an undecoded image.
Future<void> settleVisibleMomentsUiMedia(WidgetTester tester) async {
  final pending = tester
      .widgetList<FutureBuilder>(find.descendant(
          of: find.byType(MomentsMediaImage),
          matching:
              find.byWidgetPredicate((widget) => widget is FutureBuilder)))
      .map((widget) => widget.future)
      .whereType<Future>();
  await tester.runAsync(() => Future.wait(pending));
  await tester.pump();
  final providers = tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .toSet();
  await tester.runAsync(() => Future.wait(providers.map(_decodeImage)));
  await tester.pumpAndSettle();
}

Future<void> _decodeImage(ImageProvider provider) async {
  final stream = provider.resolve(ImageConfiguration.empty);
  final completer = Completer<void>();
  late ImageStreamListener listener;
  listener = ImageStreamListener((_, __) {
    if (!completer.isCompleted) completer.complete();
    stream.removeListener(listener);
  }, onError: (Object error, StackTrace? stack) {
    if (!completer.isCompleted) completer.completeError(error, stack);
    stream.removeListener(listener);
  });
  stream.addListener(listener);
  await completer.future;
}

/// Real package bytes are decoded outside widget fake time, so the page can
/// settle deterministically while still exercising its real media widget.
Future<void> prepareMomentsUiPhotos(
    WidgetTester tester, MomentsUiFixture fixture) async {
  await tester.runAsync(() async {
    await fixture.loadPhotos();
    final providers = <ImageProvider>[
      ...fixture.api.mediaBytes.values.map(MemoryImage.new),
      const AssetImage('assets/images/moments_cover_99chat.webp',
          package: 'openim_common'),
    ];
    addTearDown(() async {
      for (final provider in providers) {
        await provider.evict();
      }
    });
    for (final provider in providers) {
      await _decodeImage(provider);
    }
  });
}

/// Matches ChatApp's inherited theme; Moments owns its reference page colors.
ThemeData momentsUiTheme(bool dark, {String? fontFamily}) {
  final brightness = dark ? Brightness.dark : Brightness.light;
  final surface = dark ? const Color(0xFF202A36) : Colors.white;
  final foreground = dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
  final label = TextStyle(
      color: CupertinoColors.label, fontSize: 17, fontFamily: fontFamily);
  return ThemeData(
    fontFamily: fontFamily,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0089FF),
            brightness: brightness,
            surface: surface)
        .copyWith(onSurface: foreground),
    scaffoldBackgroundColor:
        dark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: CupertinoColors.systemBlue,
      applyThemeToAll: true,
      textTheme: const CupertinoTextThemeData().copyWith(
          textStyle: label,
          actionTextStyle: label.copyWith(color: CupertinoColors.systemBlue)),
    ),
  );
}

/// A real route, not a mock rendering. Settle can be disabled for first-frame
/// gates, so initial loading and stale responses are not hidden by screenshots.
Future<void> mountMomentsUi(
  WidgetTester tester, {
  required MomentsUiFixture fixture,
  MomentsUiSurface surface = MomentsUiSurface.feed,
  bool dark = false,
  Locale locale = const Locale('zh', 'CN'),
  Size size = const Size(375, 812),
  double devicePixelRatio = 1,
  double textScale = 1,
  bool reducedMotion = false,
  String? fontFamily,
  String? authorId,
  MomentUser? profileUser,
  String momentId = momentsUiFriendPostId,
  GlobalKey? previewKey,
  bool settle = true,
}) async {
  Get.testMode = true;
  Styles.isDark = dark;
  tester.view.physicalSize = size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => Styles.isDark = false);
  addTearDown(Get.reset);
  final page = switch (surface) {
    MomentsUiSurface.feed => MomentsPage(
        repository: fixture.repository,
        profileUser: profileUser ?? momentsUiSelf),
    MomentsUiSurface.profile => MomentsPage(
        repository: fixture.repository,
        authorId: authorId ?? momentsUiSelf.userId,
        profileUser: profileUser ?? momentsUiSelf),
    MomentsUiSurface.detail =>
      MomentsDetailPage(repository: fixture.repository, momentId: momentId),
  };
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) {
      final app = GetMaterialApp(
        debugShowCheckedModeBanner: false,
        translations: TranslationService(),
        locale: locale,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: momentsUiTheme(dark, fontFamily: fontFamily),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 34),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: page,
      );
      return previewKey == null
          ? app
          : RepaintBoundary(key: previewKey, child: app);
    },
  ));
  if (settle) await tester.pumpAndSettle();
}
