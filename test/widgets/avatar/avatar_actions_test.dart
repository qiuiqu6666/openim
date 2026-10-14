import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/set_remark_view.dart';
import 'package:openim/pages/register/set_password/widgets/registration_avatar_picker.dart';
import 'package:openim_common/openim_common.dart';

import '../../support/performance/render_test_fakes.dart' show renderTestPng;

const _url = 'https://media.example.test/editable-avatar.png';

void _cacheAvatar() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(AppTokens.accent, BlendMode.src);
  final picture = recorder.endRecording();
  final provider = ExtendedNetworkImageProvider(_url,
      cache: true,
      timeLimit: const Duration(seconds: 20),
      retries: 1,
      timeRetry: const Duration(seconds: 1),
      printError: false);
  final image = picture.toImageSync(80, 120);
  picture.dispose();
  provider.imageCache.putIfAbsent(
      provider,
      () =>
          OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image))));
}

Future<void> _mount(WidgetTester tester, Widget child, bool dark) async {
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final dark in [false, true]) {
    testWidgets('read-only name editor previews without saving ($dark)',
        (tester) async {
      _cacheAvatar();
      final draft = TextEditingController(text: '未保存的备注');
      var saved = 0;
      await _mount(
          tester,
          SetFriendRemarkPage.editor(
            controller: draft,
            avatarURL: _url,
            maxLength: 30,
            onSave: () => saved++,
          ),
          dark);
      await tester.tap(find.byType(AvatarView));
      await tester.pumpAndSettle();
      expect(find.byType(ChatPicturePreview), findsOneWidget);
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(saved, 0);
      Get.back();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(draft.text, '未保存的备注');
      expect(saved, 0);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
      expect(tester.takeException(), isNull);
    });

    testWidgets('photo menu previews or cancels without picker/upload ($dark)',
        (tester) async {
      _cacheAvatar();
      var updates = 0;
      await _mount(
          tester,
          Scaffold(
            body: TextButton(
              onPressed: () => IMViews.openPhotoSheet(
                avatarUrl: _url,
                onData: (_, __) => updates++,
              ),
              child: const Text('编辑头像'),
            ),
          ),
          dark);
      await tester.tap(find.text('编辑头像'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.text(StrRes.toolboxAlbum), findsOneWidget);
      expect(find.text(StrRes.toolboxCamera), findsOneWidget);
      await tester.tap(find.text(StrRes.viewAvatar));
      await tester.pumpAndSettle();
      expect(find.byType(ChatPicturePreview), findsOneWidget);
      expect(updates, 0);
      Get.back();
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑头像'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('编辑头像'), findsOneWidget);
      expect(updates, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'registration avatar can preview then change local photo ($dark)',
        (tester) async {
      var changes = 0;
      final bytes = renderTestPng();
      await _mount(
          tester,
          Scaffold(
            body: RegistrationAvatarPicker(
              bytes: bytes,
              enabled: true,
              picking: false,
              onPick: () => changes++,
            ),
          ),
          dark);
      await tester.tap(find.byKey(const ValueKey('registration-avatar-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StrRes.viewAvatar));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
      expect(browser.sources.single.bytes, same(bytes));
      expect(browser.showGallery, isFalse);
      expect(changes, 0);
      Get.back();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('registration-avatar-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StrRes.selectAssetsFromAlbum));
      await tester.pumpAndSettle();
      expect(changes, 1);
      expect(find.byType(RegistrationAvatarPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('revoked avatar editing permission is rechecked after menu',
      (tester) async {
    var active = true;
    var changes = 0;
    await _mount(tester, Scaffold(body: Builder(builder: (context) {
      return TextButton(
        onPressed: () => AvatarActions.open(context,
            onChange: () => changes++, isActive: () => active),
        child: const Text('头像'),
      );
    })), false);
    await tester.tap(find.text('头像'));
    await tester.pumpAndSettle();
    expect(find.text(StrRes.viewAvatar), findsNothing);
    active = false;
    await tester.tap(find.text(StrRes.selectAssetsFromAlbum));
    await tester.pumpAndSettle();
    expect(changes, 0);
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
