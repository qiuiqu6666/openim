import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('card and confirmation support theme dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? result;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
              body: Builder(
                  builder: (context) => Column(children: [
                        const ContactCardView(
                            userID: '12345',
                            name: 'Alice',
                            isSelf: true,
                            time: '18:29'),
                        TextButton(
                            onPressed: () async {
                              result = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => const ContactCardSendDialog(
                                      name: 'Alice',
                                      recipientName:
                                          'A very long conversation name',
                                      recipientIsGroup: true));
                            },
                            child: const Text('open')),
                      ]))),
        ),
      ));
      expect(find.text('18:29'), findsOneWidget);
      expect(find.text('12345'), findsOneWidget);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
      await tester.tap(find.text(StrRes.cancel));
      await tester.pumpAndSettle();
      expect(result, false);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StrRes.determine));
      await tester.pumpAndSettle();
      expect(result, true);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('chat toolbox exposes the contact card picker', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = false;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        home: Scaffold(
          body: ChatToolBox(onTapCard: () => selected = true),
        ),
      ),
    ));
    final label = find.text(StrRes.toolboxCard);
    expect(label, findsOneWidget);
    final tile = find.ancestor(of: label, matching: find.byType(Column)).first;
    await tester.tapAt(tester.getTopLeft(tile) + const Offset(25, 25));
    expect(selected, isTrue);
  });

  test('card summary and profile navigation use the shared contact', () {
    final message = Message(
      contentType: MessageType.card,
      sendID: 'sender',
      cardElem: CardElem(userID: 'contact', nickname: 'Alice'),
    );
    expect(IMUtils.parseMsg(message), '[${StrRes.carte}]Alice');
    UserInfo? target;
    IMUtils.parseClickEvent(message, onViewUserInfo: (user) => target = user);
    expect(target?.userID, 'contact');
    expect(target?.nickname, 'Alice');
    target = null;
    IMUtils.parseClickEvent(Message(contentType: MessageType.card),
        onViewUserInfo: (user) => target = user);
    expect(target, isNull);
  });
}
