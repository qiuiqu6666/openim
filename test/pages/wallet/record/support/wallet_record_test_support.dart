import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';
import 'package:openim/pages/wallet/record/wallet_record_screen.dart';
import 'package:openim/pages/wallet/host/app_empty_state.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';
import 'package:openim/pages/wallet/widgets/platform_coin_icon.dart';
import 'package:openim/pages/wallet/widgets/wallet_99chat_tokens.dart';
import 'package:openim_common/openim_common.dart' show Styles;

import '../fixtures/wallet_record_fixtures.dart';

class RecordTestRepository extends UnavailableWalletRepository {
  RecordTestRepository({List<WalletRecordDto>? records})
      : records = records ?? walletRecordFixtures;

  List<WalletRecordDto> records;
  int depositCalls = 0;
  int withdrawCalls = 0;
  Future<List<WalletRecordDto>> Function()? respondDeposits;
  Future<List<WalletRecordDto>> Function()? respondWithdrawals;

  @override
  Future<List<WalletRecordDto>> getDepositRecords() {
    depositCalls++;
    return respondDeposits?.call() ??
        Future.value(records.where((record) => record.income).toList());
  }

  @override
  Future<List<WalletRecordDto>> getWithdrawRecords() {
    withdrawCalls++;
    return respondWithdrawals?.call() ??
        Future.value(records.where((record) => !record.income).toList());
  }
}

class RecordRouteObserver extends NavigatorObserver {
  Route<dynamic>? lastPush;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) lastPush = route;
    super.didPush(route, previousRoute);
  }
}

const walletRecordLocales = [
  Locale('zh', 'CN'),
  Locale('zh', 'TW'),
  Locale('en', 'US'),
  Locale('ja', 'JP'),
  Locale('ko', 'KR'),
];

Finder walletRecordKey(String key) => find.byKey(ValueKey(key));

Future<void> pumpWalletRecords(
  WidgetTester tester, {
  WalletRepository? repository,
  String? initialCoin,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
  EdgeInsets safePadding = EdgeInsets.zero,
  GlobalKey? boundaryKey,
  RecordRouteObserver? observer,
  String? fontFamily,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final previousLocale = Get.locale;
  Get.locale = locale;
  addTearDown(() => Get.locale = previousLocale);
  final dark = brightness == Brightness.dark;
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: locale,
      supportedLocales: walletRecordLocales,
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
          surface: AppTokens.appSurface(dark),
        ),
        scaffoldBackgroundColor: AppTokens.appBackground(dark),
        splashFactory: InkRipple.splashFactory,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: safePadding,
        ),
        child: child!,
      ),
      home: RepaintBoundary(
        key: boundaryKey,
        child: WalletRecordScreen(
          initialCoin: initialCoin,
          repository: repository,
        ),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> settleWalletRecordImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byType(WalletRecordScreen));
    await Future.wait([
      precacheImage(const AssetImage(PlatformCoinIcon.assetPath), context),
      precacheImage(const AssetImage(AppEmptyState.assetPath), context),
    ]);
  });
  await tester.pumpAndSettle();
}

Future<void> refreshWalletRecords(WidgetTester tester) async {
  await tester.drag(
      walletRecordKey('wallet-record-scroll'), const Offset(0, 500));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void expectRecordRequests(RecordTestRepository repository, int count) {
  expect(repository.depositCalls, count);
  expect(repository.withdrawCalls, count);
}
