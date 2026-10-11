import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/fund/withdrawal_security/presentation/fund_security_feedback.dart';
import 'package:openim/pages/mine/settings/pages/change_phone_page.dart';
import 'package:openim/services/fund_api.dart';
import 'package:openim/theme/app_theme_data.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _export = bool.fromEnvironment('EXPORT_ALERT_PREVIEWS');

class _IM extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(userID: 'self').obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends GetxController implements HomeLogic {
  int logouts = 0;
  @override
  Future<void> endSession(
      {bool invalid = false, bool resetScreenLock = false}) async {
    logouts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileTransport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<void>? cancelFuture) async =>
      ResponseBody.fromString(
          jsonEncode({
            'errCode': 0,
            'data': {
              'users': [
                {'userID': 'self', 'phoneNumber': ''}
              ]
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio oldDio;
  setUpAll(() async {
    if (!_export) return;
    await (FontLoader('CupertinoSystemText')
          ..addFont(Future.value(ByteData.sublistView(
              await File('C:/Windows/Fonts/msyh.ttc').readAsBytes()))))
        .load();
  });
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'self';
    Get.put<IMController>(_IM());
    oldDio = http.dio;
    http.dio = Dio()..httpClientAdapter = _ProfileTransport();
  });
  tearDown(() {
    Get.reset();
    http.dio.close();
    http.dio = oldDio;
    OpenIM.iMManager.userID = '';
  });

  Future<BuildContext> mount(
      WidgetTester tester, Brightness brightness, GlobalKey boundary) async {
    tester.view.physicalSize = const Size(375, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext page;
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppThemeData(brightness),
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(builder: (context) {
              page = context;
              return const Scaffold();
            }),
          ),
        )));
    await tester.pumpAndSettle();
    return page;
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'phone recovery uses Cupertino and opens the real binding page ($brightness)',
        (tester) async {
      final boundary = GlobalKey();
      final context = await mount(tester, brightness, boundary);
      final work = showFundSecurityFailure(
          context, const FundApiException(20038, 'server detail'),
          isCurrent: () => true);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('交易安全验证'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
      expect(find.text('绑定手机号'), findsOneWidget);
      if (_export) {
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/ios-alert-previews')
            ..createSync(recursive: true);
          await File('${directory.path}/${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('绑定手机号'));
      await tester.pumpAndSettle();
      expect(find.byType(ChangePhonePage), findsOneWidget);
      Get.back();
      await tester.pumpAndSettle();
      await work;
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'acknowledgement and stale recovery never log out; sign-in does once',
      (tester) async {
    final home = _Home();
    Get.put<HomeLogic>(home);
    final context = await mount(tester, Brightness.light, GlobalKey());
    var current = true;
    Future<void> open() => showFundSecurityFailure(
        context, const FundApiException(20079, 'unknown device'),
        isCurrent: () => current);
    var work = open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await work;
    expect(home.logouts, 0);
    work = open();
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();
    await work;
    expect(home.logouts, 0);
    current = true;
    work = open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();
    await work;
    expect(home.logouts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
