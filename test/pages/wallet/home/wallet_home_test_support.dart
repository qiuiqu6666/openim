import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/home/wallet_home_view.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';
import 'package:openim/pages/wallet/widgets/platform_coin_icon.dart';
import 'package:openim_common/openim_common.dart';
import 'package:provider/provider.dart';

/// Test-only wallet data. Production continues to use its existing repository.
const walletHomeFixture = WalletDto(
  totalBal: '8,652.48',
  totalBalUsd: '1,220.16',
  trxAddr: 'TExampleTestAddress',
  coins: [
    CoinDto(
      name: '99币',
      code: '99',
      sub: '¥ 1.00',
      bal: '5,800.00',
      fiat: '¥5,800.00',
      type: CoinType.cny,
      platformCoin: true,
      balMinor: 580000,
      scale: 2,
    ),
    CoinDto(
      name: 'USDT',
      code: 'USDT',
      sub: '¥ 7.09',
      bal: '402.325811',
      fiat: '¥2,852.48',
      type: CoinType.usdt,
      balMinor: 402325811,
      scale: 6,
    ),
  ],
);

const walletHomeFilterFixture = WalletDto(
  totalBal: '10.10',
  trxAddr: '',
  coins: [
    CoinDto(
        name: 'Small asset',
        code: 'SMALL',
        sub: '',
        bal: '0.1',
        fiat: '¥0.10',
        type: CoinType.trx),
    CoinDto(
        name: 'Known holding',
        code: 'KNOWN',
        sub: '',
        bal: '10',
        fiat: '¥10.00',
        type: CoinType.trx),
    CoinDto(
        name: 'Unknown valuation',
        code: 'UNKNOWN',
        sub: '',
        bal: '3',
        fiat: '--',
        type: CoinType.trx),
  ],
);

const walletHomeLongFixture = WalletDto(
  totalBal: '123,456,789,012,345,678.99',
  totalBalUsd: '17,412,805,220,358,205.99',
  trxAddr: '',
  coins: [
    CoinDto(
      name: 'Very long international asset name 超长资产名称测试',
      code: 'LONG',
      sub: '¥ 123,456,789.00000000',
      bal: '123,456,789,012,345.123456',
      fiat: '¥123,456,789,012,345,678.99',
      type: CoinType.usdt,
      scale: 6,
    ),
  ],
);

class HomeTestRepository extends UnavailableWalletRepository {
  HomeTestRepository({WalletDto data = walletHomeFixture}) : _data = data;

  final WalletDto _data;
  int walletCalls = 0;
  Future<WalletDto> Function()? respond;

  @override
  Future<WalletDto> getWallet() {
    walletCalls++;
    return respond?.call() ?? Future.value(_data);
  }
}

class HomeRouteObserver extends NavigatorObserver {
  Route<dynamic>? lastPush;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) lastPush = route;
    super.didPush(route, previousRoute);
  }
}

const walletHomeLocales = [
  Locale('zh', 'CN'),
  Locale('zh', 'TW'),
  Locale('en', 'US'),
  Locale('ja', 'JP'),
  Locale('ko', 'KR'),
];

Future<void> pumpWalletHome(
  WidgetTester tester, {
  required WalletController controller,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
  EdgeInsets safePadding = EdgeInsets.zero,
  GlobalKey? boundaryKey,
  HomeRouteObserver? observer,
  String? fontFamily,
  Widget? page,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final dark = brightness == Brightness.dark;
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: locale,
      supportedLocales: walletHomeLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [if (observer != null) observer],
      theme: ThemeData(
        brightness: brightness,
        fontFamily: fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTokens.accent,
          brightness: brightness,
          surface: AppTokens.surface(dark: dark),
        ),
        scaffoldBackgroundColor: AppTokens.background(dark: dark),
        splashFactory: InkRipple.splashFactory,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: safePadding,
        ),
        child: child!,
      ),
      home: ChangeNotifierProvider<WalletController>.value(
        value: controller,
        child: RepaintBoundary(
          key: boundaryKey,
          child: page ?? const Scaffold(body: WalletHomeView()),
        ),
      ),
    ),
  ));
  await tester.pump();
}

Future<WalletController> loadedHomeController({
  HomeTestRepository? repository,
}) async {
  final controller = WalletController(repo: repository ?? HomeTestRepository());
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

Finder walletHomeKey(String key) => find
    .byKey(key == 'wallet-home-scroll' ? PageStorageKey(key) : ValueKey(key));

Future<void> settleWalletHomeImages(WidgetTester tester) async {
  await tester.runAsync(() => precacheImage(
      const AssetImage(PlatformCoinIcon.assetPath),
      tester.element(find.byType(WalletHomeView))));
  await tester.pumpAndSettle();
}
