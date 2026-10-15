import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'package:openim/routes/swipe_back/app_page_transitions_theme.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          '$platform $brightness: chat entry, interrupted pop and gesture keep geometry',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final nav = GlobalKey<NavigatorState>();
        final capture = GlobalKey();
        final scroll = ScrollController(initialScrollOffset: 96);
        addTearDown(scroll.dispose);
        const under = ValueKey('under');
        const top = ValueKey('chat');
        const list = ValueKey('messages');
        await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: MaterialApp(
                navigatorKey: nav,
                theme: ThemeData(
                    platform: platform,
                    brightness: brightness,
                    pageTransitionsTheme: appPageTransitionsTheme),
                home: const Scaffold())));
        final underPage = Scaffold(
            key: under,
            appBar: AppBar(title: const Text('Chats')),
            body: ListView(
                children: List.generate(
                    14,
                    (i) => ListTile(
                        title: Text('Conversation ${i + 1}'),
                        subtitle: const Text('Latest message')))));
        unawaited(nav.currentState!
            .push(AppMaterialPageRoute<void>(builder: (_) => underPage)));
        await tester.pumpAndSettle();
        final config =
            AppPages.routes.firstWhere((p) => p.name == AppRoutes.chat);
        GetPageRoute<void> route() => GetPageRoute<void>(
            customTransition: config.customTransition,
            transitionDuration: config.transitionDuration!,
            popGesture: false,
            page: () => Scaffold(
                key: top,
                appBar: AppBar(title: const Text('Chat')),
                body: ListView.builder(
                    key: list,
                    controller: scroll,
                    itemExtent: 64,
                    itemCount: 40,
                    itemBuilder: (_, i) => ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text('Message ${i + 1}'),
                        subtitle: const Text('Stable message window')))));
        unawaited(nav.currentState!.push(route()));
        await tester.pump();
        Element? mountedList;
        var previousX = 375.0;
        for (var frame = 1; frame <= 18; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          mountedList ??= tester.element(find.byKey(list));
          final x = tester.getTopLeft(find.byKey(top)).dx;
          expect(x, inInclusiveRange(0, previousX + .001),
              reason: 'No reversal or overshoot');
          expect(tester.getSize(find.byKey(top)), const Size(375, 812));
          expect(tester.getTopLeft(find.byKey(top)).dy, 0);
          expect(tester.getTopLeft(find.byKey(under, skipOffstage: false)).dx + 375,
              greaterThanOrEqualTo(x - .01),
              reason: 'No uncovered gap between pages');
          expect(scroll.offset, 96);
          expect(tester.element(find.byKey(list)), same(mountedList));
          previousX = x;
          const directory = String.fromEnvironment('CHAT_MOTION_CAPTURE_DIR');
          if (directory.isNotEmpty &&
              platform == TargetPlatform.android &&
              [4, 8, 14, 18].contains(frame)) {
            final boundary = capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final pixels = await boundary.toImage();
              final bytes =
                  await pixels.toByteData(format: ui.ImageByteFormat.png);
              await Directory(directory).create(recursive: true);
              await File('$directory/${brightness.name}-${frame * 16}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              pixels.dispose();
            });
          }
        }
        expect(previousX, closeTo(0, .01));
        await tester.pumpAndSettle();
        final cancel = await tester.startGesture(const Offset(10, 300));
        await cancel.moveBy(const Offset(100, 0),
            timeStamp: const Duration(milliseconds: 800));
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(top)).dx, closeTo(100, .01));
        await cancel.cancel();
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(top)).dx, closeTo(100, .01));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(top)).dx, closeTo(0, .01));
        expect(scroll.offset, 96);
        final finish = await tester.startGesture(const Offset(10, 300));
        await finish.moveBy(const Offset(100, 0),
            timeStamp: const Duration(milliseconds: 800));
        await tester.pump();
        await finish.up();
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(top)).dx, closeTo(100, .01));
        await tester.pumpAndSettle();
        expect(find.byKey(top), findsNothing);
        expect(nav.currentState!.userGestureInProgress, isFalse);
        unawaited(nav.currentState!.push(route()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final interruptedX = tester.getTopLeft(find.byKey(top)).dx;
        nav.currentState!.pop();
        await tester.pump();
        expect(
            tester.getTopLeft(find.byKey(top)).dx, closeTo(interruptedX, .01));
        await tester.pumpAndSettle();
        expect(find.byKey(top), findsNothing);
        expect(tester.getTopLeft(find.byKey(under)).dx, closeTo(0, .01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
