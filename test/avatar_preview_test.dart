import 'dart:ui' as ui;
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final isGroup in [false, true]) {
    testWidgets('${isGroup ? 'group' : 'user'} avatar preview has save button',
        (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(48, 48);
      picture.dispose();
      final provider = ExtendedNetworkImageProvider(
          'https://example.com/avatar.png',
          cache: true,
          timeLimit: const Duration(seconds: 20),
          retries: 1,
          timeRetry: const Duration(seconds: 1),
          printError: false);
      provider.imageCache.putIfAbsent(
          provider,
          () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: image))));
      addTearDown(() {
        Get.reset();
        provider.imageCache.clear();
        provider.imageCache.clearLiveImages();
      });
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          home: Scaffold(
            body: Center(
              child: AvatarView(
                width: 48,
                height: 48,
                url: 'https://example.com/avatar.png',
                isGroup: isGroup,
                enabledPreview: true,
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find
          .descendant(
            of: find.byType(AvatarView),
            matching: find.byType(GestureDetector),
          )
          .first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      expect(find.byType(IconButton), findsOneWidget);
    });
  }
}
