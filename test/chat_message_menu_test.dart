import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
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
