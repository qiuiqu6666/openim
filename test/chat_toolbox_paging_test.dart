import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('toolbox swipes both ways and keeps second-page actions clickable',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var cards = 0;
    void action() {}
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(home: Scaffold(body: ChatToolBox(
        onTapFormattedText: action, onTapLocation: action, onTapEmoji: action,
        onTapCamera: action, onTapRecord: action, onTapAudio: action,
        onTapFile: action, onTapAlbum: action, onTapCall: action,
        onTapCard: () => cards++,
      ))),
    ));
    expect(find.text(StrRes.toolboxCard).hitTestable(), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    final label = find.text(StrRes.toolboxCard).hitTestable();
    expect(label, findsOneWidget);
    final tile = find.ancestor(of: label, matching: find.byType(Column)).first;
    await tester.tapAt(tester.getTopLeft(tile) + const Offset(25, 25));
    expect(cards, 1);
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text(StrRes.toolboxCard).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
