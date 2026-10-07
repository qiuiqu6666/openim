import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/set_remark_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/set_remark_view.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile%20_panel_logic.dart';
import 'package:openim_common/openim_common.dart';

const _sdk = MethodChannel('flutter_openim_sdk');

class _Profile extends GetxController implements UserProfilePanelLogic {
  _Profile(String? remark) {
    userInfo =
        (UserFullInfo(userID: 'friend', nickname: '秋啊')..remark = remark).obs;
  }

  @override
  late Rx<UserFullInfo> userInfo;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<SetFriendRemarkLogic> _open(
  WidgetTester tester, {
  String? remark,
  bool dark = false,
}) async {
  Styles.isDark = dark;
  GetTags.createUserProfileTag();
  addTearDown(GetTags.destroyUserProfileTag);
  Get.put<UserProfilePanelLogic>(_Profile(remark), tag: GetTags.userProfile);
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: EasyLoading.init(),
      home: const Scaffold(body: Text('origin')),
      getPages: [
        GetPage(
          name: '/remark',
          binding: BindingsBuilder(() {
            Get.put(SetFriendRemarkLogic());
          }),
          page: () => SetFriendRemarkPage(),
        ),
      ],
    ),
  ));
  unawaited(Get.toNamed<void>('/remark'));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await LoadingView.singleton.dismiss();
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    Styles.isDark = false;
  });
  return Get.find<SetFriendRemarkLogic>();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() {
    Get.reset();
    Get.testMode = true;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, (call) async {
      if (call.method != 'updateFriends') {
        throw StateError('Unexpected SDK call: ${call.method}');
      }
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, null);
  });

  for (final dark in [false, true]) {
    for (final original in [null, '旧备注']) {
      testWidgets(
          'remark fills existing text and uses nickname as empty hint ($original, dark=$dark)',
          (tester) async {
        final logic = await _open(tester, remark: original, dark: dark);
        final expected = original ?? '';
        expect(logic.inputCtrl.text, expected);
        final input = tester.widget<TextField>(find.byType(TextField));
        expect(input.controller!.text, expected);
        expect(input.decoration!.hintText, '秋啊');
        expect(find.text('${expected.characters.length}/30'), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(input.controller!.selection.isValid, isTrue);
        await tester.enterText(find.byType(TextField), '新备注');
        await tester.tap(find.text(StrRes.determine));
        await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pumpAndSettle();
        expect(calls, hasLength(1));
        expect((calls.single.arguments as Map)['req'], {
          'friendUserIDs': ['friend'],
          'remark': '新备注',
        });
        expect(find.text('origin'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      });
    }
  }

  for (final original in [null, '', '旧备注']) {
    testWidgets(
        'unchanged remark display never writes a new remark ($original)',
        (tester) async {
      final logic = await _open(tester, remark: original);
      logic.save();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('origin'), findsOneWidget);
    });
  }

  testWidgets('clearing an existing remark still removes it through the SDK',
      (tester) async {
    await _open(tester, remark: '旧备注');
    await tester.enterText(find.byType(TextField), '临时备注');
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text(StrRes.determine));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(((calls.single.arguments as Map)['req'] as Map)['remark'], '');
    expect(find.text('origin'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('existing remark supports editing at the end and in the middle',
      (tester) async {
    final logic = await _open(tester, remark: '旧备注');
    await tester.tap(find.byType(TextField));
    await tester.pump();
    logic.inputCtrl.selection = const TextSelection.collapsed(offset: 3);
    tester.testTextInput.enterText('旧备注追加');
    await tester.pump();
    expect(logic.inputCtrl.text, '旧备注追加');
    logic.inputCtrl.selection = const TextSelection.collapsed(offset: 1);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '旧新备注追加', selection: TextSelection.collapsed(offset: 2)));
    await tester.pump();
    expect(logic.inputCtrl.text, '旧新备注追加');
    expect(logic.inputCtrl.selection.baseOffset, 2);
  });
}
