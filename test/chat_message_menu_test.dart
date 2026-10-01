import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('custom sticker shows without a chat bubble', (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => const MaterialApp(
        home: Scaffold(
          body: ChatItemContainer(
            id: 'sticker',
            timeStr: '05:51',
            isBubbleBg: false,
            bareMedia: true,
            isISend: true,
            hasRead: true,
            isSending: false,
            isSendFailed: false,
            child: SizedBox(key: Key('sticker-image'), width: 100, height: 100),
          ),
        ),
      ),
    ));
    expect(find.byType(ChatBubble), findsNothing);
    expect(
        tester.getRect(find.text('05:51')).top,
        greaterThan(
            tester.getRect(find.byKey(const Key('sticker-image'))).bottom));
    expect(find.byType(ChatReadReceiptIcon), findsOneWidget);
  });

  testWidgets('photo and video metadata overlays the bottom right',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => const MaterialApp(
          home: Scaffold(
        body: ChatItemContainer(
          id: 'overlay',
          timeStr: '15:55',
          isBubbleBg: false,
          mediaOverlay: true,
          isISend: true,
          hasRead: true,
          isSending: false,
          isSendFailed: false,
          child: SizedBox(key: Key('preview'), width: 180, height: 240),
        ),
      )),
    ));
    final media = tester.getRect(find.byKey(const Key('preview')));
    final time = tester.getRect(find.text('15:55'));
    final receipt = tester.getRect(find.byType(ChatReadReceiptIcon));
    expect(media.contains(time.topLeft), isTrue);
    expect(media.contains(receipt.bottomRight), isTrue);
    expect(time.center.dy, greaterThan(media.center.dy));
    expect(receipt.left, greaterThan(time.right));
    expect(find.byType(ChatBubble), findsNothing);
    expect(tester.widget<Text>(find.text('15:55')).style?.color, Colors.white);
    expect(
        tester
            .widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon))
            .color,
        Colors.white);
  });
  testWidgets('message time and send status are inside the bubble',
      (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: ChatItemContainer(
              id: 'message-1',
              timeStr: '17:59',
              isBubbleBg: true,
              isISend: true,
              hasRead: true,
              isSending: false,
              isSendFailed: false,
              child: const ChatText(text: 'hi'),
            ),
          ),
        ),
      ),
    );

    final bubble = find.byType(ChatBubble);
    expect(tester.getSize(bubble).width,
        lessThan(tester.getSize(find.byType(Scaffold)).width * 0.5));
    expect(
        find.descendant(of: bubble, matching: find.text('hi')), findsOneWidget);
    expect(find.descendant(of: bubble, matching: find.text('17:59')),
        findsOneWidget);
    expect(
        find.descendant(of: bubble, matching: find.byType(ChatReadReceiptIcon)),
        findsOneWidget);
    expect(find.text(StrRes.hasRead), findsNothing);
    expect(
      tester.getRect(find.text('17:59')).top,
      lessThan(tester.getRect(find.text('hi')).bottom),
    );
  });

  testWidgets('long messages keep time and status without overflowing',
      (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(800, 600),
        builder: (_, __) => const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: ChatItemContainer(
                  id: 'message-2',
                  timeStr: '17:59',
                  isBubbleBg: true,
                  isISend: true,
                  hasRead: false,
                  isSending: false,
                  isSendFailed: false,
                  child: ChatText(
                    text:
                        'A long message that needs to wrap on a narrow screen without hiding the timestamp or status icon.',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('17:59'), findsOneWidget);
    expect(find.byType(ChatReadReceiptIcon), findsOneWidget);
    final textRect = tester.getRect(find.byType(ChatText));
    final timeRect = tester.getRect(find.text('17:59'));
    final statusRect = tester.getRect(find.byType(ChatReadReceiptIcon));
    expect(timeRect.bottom, greaterThanOrEqualTo(textRect.bottom - 4));
    expect(textRect.right, greaterThan(timeRect.left));
    expect(statusRect.right, lessThanOrEqualTo(textRect.right + 1));
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon))
            .isRead,
        isFalse);
  });

  testWidgets('media time is above content and status is below',
      (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => const MaterialApp(
          home: Scaffold(
            body: ChatItemContainer(
              id: 'image-1',
              timeStr: '16:03',
              isBubbleBg: false,
              isISend: true,
              hasRead: true,
              isSending: false,
              isSendFailed: false,
              child:
                  SizedBox(key: Key('media-content'), width: 120, height: 80),
            ),
          ),
        ),
      ),
    );

    expect(tester.getBottomLeft(find.text('16:03')).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('media-content'))).dy));
    expect(
        tester.getTopLeft(find.byType(ChatReadReceiptIcon)).dy,
        greaterThan(
            tester.getBottomLeft(find.byKey(const Key('media-content'))).dy));
    expect(tester.getSize(find.byType(ChatBubble)).width, lessThan(120 + 30.w));
  });

  testWidgets('long pressing a message opens its action menu', (tester) async {
    final controller = CustomPopupMenuController();
    var copied = false;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: ChatItemContainer(
              id: 'message-1',
              isBubbleBg: true,
              isISend: true,
              hasRead: false,
              isSending: false,
              isSendFailed: false,
              rightNickname: 'Me',
              menuController: controller,
              messageMenus: [
                PopMenuInfo(text: 'Copy', onTap: () => copied = true),
              ],
              child: const ChatText(text: 'hello'),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, isTrue);
    expect(controller.menuIsShowing, isFalse);
    controller.dispose();
  });
}
