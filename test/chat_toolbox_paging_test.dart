import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('favorites entry invokes its callback without disabling album',
      (tester) async {
    var favorites = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: ChatToolBox(onTapFavorites: () => favorites++),
        ),
      ),
    ));
    final label = find.text(StrRes.favoriteCollection);
    expect(label.hitTestable(), findsOneWidget);
    expect(find.text(StrRes.toolboxAlbum).hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip(StrRes.favoriteCollection));
    expect(favorites, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'toolbox swipes both ways and keeps second-page actions clickable',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var emojis = 0;
    void action() {}
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          home: Scaffold(
              body: ChatToolBox(
        onTapFormattedText: action,
        onTapLocation: action,
        onTapEmoji: () => emojis++,
        onTapCamera: action,
        onTapRecord: action,
        onTapAudio: action,
        onTapFile: action,
        onTapAlbum: action,
        onTapCall: action,
        onTapCard: action,
      ))),
    ));
    expect(find.text(StrRes.toolboxCard).hitTestable(), findsOneWidget);
    expect(find.text(StrRes.emoji).hitTestable(), findsNothing);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    final label = find.text(StrRes.emoji).hitTestable();
    expect(label, findsOneWidget);
    final tile = find.ancestor(of: label, matching: find.byType(Column)).first;
    await tester.tapAt(tester.getTopLeft(tile) + const Offset(25, 25));
    expect(emojis, 1);
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text(StrRes.emoji).hitTestable(), findsNothing);
    expect(find.text(StrRes.toolboxCard).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
