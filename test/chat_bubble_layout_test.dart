import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('chat bubbles fit content and stay on their sender side',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previewKey = GlobalKey();
    Widget message(String id, bool outgoing, Widget content,
            {bool media = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: ChatItemContainer(
            key: ValueKey(id),
            id: id,
            timeStr: '17:59',
            isBubbleBg: !media,
            isISend: outgoing,
            hasRead: true,
            isSending: false,
            isSendFailed: false,
            leftNickname: 'User',
            rightNickname: 'Me',
            child: content,
          ),
        );
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          home: RepaintBoundary(
        key: previewKey,
        child: Scaffold(
            body: SafeArea(
                child: ListView(children: [
          message('short', true, const ChatText(text: 'hi')),
          message('received', false, const ChatText(text: '123123123')),
          message(
              'long',
              false,
              const ChatText(
                  text:
                      'A longer message wraps within the available space and keeps the text aligned to the left.')),
          message(
              'media',
              true,
              Container(
                  width: 120,
                  height: 160,
                  color: Colors.blueGrey.shade100,
                  child: const Icon(Icons.image_outlined, size: 48)),
              media: true),
        ]))),
      )),
    ));
    await tester.pumpAndSettle();
    Finder bubble(String id) => find.descendant(
        of: find.byKey(ValueKey(id)), matching: find.byType(ChatBubble));
    expect(tester.getSize(bubble('short')).width, lessThan(160));
    expect(tester.getSize(bubble('received')).width, lessThan(270));
    expect(tester.getSize(bubble('media')).width, closeTo(144, 1));
    expect(tester.getTopLeft(bubble('received')).dx, closeTo(66, 1));
    expect(tester.getBottomRight(bubble('short')).dx, closeTo(363, 1));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('short')),
            matching: find.byType(AvatarView)),
        findsNothing);
    expect(tester.takeException(), isNull);
    const output = String.fromEnvironment('CHAT_LAYOUT_PREVIEW');
    if (output.isNotEmpty) {
      final boundary = previewKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final rendered = await boundary.toImage(pixelRatio: 2);
        final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(data!.buffer.asUint8List());
        rendered.dispose();
      });
    }
  });
}
