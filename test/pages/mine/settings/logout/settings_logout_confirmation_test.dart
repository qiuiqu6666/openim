import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/mine/mine_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IM extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(userID: 'self', nickname: 'User').obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends GetxController implements HomeLogic {
  int exits = 0;
  @override
  Future<void> endSession(
      {bool invalid = false, bool resetScreenLock = false}) async {
    exits++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    Get.testMode = true;
  });
  tearDown(() => Get.reset());

  for (final brightness in Brightness.values) {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets(
          'settings confirms logout once with Cupertino ($brightness, $platform)',
          (tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        Get.put<IMController>(_IM());
        Get.put<HomeLogic>(_Home());
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final mine = MineLogic();
        addTearDown(() => mine.onDelete());
        final home = Get.find<HomeLogic>() as _Home;
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
            locale: const Locale('zh', 'CN'),
            translations: TranslationService(),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(brightness: brightness, platform: platform),
            home: Builder(
                builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => mine.openSettings(context),
                          child: const Text('Open settings')),
                    )),
          ),
        ));
        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('退出登录'));
        await tester.tap(find.text('退出登录'));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoAlertDialog), findsOneWidget);
        expect(find.byType(CustomDialog), findsNothing);
        expect(home.exits, 0);

        await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消'));
        await tester.pumpAndSettle();
        expect(home.exits, 0);
        expect(find.byType(CupertinoAlertDialog), findsNothing);

        await tester.tap(find.text('退出登录'));
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(CupertinoDialogAction, '退出登录');
        expect(
            tester.widget<CupertinoDialogAction>(confirm).isDestructiveAction,
            isTrue);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(home.exits, 1);
        expect(find.byType(CupertinoAlertDialog), findsNothing);
        expect(find.byType(CustomDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
