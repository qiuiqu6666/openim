import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/moments/moments_likes_page.dart';
import 'package:openim/pages/moments/moments_media_preview.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/moments_ui_fixture.dart';
import '../support/moments_ui_host.dart';

final _export = Platform.environment['EXPORT_MOMENTS_UI_PREVIEW'] == '1' ||
    const String.fromEnvironment('EXPORT_MOMENTS_UI_PREVIEW') == '1';

Future<void> _fonts() async {
  final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  for (final name in [
    'MomentsPreviewFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay'
  ]) {
    await (FontLoader(name)..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    if (_export) await _fonts();
  });

  for (final surface in ['likes', 'media-loading', 'media-error']) {
    for (final dark in [false, true]) {
      testWidgets('actual $surface production page in $dark', (tester) async {
        final fixture = MomentsUiFixture();
        addTearDown(fixture.dispose);
        addTearDown(Get.reset);
        final post = fixture.api.posts[momentsUiFriendPostId]!;
        fixture.repository.applyPost(post);
        final pending = Completer<Uint8List>();
        fixture.api.mediaWork = (_, __) async {
          if (surface == 'media-error') {
            throw const MomentsException('MEDIA_UNAVAILABLE',
                code: 'MEDIA_UNAVAILABLE');
          }
          return pending.future;
        };
        final page = surface == 'likes'
            ? MomentsLikesPage(
                repository: fixture.repository, momentId: post.momentId)
            : MomentsMediaPreview(
                repository: fixture.repository, post: post, initialIndex: 0);
        final key = GlobalKey();
        Styles.isDark = dark;
        addTearDown(() => Styles.isDark = false);
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => GetMaterialApp(
                debugShowCheckedModeBanner: false,
                locale: const Locale('zh', 'CN'),
                supportedLocales: const [Locale('zh', 'CN')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: momentsUiTheme(dark,
                    fontFamily: _export ? 'MomentsPreviewFont' : null),
                home: RepaintBoundary(key: key, child: page))));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
        // Asset decoding uses the engine rather than the test clock. Wait for
        // the real empty-state image before capturing its first (light) case.
        if (surface != 'media-loading') {
          final providers = tester
              .widgetList<Image>(find.byType(Image))
              .map((image) => image.image)
              .toList(growable: false);
          await tester.runAsync(() async {
            for (final provider in providers) {
              await precacheImage(provider, key.currentContext!);
            }
          });
          await tester.pumpAndSettle();
        }
        if (surface == 'likes') {
          expect(find.text('阿南'), findsOneWidget);
          expect(find.text('阿雯'), findsOneWidget);
        } else if (surface == 'media-error') {
          expect(find.text('图片加载失败'), findsOneWidget);
          expect(find.text('重试'), findsOneWidget);
        } else {
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        if (_export) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              if (surface != 'likes') {
                final data =
                    await image.toByteData(format: ui.ImageByteFormat.rawRgba);
                final pixels = data!.buffer.asUint8List();
                var backPixels = 0, titlePixels = 0;
                for (var y = 0; y < 112; y++) {
                  for (var x = 0; x < 280; x++) {
                    final offset = (y * image.width + x) * 4;
                    if (pixels[offset] > 160 &&
                        pixels[offset + 1] > 160 &&
                        pixels[offset + 2] > 160) {
                      if (x < 96) {
                        backPixels++;
                      } else {
                        titlePixels++;
                      }
                    }
                  }
                }
                expect(backPixels, greaterThan(40));
                expect(titlePixels, greaterThan(80));
              }
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File('docs/previews/moments-99chat-$surface-'
                  '${dark ? 'dark' : 'light'}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        if (!pending.isCompleted) pending.complete(Uint8List(0));
        await tester.pumpAndSettle();
      });
    }
  }
}
