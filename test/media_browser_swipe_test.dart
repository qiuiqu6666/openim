import 'dart:io';

import 'package:extended_image/extended_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

Future<void> _settleMedia(WidgetTester tester) async {
  // Local availability now uses real asynchronous filesystem work.
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pumpAndSettle();
}

void main() {
  for (final exit in ['button', 'system', 'slide']) {
    testWidgets('preview restores system bars on $exit exit', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      const original = SystemUiOverlayStyle(
        statusBarColor: Colors.blue,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      );
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        builder: (context, child) {
          ScreenUtil.init(context, designSize: const Size(375, 812));
          return child!;
        },
        home: const Scaffold(body: Text('Original page')),
      ));
      SystemChrome.setSystemUIOverlayStyle(original);
      await tester.pump();
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => MediaBrowser(
                sources: [
                  MediaSource(
                      thumbnail: '',
                      file: File(
                          'openim_common/assets/images/ic_archive_99chat.png'),
                      tag: 'restore')
                ],
                initialIndex: 0,
              )));
      await _settleMedia(tester);
      calls.clear();
      if (exit == 'button') {
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      } else if (exit == 'system') {
        await tester.binding.handlePopRoute();
      } else {
        // Complete the slide gesture. popPage only changes the package's
        // animation state; endSlide dismisses the route and runs its cleanup.
        final slide = tester.state<ExtendedImageSlidePageState>(
            find.byType(ExtendedImageSlidePage));
        slide.slide(Offset(0, slide.pageSize.height / 2));
        slide.endSlide(ScaleEndDetails());
      }
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.text('Original page'), findsOneWidget);
      expect(SystemChrome.latestStyle, original);
      expect(
          calls.where(
              (call) => call.method == 'SystemChrome.restoreSystemUIOverlays'),
          hasLength(1));
    });
  }
  testWidgets('horizontal swipe changes the full-screen picture',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.reset);
    final image = File('openim_common/assets/images/ic_archive_99chat.png');
    expect(image.existsSync(), isTrue);
    final pages = <int>[];
    final saved = <int>[];

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) {
        ScreenUtil.init(context, designSize: const Size(375, 812));
        return child!;
      },
      home: Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(tester.element(find.text('Open')))
                .push(MaterialPageRoute<void>(
              builder: (_) => MediaBrowser(
                sources: [
                  MediaSource(
                    thumbnail: '',
                    file: image,
                    tag: 'first',
                    senderName: '发送者',
                    sentAt: DateTime(2026, 10, 1, 12, 29),
                  ),
                  MediaSource(
                    thumbnail: '',
                    file: image,
                    tag: 'second',
                    senderName: '发送者',
                    sentAt: DateTime(2026, 10, 1, 12, 30),
                  ),
                ],
                initialIndex: 0,
                onPageChanged: pages.add,
                onSave: saved.add,
                onForward: (_) {},
                onDelete: (_) {},
              ),
            )),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await _settleMedia(tester);
    expect(find.textContaining('1/2'), findsOneWidget);
    final back = tester.getRect(find.byIcon(Icons.arrow_back_ios_new));
    expect(back.top, greaterThanOrEqualTo(44));
    expect(back.center.dy, closeTo(44 + TitleBar.chatToolbarHeight / 2, 0.1));
    expect(
        tester
            .getRect(find.byKey(const ValueKey('media-preview-info')))
            .center
            .dy,
        closeTo(back.center.dy, 0.1));
    final actions = [
      Icons.ios_share,
      Icons.download,
      Icons.grid_view_rounded,
      Icons.more_horiz
    ].map((icon) => tester.getRect(find.byIcon(icon))).toList();
    for (var i = 0; i < actions.length; i++) {
      expect(actions[i].bottom, lessThanOrEqualTo(812 - 34));
      expect(actions[i].top, greaterThanOrEqualTo(812 - 34 - 72));
      if (i > 0) expect(actions[i].left, greaterThan(actions[i - 1].right));
    }
    await tester.drag(find.byType(MediaBrowser), const Offset(-550, 0));
    await _settleMedia(tester);

    expect(pages, contains(1));
    expect(find.textContaining('2/2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.download));
    expect(saved, [1]);
  });
}
