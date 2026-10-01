import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/set_remark_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/set_remark_view.dart';
import 'package:openim_common/openim_common.dart';

class _FakeRemarkLogic implements SetFriendRemarkLogic {
  @override
  final inputCtrl = TextEditingController(text: '原备注');

  @override
  String? get avatarURL => null;

  @override
  String? get avatarName => '用户';

  int saves = 0;

  @override
  void save() => saves++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('shared name editor lets the group avatar be tapped',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController(text: '测试群聊');
    addTearDown(controller.dispose);
    var avatarTaps = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        home: SetFriendRemarkPage.editor(
          controller: controller,
          onSave: () {},
          maxLength: 30,
          isGroupAvatar: true,
          onAvatarTap: () => avatarTaps++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AvatarView));
    expect(avatarTaps, 1);
  });

  testWidgets('remark page shows count and enforces the 30 character limit',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final logic = _FakeRemarkLogic();
    addTearDown(logic.inputCtrl.dispose);
    Styles.isDark = false;
    addTearDown(() => Styles.isDark = false);

    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: SetFriendRemarkPage(logic: logic),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('确定'), findsOneWidget);
    expect(find.text('3/30'), findsOneWidget);
    await tester.enterText(find.byType(TextField), List.filled(31, '字').join());
    await tester.pumpAndSettle();
    expect(logic.inputCtrl.text, List.filled(30, '字').join());
    expect(find.text('30/30'), findsOneWidget);
    await tester.tap(find.text('确定'));
    expect(logic.saves, 1);
    expect(tester.takeException(), isNull);
  });
}
