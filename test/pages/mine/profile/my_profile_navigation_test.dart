import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/mine/settings/openim_profile_service.dart';
import 'package:openim/pages/mine/settings/pages/edit_nickname_page.dart';
import 'package:openim/pages/mine/settings/pages/profile_info_page.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IM extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(
    userID: 'self',
    account: 'myaccount99',
    nickname: '我的名字',
    gender: 1,
    phoneNumber: '123456789',
  ).obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late _IM controller;
  late List<String> calls;

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'imToken': 'token',
      'chatToken': 'chat-token',
    }));
    OpenIM.iMManager.userID = 'self';
    controller = _IM();
    Get.put<IMController>(controller, permanent: true);
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      throw StateError('Profile entry must work without network');
    });
  });

  tearDown(() async {
    Get.reset();
    OpenIM.iMManager.userID = '';
    await DataSp.removeLoginCertificate();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(WidgetTester tester, {bool dark = false}) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Styles.isDark = dark;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: Text('Chat')),
        getPages: [
          AppPages.routes
              .singleWhere((route) => route.name == AppRoutes.myProfile),
        ],
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
        'self opens editable account profile in ${dark ? 'dark' : 'light'}',
        (tester) async {
      await mount(tester, dark: dark);
      final navigation = AppNavigator.startUserProfilePane(
        userID: 'self',
        nickname: '群内昵称',
        groupID: 'private-group',
      );
      await tester.pumpAndSettle();
      expect(find.text('个人资料'), findsOneWidget);
      expect(find.text('我的名字'), findsOneWidget);
      expect(find.text('myaccount99'), findsOneWidget);
      expect(find.text('群内昵称'), findsNothing);
      final profile =
          tester.widget<ProfileInfoPage>(find.byType(ProfileInfoPage));
      expect(profile.userId, 'self');
      expect(profile.service, isA<OpenIMProfileService>());
      expect(profile.onMomentsTap, isNotNull);
      expect(calls, isEmpty);

      await tester.tap(find.text('名字'));
      await tester.pumpAndSettle();
      expect(find.byType(EditNicknamePage), findsOneWidget);
      expect(
          tester
              .widget<EditNicknamePage>(find.byType(EditNicknamePage))
              .initialNickname,
          '我的名字');
      Get.back();
      await tester.pumpAndSettle();
      Get.back();
      await tester.pumpAndSettle();
      await navigation;
      expect(find.text('Chat'), findsOneWidget);
      expect(profile.store.isCurrentAccount, isFalse);
      controller.userInfo.update((user) => user?.nickname = '更新名字');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'live profile updates stay in sync and changed accounts are hidden',
      (tester) async {
    await mount(tester);
    AppNavigator.startUserProfilePane(userID: 'self');
    await tester.pumpAndSettle();
    controller.userInfo.update((user) => user?.nickname = '更新名字');
    await tester.pumpAndSettle();
    expect(find.text('更新名字'), findsOneWidget);
    expect(find.text('我的名字'), findsNothing);
    OpenIM.iMManager.userID = 'another-user';
    controller.userInfo.value =
        UserFullInfo(userID: 'another-user', nickname: '另一账号');
    await tester.pumpAndSettle();
    expect(find.byType(ProfileInfoPage), findsNothing);
    expect(find.text('另一账号'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
