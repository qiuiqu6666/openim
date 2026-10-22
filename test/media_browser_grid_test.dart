import 'package:extended_image/extended_image.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('loaded grid items open at the same action index',
      (tester) async {
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9ioAAAAASUVORK5CYII=');
    final sources = [
      MediaSource(
          thumbnail: '', tag: 'initial', bytes: bytes, sentAt: DateTime(2020))
    ];
    var loads = 0;
    int? forwarded;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) {
          ScreenUtil.init(context, designSize: const Size(375, 812));
          return child!;
        },
        home: MediaBrowser(
            initialIndex: 0,
            sources: sources,
            loadMoreMedia: () async {
              loads++;
              sources.add(MediaSource(
                  thumbnail: '',
                  tag: 'added',
                  bytes: bytes,
                  sentAt: DateTime(2026)));
              return false;
            },
            onForward: (index) => forwarded = index)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('图片和视频'));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.text('2 items loaded'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Photo 1'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.textContaining('2/2'), findsWidgets);
    await tester.tap(find.byTooltip('转发'));
    expect(forwarded, 1);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(loads, 1);
    await tester.tap(find.bySemanticsLabel('Photo 1'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Photo 1'));
    await tester.pumpAndSettle();
    final slide = tester
        .widget<ExtendedImageSlidePage>(find.byType(ExtendedImageSlidePage));
    final state = tester.state<ExtendedImageSlidePageState>(
        find.byType(ExtendedImageSlidePage));
    expect(
        slide.slideEndHandler!(const Offset(0, 900),
            state: state, details: ScaleEndDetails()),
        false);
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('gallery handles unavailable thumbnails without error widgets',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) {
        ScreenUtil.init(context, designSize: const Size(375, 812));
        return child!;
      },
      home: MediaBrowser(initialIndex: 0, sources: [
        MediaSource(
            thumbnail: '',
            file: File('openim_common/assets/images/ic_archive_99chat.png')),
        MediaSource(thumbnail: '', isVideo: true),
      ]),
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('图片和视频'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back to preview'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
