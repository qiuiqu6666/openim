import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/wallet/deposit/coin_picker/wallet_deposit_coin_picker_screen.dart';
import 'package:openim/pages/wallet/widgets/wallet_99chat_tokens.dart';
import 'package:openim_common/openim_common.dart' show Styles;

import '../../support/wallet_deposit_test_support.dart';

export '../../support/wallet_deposit_test_support.dart';
export 'package:openim/pages/wallet/data/wallet_fund_api.dart';

class CoinPickerRouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    super.didPush(route, previousRoute);
  }
}

Future<void> pumpWalletDepositCoins(
  WidgetTester tester, {
  required WalletTestFundApi api,
  String Function()? accountProvider,
  DepositTestShareService? share,
  CoinPickerRouteObserver? observer,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  Size size = const Size(390, 844),
  double textScale = 1,
  GlobalKey? boundaryKey,
  String? fontFamily,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  final previousLocale = Get.locale;
  final previousDark = Styles.isDark;
  Get.locale = locale;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() {
    Get.locale = previousLocale;
    Styles.isDark = previousDark;
  });
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en'),
        Locale('ja'),
        Locale('ko'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: observer == null ? [] : [observer],
      theme: ThemeData(
        brightness: brightness,
        fontFamily: fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTokens.accent,
          brightness: brightness,
          surface: AppTokens.appSurface(brightness == Brightness.dark),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: boundaryKey,
        child: WalletDepositCoinPickerScreen(
          api: api,
          accountProvider: accountProvider ?? () => 'server:test-user',
          shareService: share ?? DepositTestShareService(),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Finder coinKey(String key) => find.byKey(ValueKey(key));
Finder coinRow(String code, {bool searching = false}) =>
    coinKey('wallet-deposit-coin-${searching ? "search" : "hot"}-$code');

Future<void> searchCoins(WidgetTester tester, String query) async {
  await tester.enterText(coinKey('wallet-deposit-coin-search'), query);
  await tester.pump();
}
