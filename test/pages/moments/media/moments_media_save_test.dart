import 'dart:async';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/moments/media/moments_media_gallery.dart';
import 'package:openim/pages/moments/moments_media_preview.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../support/performance/render_test_fakes.dart';

const _gallery = MethodChannel('image_gallery_saver_plus');
const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
const _deviceInfo = MethodChannel('dev.fluttercommunity.plus/device_info');
const _post = MomentPost(
  momentId: 'save-preview',
  author: renderTestUser,
  mediaList: [MomentMedia(mediaId: 'first'), MomentMedia(mediaId: 'second')],
);

class _GalleryFixture {
  final writes = <MethodCall>[];
  final permissionRequests = <int>[];
  bool allowed = true;
  bool saved = true;
  int sdk = 34;
  Completer<Map<int, int>>? permissionGate;
  Completer<Map<String, Object>>? writeGate;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_gallery, (call) async {
      writes.add(call);
      return writeGate?.future ?? {'isSuccess': saved};
    });
    messenger.setMockMethodCallHandler(_permissions, (call) async {
      if (call.method != 'requestPermissions') return 1;
      final ids = List<int>.from(call.arguments as List);
      permissionRequests.addAll(ids);
      return permissionGate?.future ??
          {for (final id in ids) id: allowed ? 1 : 0};
    });
    messenger.setMockMethodCallHandler(
        _deviceInfo,
        (_) async => {
              'version': {
                'sdkInt': sdk,
                'baseOS': '',
                'codename': '',
                'incremental': '',
                'previewSdkInt': 0,
                'release': '',
                'securityPatch': '',
              },
              for (final key in [
                'board',
                'bootloader',
                'brand',
                'device',
                'display',
                'fingerprint',
                'hardware',
                'host',
                'id',
                'manufacturer',
                'model',
                'product',
                'tags',
                'type',
                'serialNumber',
              ])
                key: 'test',
              'isPhysicalDevice': true,
              'isLowRamDevice': false,
              'freeDiskSize': 1,
              'totalDiskSize': 1,
              'physicalRamSize': 1,
              'availableRamSize': 1,
            });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_gallery, null);
      messenger.setMockMethodCallHandler(_permissions, null);
      messenger.setMockMethodCallHandler(_deviceInfo, null);
    });
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<MomentsRepository> _mount(WidgetTester tester, RenderTestApi api,
    {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = renderTestRepository(api)..applyPost(_post);
  addTearDown(repository.dispose);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      builder: EasyLoading.init(),
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
          body: MomentsMediaPreview(
        repository: repository,
        post: _post,
        initialIndex: 0,
      )),
    ),
  ));
  await _frames(tester);
  return repository;
}

void _testMobile(String name, WidgetTesterCallback body,
    {TargetPlatform platform = TargetPlatform.iOS}) {
  testWidgets(name, (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      await EasyLoading.dismiss(animation: false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    EasyLoading.instance
      ..animationDuration = Duration.zero
      ..displayDuration = const Duration(seconds: 1);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    Get.reset();
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    _testMobile('save button writes selected original / $platform',
        (tester) async {
      final gallery = _GalleryFixture()..install();
      final original = renderTestPng();
      await _mount(
          tester, RenderTestApi()..mediaWork = (_, __) async => original,
          brightness: platform == TargetPlatform.android
              ? Brightness.dark
              : Brightness.light);
      expect(find.byTooltip(StrRes.saveToAlbum), findsOneWidget);
      await tester.tap(find.byTooltip(StrRes.saveToAlbum));
      await _frames(tester);
      expect(gallery.writes, hasLength(1));
      expect(gallery.writes.single.method, 'saveImageToGallery');
      expect(gallery.writes.single.arguments['imageBytes'], original);
      expect(gallery.writes.single.arguments['quality'], 100);
      expect(gallery.writes.single.arguments['name'], startsWith('moment_'));
      expect(
          gallery.permissionRequests,
          platform == TargetPlatform.iOS
              ? [Permission.photosAddOnly.value]
              : isEmpty);
      expect(find.text(StrRes.saveSuccessfully), findsOneWidget);
      expect(find.byType(MediaBrowser), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, platform: platform);
  }

  _testMobile('swipe saves full current image once after its pending load',
      (tester) async {
    final gallery = _GalleryFixture()..install();
    gallery.writeGate = Completer();
    final original = Uint8List.fromList([...renderTestPng(), 1]);
    final thumbnail = Uint8List.fromList([...renderTestPng(), 2]);
    final pending = Completer<Uint8List>();
    final api = RenderTestApi()
      ..mediaWork = (media, thumb) async => media.mediaId == 'second'
          ? (thumb ? thumbnail : pending.future)
          : renderTestPng();
    await _mount(tester, api);
    await tester.drag(
        find.byType(ExtendedImageGesturePageView), const Offset(-550, 0));
    await _frames(tester);
    expect(find.textContaining('2/2'), findsOneWidget);
    await tester.tap(find.byTooltip(StrRes.saveToAlbum));
    await tester.tap(find.byTooltip(StrRes.saveToAlbum));
    await _frames(tester);
    expect(gallery.writes, isEmpty);
    expect(
        api.mediaCalls.where((call) => call == 'second:false'), hasLength(1));
    pending.complete(original);
    await _frames(tester);
    await tester.tap(find.byTooltip(StrRes.saveToAlbum));
    expect(gallery.writes, hasLength(1));
    expect(gallery.writes.single.arguments['imageBytes'], original);
    gallery.writeGate!.complete({'isSuccess': true});
    await _frames(tester);
    expect(find.text(StrRes.saveSuccessfully), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _testMobile('long press exposes save and cancel preserves the preview',
      (tester) async {
    final gallery = _GalleryFixture()..install();
    await _mount(tester, RenderTestApi());
    await tester.longPress(find.byType(ExtendedImageGesturePageView));
    await tester.pumpAndSettle();
    expect(find.text(StrRes.saveToAlbum), findsOneWidget);
    await tester.tap(find.text(StrRes.cancel));
    await tester.pumpAndSettle();
    expect(gallery.writes, isEmpty);
    await tester.longPress(find.byType(ExtendedImageGesturePageView));
    await tester.pumpAndSettle();
    await tester.tap(find.text(StrRes.saveToAlbum));
    await _frames(tester);
    expect(gallery.writes, hasLength(1));
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _testMobile(
      'permission denial and native failure report a result and allow retry',
      (tester) async {
    final gallery = _GalleryFixture()
      ..allowed = false
      ..install();
    await _mount(tester, RenderTestApi());
    await tester.tap(find.byTooltip(StrRes.saveToAlbum));
    await _frames(tester);
    expect(gallery.writes, isEmpty);
    expect(find.text('保存失败，请允许添加照片到相册'), findsOneWidget);
    gallery.allowed = true;
    gallery.saved = false;
    await tester.tap(find.byTooltip(StrRes.saveToAlbum));
    await _frames(tester);
    expect(find.text(StrRes.saveFailed), findsOneWidget);
    gallery.saved = true;
    await tester.tap(find.byTooltip(StrRes.saveToAlbum));
    await _frames(tester);
    expect(gallery.writes, hasLength(2));
    expect(find.text(StrRes.saveSuccessfully), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _testMobile('revocation while permission is pending prevents gallery write',
      (tester) async {
    final gallery = _GalleryFixture()
      ..permissionGate = Completer()
      ..install();
    final repository = await _mount(tester, RenderTestApi());
    await tester.tap(find.byTooltip(StrRes.saveToAlbum));
    await _frames(tester);
    repository.resetSession();
    await tester.pump();
    gallery.permissionGate!.complete({Permission.photosAddOnly.value: 1});
    await _frames(tester);
    expect(gallery.writes, isEmpty);
    expect(find.byType(MediaBrowser), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _testMobile('closing while original is pending prevents late save',
      (tester) async {
    final gallery = _GalleryFixture()..install();
    final pending = Completer<Uint8List>();
    await _mount(
        tester,
        RenderTestApi()
          ..mediaWork = (media, thumb) async =>
              media.mediaId == 'second' && !thumb
                  ? pending.future
                  : renderTestPng());
    final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    browser.onSave!(1);
    await _frames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(renderTestPng());
    await _frames(tester);
    expect(gallery.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('Android 28 asks storage permission before writing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final gallery = _GalleryFixture()
      ..sdk = 28
      ..allowed = false
      ..install();
    final result =
        await saveMomentImageToGallery(renderTestPng(), isCurrent: () => true);
    expect(result, MomentsMediaSaveResult.permissionDenied);
    expect(gallery.permissionRequests, [Permission.storage.value]);
    expect(gallery.writes, isEmpty);
  });
}
