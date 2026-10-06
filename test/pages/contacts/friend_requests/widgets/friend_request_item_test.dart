import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/friend_requests/widgets/friend_request_item.dart';
import 'package:openim_common/openim_common.dart';

Future<void> mountItem(WidgetTester tester,
    {bool dark = false,
    bool outgoing = true,
    String? extension = '{"addSource":"account"}',
    String? reason = '我是：秋12123',
    int result = 0,
    bool english = false,
    double scale = 1,
    Size size = const Size(375, 812),
    VoidCallback? onView}) async {
  Styles.isDark = dark;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: english ? const Locale('en', 'US') : const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
        body: ListView(children: [
          FriendRequestItem(
            application: FriendApplicationInfo(
              fromUserID: 'im_sender',
              toUserID: 'im_recipient',
              fromNickname: '发送者',
              toNickname: 'dual',
              reqMsg: reason,
              handleResult: result,
              ex: extension,
            ),
            outgoing: outgoing,
            onView: onView ?? () {},
          ),
        ]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });
  for (final dark in [false, true]) {
    testWidgets('source coexists with greeting and outgoing state ($dark)',
        (tester) async {
      await mountItem(tester, dark: dark);
      expect(find.text('dual'), findsOneWidget);
      expect(find.text('我是：秋12123'), findsOneWidget);
      expect(find.text('通过99号添加'), findsOneWidget);
      expect(find.text(StrRes.waitingForVerification), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('incoming request keeps its action and source ($dark)',
        (tester) async {
      var viewed = 0;
      await mountItem(tester,
          dark: dark,
          outgoing: false,
          extension: '{"addSource":"group"}',
          onView: () => viewed++);
      expect(find.text('发送者'), findsOneWidget);
      expect(find.text('通过群聊添加'), findsOneWidget);
      await tester.tap(find.text(StrRes.lookOver));
      expect(viewed, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('old signed records show unknown without exposing signature',
      (tester) async {
    await mountItem(tester,
        extension: '{"v":1,"op":"private-operation","mac":"private-mac"}',
        reason: null,
        result: 1);
    expect(find.text('来源未知'), findsOneWidget);
    expect(find.text(StrRes.approved), findsOneWidget);
    expect(find.textContaining('private-'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(320, 650), const Size(812, 375)]) {
    testWidgets('English source fits large text on $size', (tester) async {
      await mountItem(tester,
          english: true,
          scale: 2,
          size: size,
          extension: '{"addSource":"manage"}',
          result: -1);
      expect(find.text('Added via group management'), findsOneWidget);
      expect(find.text(StrRes.rejected), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
