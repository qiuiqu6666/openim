import '../order/wallet_order_events.dart';
import '../record/wallet_record_amount.dart';
import '../record/wallet_record_models.dart';
import '../record/journals/wallet_journal_page.dart';
import '../record/journals/wallet_journal_query.dart';
import '../record/journals/wallet_journal_source.dart';
import '../record/journals/wallet_journal_counterparty_source.dart';
import '../wallet_repository.dart';
import 'wallet_fund_api.dart';
import 'wallet_history_source_boundary.dart';
import 'wallet_session_source.dart';
import 'wallet_trend_data.dart';

/// Converts the user-facing fund APIs into the existing Wallet view contract.
/// Uses server valuations for all available balances without repricing locally.
class WalletFundRepository extends UnavailableWalletRepository
    implements
        WalletHistorySourceBoundary,
        WalletSessionSource,
        WalletJournalSource,
        WalletJournalCounterpartySource,
        WalletJournalCounterpartyProfileSource,
        WalletTrendSource {
  WalletFundRepository({
    WalletFundApi? api,
    String Function()? accountProvider,
    WalletJournalCounterpartySource? counterpartySource,
  })  : _api = api ?? WalletFundApi(),
        _accountProvider =
            accountProvider ?? (() => WalletOrderEvents.currentAccountKey) {
    ownerAccountKey = _accountProvider();
    _counterpartySource = counterpartySource ??
        OpenIMWalletJournalCounterpartySource(
            accountProvider: _accountProvider);
  }

  final WalletFundApi _api;
  final String Function() _accountProvider;
  late final WalletJournalCounterpartySource _counterpartySource;
  @override
  late final String ownerAccountKey;
  @override
  bool get isCurrentAccount => _accountProvider() == ownerAccountKey;
  @override
  bool get hasCompleteLedger => false;
  @override
  bool get hasWithdrawalHistory => false;
  @override
  int get depositRecordLimit => 100;

  void _requireCurrentAccount() {
    if (!isCurrentAccount) throw const WalletAccountChangedException();
  }

  @override
  Future<Map<String, String>> getNicknames(Set<String> userIDs) async {
    _requireCurrentAccount();
    final names = await _counterpartySource.getNicknames(userIDs);
    _requireCurrentAccount();
    return names;
  }

  @override
  Future<Map<String, WalletJournalCounterpartyProfile>> getProfiles(
      Set<String> userIDs) async {
    _requireCurrentAccount();
    final source = _counterpartySource;
    final Map<String, WalletJournalCounterpartyProfile> profiles;
    if (source is WalletJournalCounterpartyProfileSource) {
      profiles = await (source as WalletJournalCounterpartyProfileSource)
          .getProfiles(userIDs);
    } else {
      final names = await source.getNicknames(userIDs);
      profiles = Map.unmodifiable({
        for (final entry in names.entries)
          entry.key: WalletJournalCounterpartyProfile(nickname: entry.value),
      });
    }
    _requireCurrentAccount();
    return profiles;
  }

  @override
  Future<WalletTrendData> getTrend() async {
    _requireCurrentAccount();
    final data = await _api.fetchTrend();
    _requireCurrentAccount();
    return data;
  }

  @override
  Future<WalletJournalPage> getJournalPage(WalletJournalQuery query) async {
    _requireCurrentAccount();
    final page = await _api.fetchJournals(query);
    _requireCurrentAccount();
    return page;
  }

  @override
  Future<WalletDto> getWallet() async {
    _requireCurrentAccount();
    final snapshot = await _api.fetchBalanceSnapshot();
    final balances = snapshot.balances;
    _requireCurrentAccount();
    final byCurrency = {for (final item in balances) item.currency: item};
    if (byCurrency.length != FundCurrency.values.length ||
        balances.length != FundCurrency.values.length) {
      throw const FormatException('Incomplete wallet balances');
    }
    return WalletDto(
      totalBal: snapshot.totalCny,
      dailyAmountCny: snapshot.dailyAmountCny,
      dailyPercentage: snapshot.dailyPercentage,
      trxAddr: '',
      coins: [
        for (final currency in FundCurrency.values)
          _coin(byCurrency[currency]!,
              fiat: snapshot.valuesCny[currency] == null ||
                      snapshot.valuesCny[currency] == '--'
                  ? '--'
                  : '¥${snapshot.valuesCny[currency]}',
              changeAmountCny: snapshot.changesCny[currency],
              changePercent: snapshot.changePercentages[currency]),
      ],
    );
  }

  CoinDto _coin(FundBalance balance,
      {String fiat = '--', String? changeAmountCny, String? changePercent}) {
    final currency = balance.currency;
    final platform = currency == FundCurrency.bi99;
    final units = balance.available.units;
    final minor = units.toInt();
    final fitsLegacyMinor = BigInt.from(minor) == units;
    return CoinDto(
      name: platform ? '99' : currency.code,
      code: platform ? '99' : currency.code,
      type: switch (currency) {
        FundCurrency.usdt => CoinType.usdt,
        FundCurrency.trx => CoinType.trx,
        FundCurrency.bi99 => CoinType.cny,
      },
      bal: walletRecordAmountTwoDecimals(balance.available.decimal),
      availableRaw: balance.available.decimal,
      frozen: balance.frozen.decimal,
      fiat: fiat,
      changeAmountCny: changeAmountCny,
      changePercent: changePercent,
      sub: '--',
      balMinor: fitsLegacyMinor ? minor : 0,
      scale: currency.decimals,
      platformCoin: platform,
      depositEnabled: !platform,
      // Legacy int-based controls must not receive a truncated BigInt. New
      // fund payment flows use the exact available units from their API.
      withdrawEnabled: fitsLegacyMinor,
    );
  }

  @override
  Future<List<WalletPayMethodDto>> getPayMethods() async => (await getWallet())
      .coins
      .map((coin) => coin.toPayMethod(net: 'TRON'))
      .toList(growable: false);

  @override
  Future<List<WalletRecordDto>> getDepositRecords() async {
    _requireCurrentAccount();
    final deposits = await _api.fetchDeposits();
    _requireCurrentAccount();
    if (deposits.any(
        (record) => !const ['credited', 'orphaned'].contains(record.status))) {
      throw const FormatException('Unsupported deposit status');
    }
    return List<WalletRecordDto>.unmodifiable([
      for (final deposit in deposits)
        WalletRecordDto(
          // The API can include several events with the same tx hash.
          id: 'deposit:${deposit.occurrenceIndex}:${deposit.txID}',
          type: WalletRecordType.receive,
          status: deposit.status == 'orphaned'
              ? WalletRecordStatus.failed
              : WalletRecordStatus.success,
          title: deposit.status == 'orphaned' ? '充值已撤销' : '链上充值',
          subTitle: '',
          amount: deposit.amount,
          coin: deposit.currency == FundCurrency.bi99
              ? '99'
              : deposit.currency.code,
          income: deposit.status != 'orphaned',
          network: 'TRON',
          fee: '',
          payer: '',
          payee: deposit.address,
          addr: deposit.address,
          hash: deposit.txID,
          block: '${deposit.height}',
          // Deposit history has no timestamp; a block height is not a date.
          time: '',
          orderNo: '',
          memo: deposit.status == 'orphaned' ? '区块回滚撤销' : '',
        ),
    ]);
  }

  @override
  Future<List<WalletRecordDto>> getWithdrawRecords() async {
    _requireCurrentAccount();
    // No client withdrawal-list endpoint exists. The boundary is displayed
    // by record routes instead of fabricating orders from balance changes.
    return const [];
  }
}
