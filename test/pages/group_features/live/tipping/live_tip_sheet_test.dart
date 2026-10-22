import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/live/pages/live_tip_sheet.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/widgets/live_style.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/services/fund_pending_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../wallet/data/wallet_fund_test_transport.dart';
import '../live_test_support.dart';

const _preview = String.fromEnvironment('LIVE_TIP_PREVIEW_DIR');
const _sdk = MethodChannel('flutter_openim_sdk');

class _Security extends StubSettingsService {
  @override
  Future<bool> hasTradePassword() async => true;
}

Map<String, dynamic> _balances(
        {String usdt = '12.345678', String yuan = '987.65'}) =>
    {
      'balances': [
        {'currency': 'USDT', 'available': usdt, 'frozen': '500'},
        {'currency': 'TRX', 'available': '876.54', 'frozen': '0'},
        {'currency': 'BI99', 'available': yuan, 'frozen': '0'},
      ]
    };

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<GlobalKey> _mount(WidgetTester tester, WalletFundApi wallet,
    {bool dark = false,
    double scale = 1,
    LiveTransport? payment,
    FundPendingStore? pending}) async {
  final key = GlobalKey();
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  configureEasyLoadingInteractions();
  final fixture = liveContext(
      (payment ?? LiveTransport((_) => throw StateError('No payment expected')))
          .api());
  if (_preview.isNotEmpty) {
    await tester.runAsync(() async {
      await (FontLoader('TipPreview')
            ..addFont(File('C:/Windows/Fonts/msyh.ttc')
                .readAsBytes()
                .then(ByteData.sublistView)))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')
            ..addFont(rootBundle
                .load('packages/cupertino_icons/assets/CupertinoIcons.ttf')))
          .load();
    });
  }
  await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: _preview.isEmpty ? null : 'TipPreview',
                  scaffoldBackgroundColor: AppTokens.background(dark: dark)),
              builder: EasyLoading.init(
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!)),
              home: Scaffold(
                  body: Builder(
                      builder: (context) => Center(
                          child: TextButton(
                              onPressed: () => GroupLiveTipSheet.show(context,
                                  featureContext: fixture,
                                  session: liveSession(status: LiveStatus.live),
                                  walletApi: wallet,
                                  security: _Security(),
                                  pendingStore: pending),
                              child: const Text('打开打赏')))))))));
  await tester.tap(find.text('打开打赏'));
  await _frames(tester);
  await tester.runAsync(() => precacheImage(
      const AssetImage('assets/img/platform_99.webp'),
      tester.element(find.text('打赏主播'))));
  await tester.pump();
  addTearDown(() async {
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  return key;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (_preview.isEmpty) return;
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_preview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WalletFundTestTransport wallet;
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    wallet = (WalletFundTestTransport()..securityCheck = ((request) => {
      'smsRequired': false, 'reasons': <String>[], 'blockedUntil': 0,
      'phoneMasked': '', 'currency': (request['tip'] as Map)['currency'],
      'smsThreshold': '5', 'cooldownHours': 2,
    }))..respond(_balances());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            _sdk,
            (_) async => jsonEncode([
                  {'userID': 'anchor', 'nickname': '主播昵称'}
                ]));
  });
  tearDown(() {
    wallet.close();
    Styles.isDark = false;
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, null);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'currency switch uses real available balances and hides TRX ($dark)',
        (tester) async {
      final key = await _mount(tester, wallet.wallet, dark: dark);
      expect(find.text('TRX'), findsNothing);
      expect(find.text('可用余额 987.65 元'), findsOneWidget);
      expect(
          tester
              .widget<CupertinoSlidingSegmentedControl<String>>(
                  find.byType(CupertinoSlidingSegmentedControl<String>))
              .groupValue,
          'BI99');
      await tester.tapAt(tester
          .getCenter(find.byKey(const ValueKey('live-tip-currency-USDT'))));
      await tester.pumpAndSettle();
      expect(find.text('可用余额 12.345678 USDT'), findsOneWidget);
      expect(
          tester
              .widget<LivePrimaryButton>(find.byType(LivePrimaryButton))
              .onPressed,
          isNull);
      expect(wallet.requests.single.path, endsWith('/chat/fund/balances'));
      expect(wallet.requests.single.method, 'GET');
      await _capture(tester, key, 'usdt-${dark ? 'dark' : 'light'}');
      await tester.tapAt(tester
          .getCenter(find.byKey(const ValueKey('live-tip-currency-BI99'))));
      await tester.pumpAndSettle();
      expect(find.text('可用余额 987.65 元'), findsOneWidget);
      expect(wallet.requests, hasLength(1));
      await tester.enterText(
          find.byKey(const ValueKey('live-tip-amount')), '8.88');
      await tester.pumpAndSettle();
      await _capture(tester, key, 'yuan-${dark ? 'dark' : 'light'}');
      wallet.respond(_balances(yuan: '0'));
      await tester.tap(find.byTooltip('刷新余额'));
      await _frames(tester);
      expect(find.text('可用余额 0.00 元'), findsOneWidget);
      await tester.tap(find.text('确认打赏'));
      await _frames(tester);
      expect(find.text('可用余额不足，请调整打赏金额'), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'balance error retries without inventing zero or leaking diagnostics',
      (tester) async {
    wallet.failure = DioExceptionType.connectionError;
    final key = await _mount(tester, wallet.wallet);
    expect(find.text('余额暂不可用，请重试'), findsOneWidget);
    expect(find.textContaining('0.00 USDT'), findsNothing);
    expect(find.textContaining('123456'), findsNothing);
    await _capture(tester, key, 'balance-error');
    wallet.failure = null;
    await tester.tap(find.byTooltip('重试余额'));
    await _frames(tester);
    expect(find.text('可用余额 987.65 元'), findsOneWidget);
    expect(wallet.requests.where((r) => r.path.endsWith('/balances')), hasLength(2));
    expect(wallet.requests.where((r) => r.path.endsWith('/withdrawal-security/check')), isEmpty);
  });

  testWidgets('new tip uses the selected currency and exact smallest units',
      (tester) async {
    final payment =
        LiveTransport((_) => {'tipId': 99, 'liveSessionId': 'live-1'});
    await _mount(tester, wallet.wallet, payment: payment);
    await tester.enterText(
        find.byKey(const ValueKey('live-tip-amount')), '1.23');
    await tester.pump();
    await tester.tap(find.text('确认打赏'));
    await _frames(tester);
    expect(find.text('1.23 元'), findsOneWidget);
    expect(find.text('打赏给 主播昵称'), findsOneWidget);
    expect(payment.requests, isEmpty);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
      await tester.pump();
    }
    await _frames(tester);
    expect(payment.requests.single.path, endsWith('/live/live-1/tip'));
    expect(payment.requests.single.data['currency'], 'BI99');
    expect(payment.requests.single.data['amount'], 123);
    expect(wallet.requests.where((r) => r.path.endsWith('/balances')), hasLength(2));
    expect(wallet.requests.where((r) => r.path.endsWith('/withdrawal-security/check')), hasLength(1));
  });

  testWidgets('tip cooldown prevents a payment request', (tester) async {
    wallet.securityCheck = (request) => {
      'smsRequired': false, 'reasons': <String>[],
      'blockedUntil': DateTime.now().millisecondsSinceEpoch + 3600000,
      'phoneMasked': '', 'currency': (request['tip'] as Map)['currency'],
      'smsThreshold': '5', 'cooldownHours': 2,
    };
    final payment = LiveTransport((_) => throw StateError('Must not pay'));
    await _mount(tester, wallet.wallet, payment: payment);
    await tester.enterText(find.byKey(const ValueKey('live-tip-amount')), '1');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认打赏'));
    await _frames(tester);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
      await tester.pump();
    }
    await _frames(tester);
    expect(find.text('暂时无法转出'), findsOneWidget);
    expect(payment.requests, isEmpty);
    await tester.tap(find.text('知道了'));
    await _frames(tester);
    EasyLoading.dismiss(animation: false);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(payment.requests, isEmpty);
  });

  testWidgets('large text and keyboard keep fields and submit reachable',
      (tester) async {
    final key = await _mount(tester, wallet.wallet, scale: 2, dark: true);
    await _capture(tester, key, 'large-text');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byKey(const ValueKey('live-tip-amount')), '1');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认打赏'));
    await tester.pumpAndSettle();
    expect(find.text('确认打赏').hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(find.byType(LivePrimaryButton)).dy,
        lessThanOrEqualTo(512));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'restored TRX order stays locked and never becomes a new USDT order',
      (tester) async {
    final store = FundPendingStore(accountKey: 'https://example.test:self');
    final draft = {
      'clientOrderID': 'tip_original',
      'groupID': 'group#1',
      'liveSessionId': 'live-1',
      'currency': 'TRX',
      'amount': 1000000,
      'amountText': '1',
      'memo': ''
    };
    await store.save('group-live-tip:group#1:live-1', draft);
    await _mount(tester, wallet.wallet, pending: store);
    expect(find.text('TRX'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('上次打赏使用的币种已不再提供，请到钱包核对原交易。'), findsOneWidget);
    expect(
        tester
            .widget<LivePrimaryButton>(find.byType(LivePrimaryButton))
            .onPressed,
        isNull);
    expect(await store.read('group-live-tip:group#1:live-1'), draft);
  });

  testWidgets(
      'pending retry bypasses spent balance and sends original BI99 units',
      (tester) async {
    wallet.respond(_balances(yuan: '0'));
    final store = FundPendingStore(accountKey: 'https://example.test:self');
    await store.save('group-live-tip:group#1:live-1', {
      'clientOrderID': 'tip_original',
      'groupID': 'group#1',
      'liveSessionId': 'live-1',
      'currency': 'BI99',
      'amount': 888,
      'amountText': '8.88',
      'memo': '谢谢'
    });
    final payment =
        LiveTransport((_) => {'tipId': 99, 'liveSessionId': 'live-1'});
    await _mount(tester, wallet.wallet, pending: store, payment: payment);
    expect(find.text('可用余额 0.00 元'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('live-tip-amount')))
            .enabled,
        isFalse);
    await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('live-tip-currency-USDT'))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CupertinoSlidingSegmentedControl<String>>(
                find.byType(CupertinoSlidingSegmentedControl<String>))
            .groupValue,
        'BI99');
    await tester.tap(find.text('重试原交易'));
    await _frames(tester);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
      await tester.pump();
    }
    await _frames(tester);
    expect(payment.requests.single.data, {
      'clientOrderId': 'tip_original',
      'currency': 'BI99',
      'amount': 888,
      'payPin': '123456',
      'memo': '谢谢'
    });
    expect(await store.read('group-live-tip:group#1:live-1'), isNull);
  });
}
