import '../../../services/fund_api.dart';
import '../exchange/data/wallet_swap_quote.dart';
import '../record/journals/wallet_journal_page.dart';
import '../record/journals/wallet_journal_query.dart';
import 'wallet_fund_models.dart';
import 'wallet_balance_snapshot.dart';
import 'wallet_trend_data.dart';

export 'wallet_balance_snapshot.dart';
export '../exchange/data/wallet_swap_quote.dart';

export '../../../services/fund_models.dart'
    show FundAmount, FundBalance, FundCurrency;
export 'wallet_fund_models.dart';

/// Wallet-only endpoints reuse Chat authentication and fund transport.
class WalletFundApi {
  WalletFundApi({FundApi? api}) : _api = api ?? FundApi();
  final FundApi _api;

  /// The same authenticated transport is used by transaction security checks.
  FundApi get transport => _api;

  Future<WalletTrendData> fetchTrend() async => WalletTrendData.fromJson(
      await _api.requestData('/chat/fund/trend', method: 'GET'));

  Future<WalletJournalPage> fetchJournals(WalletJournalQuery query) async {
    final data = await _api.requestData('/chat/fund/journals',
        method: 'GET', queryParameters: query.toQueryParameters());
    return WalletJournalPage.fromJson(data);
  }

  Future<List<FundBalance>> fetchBalances() async =>
      (await fetchBalanceSnapshot()).balances;

  Future<WalletBalanceSnapshot> fetchBalanceSnapshot() async {
    final data = await _api.requestData('/chat/fund/balances', method: 'GET');
    final values = data['balances'];
    if (values is! List) throw const FormatException('Invalid wallet balances');
    final balances = values.map((value) {
      if (value is! Map) throw const FormatException('Invalid wallet balance');
      return FundBalance.fromJson(Map<String, dynamic>.from(value),
          allowNegativeAvailable: true);
    }).toList(growable: false);
    if (balances.length != FundCurrency.values.length ||
        balances.map((balance) => balance.currency).toSet().length !=
            FundCurrency.values.length) {
      throw const FormatException('Incomplete wallet balances');
    }
    final daily = data['dailyChange'];
    final ready = daily is Map && daily['status'] == 'ready';
    final valuesCny = <FundCurrency, String>{};
    final changesCny = <FundCurrency, String>{};
    final percentages = <FundCurrency, String>{};
    for (final value in values) {
      final currency = FundCurrency.parse(value['currency'] as String);
      valuesCny[currency] =
          walletServerDecimal(value['valueCny'] ?? value['availableCny']);
      changesCny[currency] = walletServerDecimal(value['changeAmountCny']);
      percentages[currency] = walletServerDecimal(value['changePercent']);
    }
    final rate = data['usdToThisRate'];
    final updatedAt = data['usdToThisRateUpdatedAt'];
    return WalletBalanceSnapshot(
      balances: List.unmodifiable(balances),
      totalCny: walletServerDecimal(data["totalCny"]),
      dailyAmountCny: ready ? walletServerDecimal(daily["amountCny"]) : "--",
      dailyPercentage: ready ? walletServerDecimal(daily["percentage"]) : "--",
      valuesCny: Map.unmodifiable(valuesCny),
      changesCny: Map.unmodifiable(changesCny),
      changePercentages: Map.unmodifiable(percentages),
      usdToThisRate: rate is num && rate.isFinite && rate > 0 ? rate : null,
      usdToThisRateUpdatedAt: updatedAt is int ? updatedAt : null,
    );
  }

  Future<WalletDepositAddress> fetchDepositAddress() async =>
      WalletDepositAddress.fromJson(
          await _api.requestData('/chat/fund/deposit-address', method: 'GET'));

  Future<List<WalletDepositRecord>> fetchDeposits() async {
    final data = await _api.requestData('/chat/fund/deposits', method: 'GET');
    final values = data['deposits'];
    if (values is! List) {
      throw const FormatException('Invalid wallet deposits');
    }
    final occurrences = <String, int>{};
    final records = <WalletDepositRecord>[];
    for (final value in values) {
      if (value is! Map) {
        throw const FormatException('Invalid wallet deposit');
      }
      final json = Map<String, dynamic>.from(value);
      final txID = json['tx_id'];
      if (txID is! String || txID.trim().isEmpty) {
        throw const FormatException('Missing deposit transaction ID');
      }
      final key = txID.trim();
      final index = occurrences[key] ?? 0;
      occurrences[key] = index + 1;
      records.add(WalletDepositRecord.fromJson(json, occurrenceIndex: index));
    }
    return List.unmodifiable(records);
  }

  Future<WalletFundOrder> getOrder(String orderID) async {
    _requiredValue(orderID, '订单号');
    final data = await _api.requestData(
        '/chat/fund/orders/${Uri.encodeComponent(orderID)}',
        method: 'GET');
    final order = _parseOrder(data);
    if (order.orderID != orderID) {
      throw const FormatException('Wallet order ID does not match');
    }
    return order;
  }

  Future<WalletFundOrder> getOrderByClient(String clientOrderID) async {
    _validateSwapClientID(clientOrderID);
    final data = await _api.requestData('/chat/fund/orders/by-client',
        method: 'GET', queryParameters: {'clientOrderID': clientOrderID});
    final order = _parseOrder(data);
    if (order.clientOrderID != clientOrderID) {
      throw const FormatException('Wallet client order ID does not match');
    }
    return order;
  }

  Future<WalletSwapQuote> fetchSwapQuote({
    required FundAmount amount,
    required FundCurrency toCurrency,
  }) async {
    _validateSwapAmount(amount, toCurrency);
    final quote = WalletSwapQuote.fromJson(
        await _api.requestData('/chat/fund/swap-quotes', data: {
      'fromCurrency': amount.currency.code,
      'toCurrency': toCurrency.code,
      'amount': amount.decimal,
    }));
    if (!quote.matches(amount, toCurrency)) {
      throw const FormatException('Swap quote does not match the request');
    }
    return quote;
  }

  Future<WalletWithdrawResult> withdraw({
    required String clientOrderID,
    required FundAmount amount,
    required String toAddress,
    required String payPassword,
    String? verifyChallengeID,
    String? verifyCode,
  }) async {
    _validateWrite(clientOrderID, amount, payPassword);
    _requiredValue(toAddress, '提现地址');
    if (amount.currency == FundCurrency.bi99) {
      throw const FormatException('该币种不支持链上提现');
    }
    if ((verifyChallengeID == null) != (verifyCode == null) ||
        (verifyChallengeID != null &&
            (verifyChallengeID.trim().isEmpty ||
                !RegExp(r'^\d{6}$').hasMatch(verifyCode!)))) {
      throw const FormatException('请输入本次提现的有效短信验证码');
    }
    final Map<String, dynamic> data;
    try {
      data = await _api
          .requestData('/chat/fund/withdrawals', mutation: true, data: {
        'clientOrderID': clientOrderID,
        'mode': 'chain',
        'network': 'TRON',
        'currency': amount.currency.code,
        'amount': amount.decimal,
        'toAddress': toAddress,
        'payPassword': payPassword,
        if (verifyChallengeID != null) 'verifyChallengeID': verifyChallengeID,
        if (verifyCode != null) 'verifyCode': verifyCode,
      });
    } on FundApiException catch (error) {
      // A service failure or business-ID conflict cannot disprove an earlier
      // acceptance of this draft. Recover the original ID before a new write.
      if (const {500, 503, 20062}.contains(error.code) && !error.isUncertain) {
        throw FundApiException(error.code, error.message,
            isUncertain: true, orderID: error.orderID);
      }
      rethrow;
    }
    try {
      final order = _parseOrder(data);
      _confirmOrder(order, clientOrderID, amount, 'withdraw');
      final fee = walletFundDecimal(data['fee'], amount.currency);
      if ((order.scene.isNotEmpty && order.scene != 'chain') ||
          (order.network.isNotEmpty && order.network != 'TRON') ||
          order.toAddress != toAddress ||
          (order.fee != null &&
              FundAmount.parse(order.fee!, amount.currency) !=
                  FundAmount.parse(fee, amount.currency))) {
        throw const FormatException('Withdrawal response does not match');
      }
      return WalletWithdrawResult(order: order, fee: fee);
    } catch (_) {
      throw FundApiException(-1, '提现结果尚未确认',
          isUncertain: true, orderID: _responseOrderID(data));
    }
  }

  Future<WalletSwapResult> swap({
    required String clientOrderID,
    required FundAmount amount,
    required FundCurrency toCurrency,
    required String payPassword,
    String? quoteID,
  }) async {
    _validateWrite(clientOrderID, amount, payPassword);
    _validateSwapClientID(clientOrderID);
    _validateSwapAmount(amount, toCurrency);
    if (quoteID != null) {
      _requiredValue(quoteID, '报价编号');
      if (RegExp(r'\s').hasMatch(quoteID)) {
        throw const FormatException('报价编号不能包含空格');
      }
    }
    Map<String, dynamic> data;
    try {
      data = await _api.requestData('/chat/fund/swaps', mutation: true, data: {
        'clientOrderID': clientOrderID,
        'fromCurrency': amount.currency.code,
        'toCurrency': toCurrency.code,
        'amount': amount.decimal,
        'payPassword': payPassword,
        if (quoteID != null) 'quoteID': quoteID,
      });
    } on FundApiException catch (error) {
      // These responses cannot prove this client's original swap did not settle.
      // Keep this classification local to swaps; existing fund writes are unchanged.
      if (const {500, 503, 20062, 20073}.contains(error.code) &&
          !error.isUncertain) {
        throw FundApiException(error.code, error.message,
            isUncertain: true, orderID: error.orderID);
      }
      rethrow;
    }
    try {
      final order = _parseOrder(data);
      _confirmOrder(order, clientOrderID, amount, 'swap');
      final received =
          walletFundDecimal(data['received'], toCurrency, positive: true);
      if ((order.targetCurrency != null &&
              order.targetCurrency != toCurrency) ||
          (quoteID != null && order.quoteID != quoteID) ||
          (order.targetAmount != null &&
              FundAmount.parse(order.targetAmount!, toCurrency) !=
                  FundAmount.parse(received, toCurrency))) {
        throw const FormatException('Swap response does not match');
      }
      return WalletSwapResult(order: order, received: received);
    } catch (_) {
      throw FundApiException(-1, '兑换结果尚未确认',
          isUncertain: true, orderID: _responseOrderID(data));
    }
  }

  static String? _responseOrderID(Map<String, dynamic> data) {
    final order = data['order'];
    final raw = order is Map ? order['orderID'] : null;
    if (raw is! String) return null;
    final id = raw.trim();
    return id.isEmpty || RegExp(r'\s').hasMatch(id) ? null : id;
  }

  static WalletFundOrder _parseOrder(Map<String, dynamic> data) {
    final json = data['order'];
    if (json is! Map) throw const FormatException('Invalid wallet order');
    return WalletFundOrder.fromJson(Map<String, dynamic>.from(json));
  }

  static void _confirmOrder(WalletFundOrder order, String clientOrderID,
      FundAmount amount, String biz) {
    if (order.biz != biz ||
        order.currency != amount.currency ||
        FundAmount.parse(order.amount, order.currency) != amount ||
        (order.clientOrderID.isNotEmpty &&
            order.clientOrderID != clientOrderID)) {
      throw const FormatException('Wallet order does not match the request');
    }
  }

  static void _validateWrite(
      String clientOrderID, FundAmount amount, String payPassword) {
    _requiredValue(clientOrderID, '业务单号');
    if (!RegExp(r'^\d{6}$').hasMatch(payPassword)) {
      throw const FormatException('支付密码须为 6 位数字');
    }
    if (!amount.isPositive) throw const FormatException('金额必须大于 0');
    if (amount.units > BigInt.parse('9223372036854775807')) {
      throw const FormatException('金额超出支持范围');
    }
  }

  static void _validateSwapAmount(FundAmount amount, FundCurrency target) {
    if (amount.currency == target) {
      throw const FormatException('请选择不同的兑换币种');
    }
    if (!amount.isPositive) throw const FormatException('金额必须大于 0');
    if (amount.units > BigInt.parse('9223372036854775807')) {
      throw const FormatException('金额超出支持范围');
    }
  }

  static void _validateSwapClientID(String clientOrderID) {
    _requiredValue(clientOrderID, '业务单号');
    if (clientOrderID.length > 128) {
      throw const FormatException('业务单号最多 128 个字符');
    }
  }

  static void _requiredValue(String value, String label) {
    if (value.trim().isEmpty || value.trim() != value) {
      throw FormatException('$label不能为空或包含首尾空格');
    }
  }
}

/// Wallet-safe user messages without changing already integrated fund pages.
String walletFundErrorMessage(Object error) {
  if (error is FormatException) {
    return RegExp(r'[\u3400-\u9FFF]').hasMatch(error.message)
        ? error.message
        : '资金数据异常，请稍后重试';
  }
  if (error is FundApiException && !error.isUncertain) {
    switch (error.code) {
      case 401:
        return '登录状态已失效，请重新登录';
      case 500:
      case 503:
        return '资金服务暂时不可用，请稍后重试';
      case 20027:
        return '金额低于最低要求或超过限额';
      case 20030:
        return '报价或链服务暂不可用，请稍后重试';
    }
  }
  return fundErrorMessage(error, chinese: true);
}
