import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
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
