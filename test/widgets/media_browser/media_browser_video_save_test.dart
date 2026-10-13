import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
// Test-only adapter for the path_provider dependency owned by openim_common.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/performance/render_test_fakes.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  testWidgets(
      'shared preview saves video as a file, deduplicates and clears spinner',
      (tester) async {
    final directory = await tester
        .runAsync(() => Directory.systemTemp.createTemp('preview-save-'));
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory!.path);
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    EasyLoading.instance
      ..animationDuration = Duration.zero
      ..displayDuration = const Duration(seconds: 1);
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    final source = (await tester.runAsync(() =>
        File('${directory.path}/video.bin').writeAsBytes([
          0,
          0,
          0,
          24,
          ...ascii.encode('ftypisom'),
          ...List.filled(64, 0)
        ])))!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const gallery = MethodChannel('image_gallery_saver_plus');
    const permissions =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    final calls = <MethodCall>[];
    final writing = Completer<Map<String, Object>>();
    messenger.setMockMethodCallHandler(permissions,
        (call) async => {for (final id in call.arguments as List) id: 1});
    messenger.setMockMethodCallHandler(gallery, (call) {
      calls.add(call);
      return writing.future;
    });
    addTearDown(() async {
      if (!writing.isCompleted) writing.complete({'isSuccess': false});
      await EasyLoading.dismiss(animation: false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      messenger.setMockMethodCallHandler(gallery, null);
      messenger.setMockMethodCallHandler(permissions, null);
      PathProviderPlatform.instance = previousPaths;
      debugDefaultTargetPlatformOverride = previousPlatform;
      await tester.runAsync(() => directory.delete(recursive: true));
      Get.reset();
    });
    late BuildContext host;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        builder: EasyLoading.init(),
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: Builder(builder: (context) {
          host = context;
          return const Scaffold(body: Text('chat'));
        }),
      ),
    ));
    unawaited(
        IMUtils.previewMediaFile(context: host, message: Message(), sources: [
      MediaSource(thumbnail: '', bytes: renderTestPng(), tag: 'image'),
      MediaSource(thumbnail: '', file: source, isVideo: true, tag: 'video'),
    ]));
    await tester.pumpAndSettle();
    final save = tester.widget<MediaBrowser>(find.byType(MediaBrowser)).onSave!;
    // Invoke the selected source's callback without initializing a desktop
    // video player. This is the same callback wired to all three save buttons.
    save(1);
    save(1);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(calls, hasLength(1));
    expect(calls.single.method, 'saveFileToGallery');
    expect(calls.single.arguments['file'], endsWith('.mp4'));
    expect(find.text('视频仍在写入，请稍后查看相册'), findsOneWidget);
    writing.complete({'isSuccess': true});
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text(StrRes.saveSuccessfully), findsOneWidget);
    expect(find.text('视频仍在写入，请稍后查看相册'), findsNothing);
    expect(tester.takeException(), isNull);
    await EasyLoading.dismiss(animation: false);
    Navigator.of(host).pop();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = previousPlatform;
  });
}
