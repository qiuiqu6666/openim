import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/mine/settings/pages/moments_friend_picker_page.dart';
import 'package:openim_common/openim_common.dart';

class _Directory extends GetxController implements ContactsLogic {
  @override
  final friends = <ISUserInfo>[
    ISUserInfo.fromJson({'userID': 'alice', 'nickname': 'Alice'})
      ..tagIndex = 'A'
      ..isShowSuspension = true,
    ISUserInfo.fromJson({'userID': 'bob', 'nickname': 'Bob'})
      ..tagIndex = 'B'
      ..isShowSuspension = true,
  ].obs;

  @override
  bool get isCurrentSession => true;
  @override
  final friendsLoadFailed = false.obs;
  @override
  Future<void> ensureFriendsLoaded() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

double _contrast(Color foreground, Color background) {
  final fg = foreground.computeLuminance();
  final bg = background.computeLuminance();
  return fg > bg ? (fg + .05) / (bg + .05) : (bg + .05) / (fg + .05);
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<ContactsLogic>(_Directory());
  });
  tearDown(() => Get.reset());

  testWidgets('friend selection controls and dragged index stay readable',
      (tester) async {
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder: (_, isDark, __) => MaterialApp(
          theme: ThemeData(
              brightness: isDark ? Brightness.dark : Brightness.light),
          home: const MomentsFriendPickerPage(
            title: 'Select friends',
            initialSelectedIds: ['alice'],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    for (final isDark in [false, true, false]) {
      dark.value = isDark;
      await tester.pumpAndSettle();
      final surface = AppTokens.surface(dark: isDark);
      final close = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.close_rounded));
      final done = tester.widget<Text>(find.text('Done'));
      final alice = tester.widget<Text>(find.text('Alice'));
      expect(_contrast(close.color!, surface), greaterThan(4.5));
      expect(_contrast(done.style!.color!, surface), greaterThan(4.5));
      expect(_contrast(alice.style!.color!, surface), greaterThan(4.5));
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget,
          reason: 'Theme changes must retain the selected friend.');

      final index = find.byType(IndexBar);
      final ordinaryA = find.descendant(of: index, matching: find.text('A'));
      final aText = tester.widget<Text>(ordinaryA);
      expect(_contrast(aText.style!.color!, surface), greaterThan(3));
      final gesture = await tester.startGesture(tester.getCenter(ordinaryA));
      await tester.pump();
      final hint = find.byWidgetPredicate((widget) =>
          widget is Text && widget.data == 'A' && widget.style?.fontSize == 20);
      expect(hint, findsOneWidget);
      final hintText = tester.widget<Text>(hint);
      final hintContainer = tester.widget<Container>(
          find.ancestor(of: hint, matching: find.byType(Container)).first);
      final hintColor = (hintContainer.decoration! as BoxDecoration).color!;
      expect(_contrast(hintText.style!.color!, hintColor), greaterThan(4.5));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
