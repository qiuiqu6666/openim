import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/fund/fund_send_page.dart';
import 'package:openim/pages/wallet/data/wallet_session_source.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';
import 'package:openim/pages/wallet/withdrawal/form/wallet_chain_withdrawal_screen.dart';
import 'package:openim/pages/wallet/withdraw_coin_picker_screen.dart';
import 'package:openim/pages/wallet/withdraw_transfer_target_validator.dart';
import 'package:openim_common/openim_common.dart' show Styles;

import '../../../home/wallet_home_test_support.dart';

export '../../../home/wallet_home_test_support.dart'
    show HomeTestRepository, HomeRouteObserver;
export 'package:openim/pages/wallet/wallet_repository.dart';
export 'package:openim/pages/wallet/withdraw_transfer_target_validator.dart';

/// Test fixtures only: these amounts are never sent to an endpoint.
const withdrawUsdtFixture = CoinDto(
  name: 'Backend stable token',
  code: 'USDT',
  sub: '¥7.09',
  bal: '12.35',
  fiat: '¥87.53',
  type: CoinType.usdt,
  balMinor: 12345678,
  scale: 6,
  availableRaw: '12.345678',
  frozen: '4.1',
);
const withdrawTrxFixture = CoinDto(
  name: 'Backend TRX token',
  code: 'TRX',
  sub: '¥1.05',
  bal: '8.01',
  fiat: '¥8.41',
  type: CoinType.trx,
  balMinor: 8010001,
  scale: 6,
  availableRaw: '8.010001',
  frozen: '0',
);
const withdrawPlatformFixture = CoinDto(
  name: 'Backend reward token',
  code: '99',
  sub: '¥1.00',
  bal: '9.00',
  fiat: '¥9.00',
  type: CoinType.cny,
  platformCoin: true,
  balMinor: 900,
  scale: 2,
  availableRaw: '9',
  frozen: '1.2',
);
const withdrawDisabledFixture = CoinDto(
  name: 'Disabled token',
  code: 'LOCKED',
  sub: '--',
  bal: '100.00',
  fiat: '--',
  type: CoinType.trx,
  withdrawEnabled: false,
);

WalletDto withdrawWalletFixture({List<CoinDto>? coins}) => WalletDto(
      totalBal: '104.94',
      trxAddr: '',
      coins: coins ??
          const [
            withdrawUsdtFixture,
            withdrawTrxFixture,
            withdrawPlatformFixture,
            withdrawDisabledFixture,
          ],
    );

/// Reuses the home repository fake with the production account boundary.
class WithdrawSessionTestRepository extends HomeTestRepository
    implements WalletSessionSource {
  WithdrawSessionTestRepository({WalletDto? data})
      : super(data: data ?? withdrawWalletFixture());

  @override
  final ownerAccountKey = 'fixture-server:withdraw-user';
  String currentAccountKey = 'fixture-server:withdraw-user';
  @override
  bool get isCurrentAccount => currentAccountKey == ownerAccountKey;
}

class WithdrawCoinRouteObserver extends HomeRouteObserver {
  int detailPushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) detailPushes++;
    super.didPush(route, previousRoute);
  }
}

Future<void> pumpWalletWithdrawCoins(
  WidgetTester tester, {
  HomeTestRepository? repository,
  WithdrawTransferTargetKind kind = WithdrawTransferTargetKind.friend,
  WithdrawCoinRouteObserver? observer,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  Size size = const Size(390, 844),
  double textScale = 1,
  GlobalKey? boundaryKey,
  String? fontFamily,
}) async {
  final previousDark = Styles.isDark;
  final previousLocale = Get.locale;
  addTearDown(tester.view.resetViewInsets);
  addTearDown(() {
    Styles.isDark = previousDark;
    Get.locale = previousLocale;
  });
  Get.locale = locale;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final controller = WalletController(repo: HomeTestRepository());
  addTearDown(controller.dispose);
  await pumpWalletHome(
    tester,
    controller: controller,
    observer: observer,
    brightness: brightness,
    locale: locale,
    size: size,
    textScale: textScale,
    boundaryKey: boundaryKey,
    fontFamily: fontFamily,
    page: WithdrawCoinPickerScreen(
      repository:
          repository ?? HomeTestRepository(data: withdrawWalletFixture()),
      initialTargetKind: kind,
    ),
  );
  await tester.pump();
}

Finder withdrawCoinKey(String suffix) =>
    find.byKey(ValueKey('wallet-withdraw-coin-$suffix'));
Finder withdrawCoinRow(String code, {String section = 'hot'}) =>
    withdrawCoinKey('$section-$code');

Future<void> searchWithdrawCoins(WidgetTester tester, String query) async {
  await tester.enterText(withdrawCoinKey('search'), query);
  await tester.pump();
}

VoidCallback withdrawCoinCallback(WidgetTester tester, Finder row) => tester
    .widget<InkWell>(
        find.descendant(of: row, matching: find.byType(InkWell)).first)
    .onTap!;

WalletChainWithdrawalScreen inspectWithdrawDestination(
  WidgetTester tester,
  WithdrawCoinRouteObserver observer,
) {
  final route = observer.lastPush! as PageRouteBuilder;
  return route.pageBuilder(
    tester.element(find.byType(WithdrawCoinPickerScreen)),
    const AlwaysStoppedAnimation(1),
    const AlwaysStoppedAnimation(0),
  ) as WalletChainWithdrawalScreen;
}

FundSendPage inspectInternalTransferDestination(
  WidgetTester tester,
  WithdrawCoinRouteObserver observer,
) {
  final route = observer.lastPush! as PageRouteBuilder;
  return route.pageBuilder(
    tester.element(find.byType(WithdrawCoinPickerScreen)),
    const AlwaysStoppedAnimation(1),
    const AlwaysStoppedAnimation(0),
  ) as FundSendPage;
}

Future<void> removeWithdrawDestination(
    WidgetTester tester, WithdrawCoinRouteObserver observer) async {
  // Avoid mounting the destination's real SDK-backed contacts and wallet API.
  observer.navigator!.removeRoute(observer.lastPush!);
  await tester.pumpAndSettle();
}
