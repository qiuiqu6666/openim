import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/mine/mine_logic.dart';
import 'package:openim/pages/mine/my_info/my_avatar_editor.dart';
import 'package:openim/pages/mine/mine_view.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/set_remark_view.dart';
import 'package:openim/pages/mine/my_info/my_info_logic.dart';
import 'package:openim/pages/mine/my_info/my_info_view.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';

class NicknameIMFixture extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(userID: 'self', nickname: 'Original name').obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NicknameMineFixture extends GetxController implements MineLogic {
  NicknameMineFixture(this.imLogic);
  @override
  final IMController imLogic;
  @override
  void editMyName() => AppNavigator.startEditMyInfo();
  @override
  void openPhotoSheet() => MyAvatarEditor.open(Get.find<IMController>());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NicknameMyInfoFixture extends GetxController implements MyInfoLogic {
  @override
  void editMyName() => AppNavigator.startEditMyInfo();
  @override
  void openPhotoSheet() => MyAvatarEditor.open(Get.find<IMController>());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final fromMyInfo in [false, true]) {
    testWidgets(
        '${fromMyInfo ? "My info" : "Mine"} nickname opens the registered editor',
        (tester) async {
      addTearDown(Get.reset);
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final im = NicknameIMFixture();
      Get.put<IMController>(im);
      Get.put<MineLogic>(NicknameMineFixture(im));
      Get.put<MyInfoLogic>(NicknameMyInfoFixture());
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: fromMyInfo ? MyInfoPage() : MinePage(),
          getPages: AppPages.routes,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AvatarView).first);
      await tester.pumpAndSettle();
      expect(find.text(StrRes.toolboxAlbum), findsOneWidget);
      expect(find.text(StrRes.toolboxCamera), findsOneWidget);
      Get.back();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original name'));
      await tester.pumpAndSettle();
      expect(find.byType(SetFriendRemarkPage), findsOneWidget);
      expect(find.text('13/16'), findsOneWidget);
      await tester.tap(find.byType(AvatarView));
      await tester.pumpAndSettle();
      expect(find.text(StrRes.toolboxAlbum), findsOneWidget);
      expect(find.text(StrRes.toolboxCamera), findsOneWidget);
      Get.back();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.controller!.text, 'Original name');
      await tester.enterText(find.byType(TextField), 'Changed name');
      expect(input.controller!.text, 'Changed name');
      expect(im.userInfo.value.nickname, 'Original name');
      Get.back();
      await tester.pumpAndSettle();
      expect(find.byType(fromMyInfo ? MyInfoPage : MinePage), findsOneWidget);
      expect(im.userInfo.value.nickname, 'Original name');
      expect(tester.takeException(), isNull);
    });
  }
}
