import 'dart:async';

import 'package:openim/pages/wallet/data/wallet_fund_api.dart';

const testDepositAddress = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';
const testUsdtContract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

WalletDepositAddress depositAddressFixture(
        {bool ready = true, bool withRules = true}) =>
    WalletDepositAddress(
        status: ready ? 'ready' : 'pending',
        network: 'TRON',
        address: ready ? testDepositAddress : '',
        currencies: const [FundCurrency.usdt, FundCurrency.trx],
        confirmations: 19,
        usdtContract: testUsdtContract,
        currencyRules: withRules
            ? {
                for (final currency in [FundCurrency.usdt, FundCurrency.trx])
                  currency: WalletCurrencyRule(
                    currency: currency,
                    minDepositAmount:
                        currency == FundCurrency.usdt ? '0.1' : '1',
                    minWithdrawAmount: '0.1',
                    withdrawFee: '0.25',
                    withdrawFeeCurrency: currency,
                    receivingAccountType: 'wallet',
                    estimatedArrivalSeconds: 120,
                    withdrawUnlockConfirmations: 33,
                    memoRequired: false,
                  ),
              }
            : const {});

List<FundBalance> balancesFixture(
        {String usdt = '12.345678', String frozen = '4.1'}) =>
    [
      FundBalance.fromJson(
          {'currency': 'USDT', 'available': usdt, 'frozen': frozen},
          allowNegativeAvailable: true),
      FundBalance.fromJson(
          {'currency': 'TRX', 'available': '8.010001', 'frozen': '0'}),
      FundBalance.fromJson(
          {'currency': 'BI99', 'available': '9', 'frozen': '1.2'}),
    ];

const depositEventsFixture = [
  WalletDepositRecord(
      txID: 'same-tx',
      currency: FundCurrency.usdt,
      amount: '12.345678',
      address: testDepositAddress,
      height: 999,
      status: 'credited',
      occurrenceIndex: 0,
      confirmations: 19),
  WalletDepositRecord(
      txID: 'same-tx',
      currency: FundCurrency.trx,
      amount: '8.010001',
      address: testDepositAddress,
      height: 999,
      status: 'credited',
      occurrenceIndex: 1),
  WalletDepositRecord(
      txID: 'reverted-tx',
      currency: FundCurrency.usdt,
      amount: '1.25',
      address: testDepositAddress,
      height: 998,
      status: 'orphaned',
      occurrenceIndex: 0),
];

/// All sample wallet values live in tests; this fake never contacts a server.
class WalletTestFundApi extends WalletFundApi {
  WalletTestFundApi(
      {WalletDepositAddress? address,
      List<FundBalance>? balances,
      this.deposits = depositEventsFixture})
      : address = address ?? depositAddressFixture(),
        balances = balances ?? balancesFixture();
  WalletDepositAddress address;
  List<FundBalance> balances;
  List<WalletDepositRecord> deposits;
  int addressCalls = 0;
  int balanceCalls = 0;
  int depositCalls = 0;
  Future<WalletDepositAddress> Function()? respondAddress;
  Future<List<FundBalance>> Function()? respondBalances;
  Future<List<WalletDepositRecord>> Function()? respondDeposits;

  @override
  Future<WalletDepositAddress> fetchDepositAddress() {
    addressCalls++;
    return respondAddress?.call() ?? Future.value(address);
  }

  @override
  Future<WalletBalanceSnapshot> fetchBalanceSnapshot() async =>
      WalletBalanceSnapshot(balances: await fetchBalances());

  @override
  Future<List<FundBalance>> fetchBalances() {
    balanceCalls++;
    return respondBalances?.call() ?? Future.value(balances);
  }

  @override
  Future<List<WalletDepositRecord>> fetchDeposits() {
    depositCalls++;
    return respondDeposits?.call() ?? Future.value(deposits);
  }
}
