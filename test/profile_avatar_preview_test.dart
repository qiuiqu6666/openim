import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/pages/profile_info_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets(
      'name editor opens an uncropped full-screen avatar and closes cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 40, 20),
        Paint()..color = AppTokens.accent,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(40, 20);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      store.setProfileAvatarPreview(data!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
    Styles.isDark = false;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ProfileInfoPage(
          nickname: '秋秋',
          userId: 'user-1',
          avatarUrl: '',
          store: store,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('名字'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ClipOval).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('查看头像'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final preview = find.byType(MediaBrowser);
    expect(preview, findsOneWidget);
    expect(tester.getSize(preview), const Size(375, 812));
    expect(find.byType(Dialog), findsNothing);
    expect(find.descendant(of: preview, matching: find.byType(ClipOval)),
        findsNothing);
    final image = tester.widget<ExtendedImage>(
      find.descendant(of: preview, matching: find.byType(ExtendedImage)),
    );
    expect(image.fit, BoxFit.contain);
    expect(image.mode, ExtendedImageMode.gesture);
    expect(tester.widget<MediaBrowser>(preview).sources.single.bytes,
        same(store.profileAvatarPreviewBytes));
    expect(find.byType(ChatPicturePreview), findsNothing);
    expect(find.byIcon(Icons.download), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
    expect(find.descendant(of: preview, matching: find.text('秋秋')), findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('1/1')), findsNothing);

    await tester.tapAt(const Offset(180, 400));
    await tester.pump();
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(find.byIcon(Icons.download), findsNothing);
    await tester.tapAt(const Offset(180, 400));
    await tester.pump();
    await tester.tap(find.descendant(
      of: preview,
      matching: find.byIcon(Icons.arrow_back_ios_new),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsNothing);
    expect(find.text('确定'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
