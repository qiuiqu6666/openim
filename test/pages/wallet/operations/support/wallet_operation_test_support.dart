import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_coordinator.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';
import 'package:openim/services/fund_api.dart' show FundApiException;
import 'package:openim/pages/fund/withdrawal_security/withdrawal_security.dart';
import '../../data/wallet_fund_test_api.dart' show depositAddressFixture;

const walletOperationTestAddress = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';

Future<FundSecurityProof?> approveWalletSecurityForTest(
        BuildContext context, FundSecurityRequest request) async =>
    const FundSecurityProof();

CoinDto withdrawalTestCoin(FundCurrency currency) => CoinDto(
    name: currency.displayName,
    code: currency.code,
    sub: '--',
    bal: '100',
    fiat: '--',
    type: currency == FundCurrency.trx ? CoinType.trx : CoinType.usdt,
    scale: currency.decimals,
    balMinor: 100000000);

WalletPayMethodDto withdrawalTestMethod(FundCurrency currency) =>
    WalletPayMethodDto(
        id: currency.code,
        coin: currency.displayName,
        code: currency.code,
        net: 'TRON',
        bal: '100',
        fiat: '--',
        balMinor: 100000000,
        scale: currency.decimals,
        color: Colors.blue,
        badgeColor: Colors.blue,
        badge: 'TRON');

class WalletOperationTestSettings extends StubSettingsService {
  int statusCalls = 0;
  bool passwordSet = true;
  @override
  Future<bool> hasTradePassword() async {
    statusCalls++;
    return passwordSet;
  }
}

/// Fixtures only: no endpoint or real account is contacted by these tests.
class WalletOperationTestApi extends WalletFundApi {
  int depositAddressCalls = 0;
  WalletDepositAddress? depositAddress;
  Future<WalletDepositAddress> Function()? onDepositAddress;

  @override
  Future<WalletDepositAddress> fetchDepositAddress() {
    depositAddressCalls++;
    return onDepositAddress?.call() ??
        Future.value(depositAddress ?? depositAddressFixture());
  }

  final writes = <Map<String, dynamic>>[];
  final queriedIDs = <String>[];
  final queriedClientIDs = <String>[];
  final quoteRequests = <Map<String, dynamic>>[];
  final issuedQuotes = <String, WalletSwapQuote>{};
  int balanceCalls = 0;
  Future<WalletWithdrawResult> Function(Map<String, dynamic>)? onWithdraw;
  Future<WalletSwapResult> Function(Map<String, dynamic>)? onSwap;
  Future<WalletSwapQuote> Function(Map<String, dynamic>)? onQuote;
  Future<WalletFundOrder> Function(String)? onOrderByClient;
  DateTime Function() now = DateTime.now;
  WalletFundOrder? lastOrder;

  @override
  Future<WalletSwapQuote> fetchSwapQuote(
      {required FundAmount amount, required FundCurrency toCurrency}) async {
    final request = <String, dynamic>{
      'fromCurrency': amount.currency.code,
      'toCurrency': toCurrency.code,
      'amount': amount.decimal,
    };
    quoteRequests.add(request);
    final quote = onQuote == null
        ? walletSwapTestQuote(amount, toCurrency,
            quoteID: 'quote-${quoteRequests.length}',
            expiresAt: now().add(const Duration(seconds: 30)))
        : await onQuote!(request);
    issuedQuotes[quote.quoteID] = quote;
    return quote;
  }

  @override
  Future<List<FundBalance>> fetchBalances() async {
    balanceCalls++;
    return FundCurrency.values
        .map((coin) => FundBalance(
            currency: coin,
            available: FundAmount.parse('100', coin),
            frozen: FundAmount.zero(coin)))
        .toList();
  }

  @override
  Future<WalletWithdrawResult> withdraw(
      {required String clientOrderID,
      required FundAmount amount,
      required String toAddress,
      required String payPassword,
      String? verifyChallengeID,
      String? verifyCode}) async {
    final write = <String, dynamic>{
      'clientOrderID': clientOrderID,
      'currency': amount.currency.code,
      'amount': amount.decimal,
      'toAddress': toAddress,
      'payPassword': payPassword,
      if (verifyChallengeID != null) 'verifyChallengeID': verifyChallengeID,
      if (verifyCode != null) 'verifyCode': verifyCode,
    };
    writes.add(write);
    if (onWithdraw != null) return onWithdraw!(write);
    final order = WalletFundOrder(
        orderID: 'withdraw-${writes.length}',
        clientOrderID: clientOrderID,
        biz: 'withdraw',
        currency: amount.currency,
        amount: amount.decimal,
        status: 'withdraw_done',
        toAddress: toAddress,
        fee: '0.25');
    lastOrder = order;
    return WalletWithdrawResult(order: order, fee: '0.25');
  }

  @override
  Future<WalletSwapResult> swap(
      {required String clientOrderID,
      required FundAmount amount,
      required FundCurrency toCurrency,
      required String payPassword,
      String? quoteID}) async {
    final write = <String, dynamic>{
      'clientOrderID': clientOrderID,
      'currency': amount.currency.code,
      'amount': amount.decimal,
      'toCurrency': toCurrency.code,
      'payPassword': payPassword,
      if (quoteID != null) 'quoteID': quoteID,
    };
    writes.add(write);
    if (onSwap != null) return onSwap!(write);
    final quote = quoteID == null ? null : issuedQuotes[quoteID];
    if (quoteID != null &&
        (quote == null || !quote.matches(amount, toCurrency))) {
      throw const FundApiException(20074, '报价与请求不一致');
    }
    final received = quote?.estimatedReceived.decimal ??
        (toCurrency == FundCurrency.bi99 ? '2.34' : '2.345678');
    final order = WalletFundOrder(
        orderID: 'swap-${writes.length}',
        clientOrderID: clientOrderID,
        biz: 'swap',
        currency: amount.currency,
        amount: amount.decimal,
        status: 'done',
        targetCurrency: toCurrency,
        targetAmount: received,
        quoteID: quoteID);
    lastOrder = order;
    return WalletSwapResult(order: order, received: received);
  }

  @override
  Future<WalletFundOrder> getOrder(String orderID) async {
    queriedIDs.add(orderID);
    return lastOrder!;
  }

  @override
  Future<WalletFundOrder> getOrderByClient(String clientOrderID) async {
    queriedClientIDs.add(clientOrderID);
    if (onOrderByClient != null) return onOrderByClient!(clientOrderID);
    final order = lastOrder;
    if (order == null || order.clientOrderID != clientOrderID) {
      throw const FundApiException(20032, '订单不存在');
    }
    return order;
  }
}

/// Independent test prices: USDT=$1, TRX=$0.25, BI99=$0.125. Received units
/// round down to the destination precision; production never derives prices.
WalletSwapQuote walletSwapTestQuote(FundAmount amount, FundCurrency toCurrency,
    {String quoteID = 'quote-fixture', DateTime? expiresAt}) {
  const pricesInEighths = <FundCurrency, int>{
    FundCurrency.usdt: 8,
    FundCurrency.trx: 2,
    FundCurrency.bi99: 1,
  };
  final fromPrice = BigInt.from(pricesInEighths[amount.currency]!);
  final toPrice = BigInt.from(pricesInEighths[toCurrency]!);
  final fromScale = BigInt.from(10).pow(amount.currency.decimals);
  final toScale = BigInt.from(10).pow(toCurrency.decimals);
  final receivedUnits =
      amount.units * fromPrice * toScale ~/ (fromScale * toPrice);
  final usdCents = amount.units *
      fromPrice *
      BigInt.from(100) ~/
      (fromScale * BigInt.from(8));
  final rateUnits = fromPrice * BigInt.from(10).pow(18) ~/ toPrice;
  final rate = _walletFixtureDecimal(rateUnits, 18);
  return WalletSwapQuote(
      quoteID: quoteID,
      amount: amount,
      toCurrency: toCurrency,
      estimatedReceived: FundAmount.parse(
          _walletFixtureDecimal(receivedUnits, toCurrency.decimals),
          toCurrency),
      rate: rate,
      marketRate: rate,
      adjustmentPercent: '0',
      inputValueUsd: _walletFixtureDecimal(usdCents, 2),
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(seconds: 30)));
}

String _walletFixtureDecimal(BigInt units, int decimals) {
  final scale = BigInt.from(10).pow(decimals);
  return '${units ~/ scale}.${(units % scale).toString().padLeft(decimals, '0')}';
}

WalletOperationCoordinator testWalletOperation(
        WalletOperationKind kind, WalletOperationTestApi api,
        {String accountID = 'fixture-user', bool Function()? isCurrent}) =>
    WalletOperationCoordinator(
        kind: kind,
        api: api,
        serverURL: 'https://wallet.test/',
        accountID: accountID,
        isAccountCurrent: isCurrent ?? () => true);

Future<void> pumpWalletOperation(WidgetTester tester, Widget page,
    {Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
    double textScale = 1,
    GlobalKey? boundaryKey,
    String? fontFamily}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() => EasyLoading.dismiss(animation: false));
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: ThemeData(brightness: brightness, fontFamily: fontFamily),
            builder: EasyLoading.init(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(textScale)),
                    child: boundaryKey == null
                        ? child!
                        : RepaintBoundary(key: boundaryKey, child: child!))),
            home: page,
          )));
  await tester.pumpAndSettle();
}

Future<void> enterWalletOperationPin(WidgetTester tester) async {
  for (final digit in '123456'.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.pumpAndSettle();
  // Let the production success toast finish inside the test body, before
  // Flutter checks pending timers (which happens before addTearDown callbacks).
  if (find.text('支付成功').evaluate().isNotEmpty) {
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

Future<void> confirmWalletSwapQuote(WidgetTester tester) async {
  final confirm = find.byKey(const ValueKey('wallet-swap-quote-confirm'));
  await tester.ensureVisible(confirm);
  await tester.pumpAndSettle();
  expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

/// Close the real page to exercise cancellation of its quote timers. Flutter's
/// pending-timer checks remain enabled throughout these tests.
Future<void> disposeWalletOperationPage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Enter through the visible swap keypad, never through a text controller or
/// the separate payment-password keypad.
Future<void> enterWalletSwapAmount(WidgetTester tester, String amount) async {
  for (final character in amount.split('')) {
    final key = character == '.' ? 'decimal' : character;
    final finder = find.byKey(ValueKey('wallet-swap-key-$key'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> selectWalletSwapCurrency(
    WidgetTester tester, String pickerKey, FundCurrency currency) async {
  final picker = find.byKey(ValueKey(pickerKey));
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(currency.displayName).last);
  await tester.pumpAndSettle();
  expect(tester.widget<DropdownButton<FundCurrency>>(picker).value, currency);
}
