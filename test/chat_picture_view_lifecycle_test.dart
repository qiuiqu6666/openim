import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/chat_picture_view.dart';

class _PendingFile implements File {
  _PendingFile(this.path, this.result, this.onCheck);

  @override
  final String path;
  final Future<bool> result;
  final VoidCallback onCheck;

  @override
  Future<bool> exists() {
    onCheck();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailedImageState implements ExtendedImageState {
  @override
  LoadState get extendedImageLoadState => LoadState.failed;

  @override
  ImageProvider get imageProvider => const AssetImage('unused');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final screenWidth in [320.0, 375.0]) {
    testWidgets('square pictures enlarge within available width $screenWidth',
        (tester) async {
      tester.view.physicalSize = Size(screenWidth, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final limit in [200.0, 80.0]) {
        final message = Message()
          ..pictureElem =
              PictureElem(sourcePicture: PictureInfo(width: 800, height: 800));
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) {
              ScreenUtil.init(context, designSize: const Size(375, 812));
              return child!;
            },
            home: Scaffold(
                body: SizedBox(
                    width: limit,
                    child:
                        ChatPictureView(message: message, isISend: false)))));
        final expected = (120 * screenWidth / 375).clamp(0.0, limit);
        expect(
            find.descendant(
                of: find.byType(ChatPictureView),
                matching: find.byWidgetPredicate((widget) =>
                    widget is SizedBox &&
                    widget.width == expected &&
                    widget.height == expected)),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('failed thumbnail falls back to distinct unmodified sources',
      (tester) async {
    const original = 'https://example.test/original?signature=a%2Bb';
    final message = Message()
      ..pictureElem = PictureElem(
        snapshotPicture: PictureInfo(url: 'https://example.test/thumb'),
        bigPicture: PictureInfo(url: original),
        sourcePicture: PictureInfo(url: original, width: 800, height: 400),
      );
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) {
        ScreenUtil.init(context, designSize: const Size(375, 812));
        return child!;
      },
      home: Scaffold(body: ChatPictureView(message: message, isISend: false)),
    ));
    // Error children are constructed but not mounted/downloaded until needed.
    expect(find.byType(ExtendedImage), findsOneWidget);
    Widget? current = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
    final urls = <String>[];
    while (current is ExtendedImage) {
      final resized = current.image as ExtendedResizeImage;
      urls.add((resized.imageProvider as ExtendedNetworkImageProvider).url);
      current = current.loadStateChanged!(_FailedImageState());
    }
    expect(urls, [
      'https://example.test/thumb?height=960&width=960&type=image',
      'https://example.test/thumb',
      original,
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('landscape fills bubble width while respecting parent bounds',
      (tester) async {
    final message = Message()
      ..pictureElem =
          PictureElem(sourcePicture: PictureInfo(width: 1000, height: 500));
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) {
          ScreenUtil.init(context, designSize: const Size(375, 812));
          return child!;
        },
        home: Scaffold(
            body: SizedBox(
                width: 200,
                child: ChatPictureView(message: message, isISend: false)))));
    final bubble = find.descendant(
        of: find.byType(ChatPictureView),
        matching: find.byWidgetPredicate((widget) =>
            widget is SizedBox && widget.width == 200 && widget.height == 100));
    expect(bubble, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'local checks survive rebuilds and ignore completion after leaving',
      (tester) async {
    final pending = Completer<bool>();
    var checks = 0;
    final message = Message()
      ..clientMsgID = 'pending-picture'
      ..contentType = MessageType.picture
      ..pictureElem = PictureElem(
        sourcePath: 'pending-original.jpg',
        sourcePicture: PictureInfo(width: 800, height: 400),
        snapshotPicture: PictureInfo(url: 'https://example.test/thumbnail.jpg'),
      );

    Widget page() => MaterialApp(
          builder: (context, child) {
            ScreenUtil.init(context, designSize: const Size(375, 812));
            return child!;
          },
          home: Scaffold(
            body: ChatPictureView(message: message, isISend: true),
          ),
        );

    await IOOverrides.runZoned(() async {
      await tester.pumpWidget(page());
      expect(checks, 1);
      // A local original should not start a remote download while its check runs.
      expect(find.byType(ExtendedImage), findsNothing);
      await tester.pumpWidget(page());
      expect(checks, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
        createFile: (path) =>
            _PendingFile(path, pending.future, () => checks++));
  });
}
