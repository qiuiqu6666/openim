import '../../../services/fund_models.dart';
import 'currency_rules/wallet_currency_rule.dart';

export 'currency_rules/wallet_currency_rule.dart';

/// The server allocates one TRON address shared by supported deposit currencies.
class WalletDepositAddress {
  WalletDepositAddress({
    required this.status,
    required this.network,
    required this.address,
    required List<FundCurrency> currencies,
    required this.confirmations,
    required this.usdtContract,
    Map<FundCurrency, WalletCurrencyRule> currencyRules = const {},
  })  : currencies = List.unmodifiable(currencies),
        currencyRules = _freezeCurrencyRules(currencyRules);

  factory WalletDepositAddress.fromJson(Map<String, dynamic> json) {
    final status = _requiredString(json, 'status');
    if (status != 'ready' && status != 'pending') {
      throw const FormatException('Invalid deposit address status');
    }
    final network = _requiredString(json, 'network');
    if (network != 'TRON') {
      throw const FormatException('Unsupported deposit network');
    }
    final rawCurrencies = json['currencies'];
    if (rawCurrencies is! List || rawCurrencies.isEmpty) {
      throw const FormatException('Missing deposit currencies');
    }
    final currencies = rawCurrencies.map((value) {
      if (value is! String) {
        throw const FormatException('Invalid deposit currency');
      }
      final currency = FundCurrency.parse(value);
      if (currency == FundCurrency.bi99) {
        throw const FormatException('Unsupported deposit currency');
      }
      return currency;
    }).toList(growable: false);
    if (currencies.toSet().length != currencies.length) {
      throw const FormatException('Duplicate deposit currency');
    }
    final address = _string(json, 'address');
    if (status == 'ready' && address.isEmpty) {
      throw const FormatException('Missing ready deposit address');
    }
    final contract = _string(json, 'usdtContract');
    if (currencies.contains(FundCurrency.usdt) && contract.isEmpty) {
      throw const FormatException('Missing USDT contract');
    }
    return WalletDepositAddress(
      status: status,
      network: network,
      address: address,
      currencies: currencies,
      confirmations: _nonNegativeInt(json['confirmations'], 'confirmations'),
      usdtContract: contract,
      currencyRules: _parseCurrencyRules(json['currencyRules']),
    );
  }

  final String status;
  final String network;
  final String address;
  final List<FundCurrency> currencies;
  final int confirmations;
  final String usdtContract;
  final Map<FundCurrency, WalletCurrencyRule> currencyRules;
  bool get isReady => status == 'ready';

  WalletCurrencyRule? ruleFor(FundCurrency currency) => currencyRules[currency];
}

Map<FundCurrency, WalletCurrencyRule> _freezeCurrencyRules(
    Map<FundCurrency, WalletCurrencyRule> rules) {
  for (final entry in rules.entries) {
    if (entry.key != entry.value.currency) {
      throw const FormatException('Currency rule does not match map key');
    }
  }
  return Map.unmodifiable(rules);
}

Map<FundCurrency, WalletCurrencyRule> _parseCurrencyRules(dynamic value) {
  if (value == null) return const {};
  if (value is! Map) throw const FormatException('Invalid currency rules');
  final rules = <FundCurrency, WalletCurrencyRule>{};
  for (final entry in value.entries) {
    final code = entry.key;
    if (code is! String) throw const FormatException('Invalid rule currency');
    final currency = FundCurrency.parse(code);
    final rawRule = entry.value;
    if (rawRule == null) continue;
    if (rawRule is! Map || rawRule.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid currency rule');
    }
    rules[currency] = WalletCurrencyRule.fromJson(
      Map<String, dynamic>.from(rawRule),
      currency: currency,
    );
  }
  return rules;
}

/// No event ID or timestamp is supplied by the current deposit endpoint.
class WalletDepositRecord {
  const WalletDepositRecord({
    required this.txID,
    required this.currency,
    required this.amount,
    required this.address,
    required this.height,
    required this.status,
    required this.occurrenceIndex,
    this.confirmations,
  });

  factory WalletDepositRecord.fromJson(
    Map<String, dynamic> json, {
    required int occurrenceIndex,
  }) {
    final currency = FundCurrency.parse(_requiredString(json, 'currency'));
    if (currency == FundCurrency.bi99) {
      throw const FormatException('Unsupported deposit currency');
    }
    final status = _requiredString(json, 'status');
    if (status != 'credited' && status != 'orphaned') {
      throw const FormatException('Unsupported deposit status');
    }
    return WalletDepositRecord(
      txID: _requiredString(json, 'tx_id'),
      currency: currency,
      amount: walletFundDecimal(json['amount'], currency, positive: true),
      address: _requiredString(json, 'address'),
      height: _nonNegativeInt(json['height'], 'height'),
      status: status,
      confirmations: json['confirmations'] == null
          ? null
          : _nonNegativeInt(json['confirmations'], 'confirmations'),
      occurrenceIndex: occurrenceIndex,
    );
  }

  final String txID;
  final FundCurrency currency;
  final String amount;
  final String address;
  final int height;
  final String status;

  /// Recorded admission threshold, not a live confirmation count.
  final int? confirmations;

  /// Position among this txID's events in the returned snapshot; no deduplication.
  final int occurrenceIndex;
}

/// Wallet order fields are independent of chat packet/transfer presentation.
class WalletFundOrder {
  const WalletFundOrder({
    required this.orderID,
    required this.biz,
    required this.currency,
    required this.amount,
    required this.status,
    this.clientOrderID = '',
    this.toAddress = '',
    this.fee,
    this.targetCurrency,
    this.targetAmount,
    this.quoteID,
    this.createdAt,
    this.scene = '',
    this.senderID = '',
    this.recvID = '',
    this.network = '',
    this.chainTxID = '',
    this.fromAddress = '',
    this.remark = '',
    this.recipientType = '',
    this.recipient = '',
    this.recipientAreaCode = '',
    this.reviewedBy = '',
    this.reviewReason = '',
    this.reviewedAt,
    this.completedBy = '',
    this.completionReason = '',
    this.completedAt,
  });

  factory WalletFundOrder.fromJson(Map<String, dynamic> json) {
    final currency = FundCurrency.parse(_requiredString(json, 'currency'));
    final biz = _requiredString(json, 'biz');
    if (!const {
      'withdraw',
      'swap',
      'transfer',
      'group_transfer',
      'packet_exclusive',
      'packet_normal',
      'packet_lucky',
    }.contains(biz)) {
      throw const FormatException('Unsupported wallet order');
    }
    final status = _requiredString(json, 'status');
    final validStatus = biz == 'withdraw'
        ? const {
            'withdraw_pending',
            'withdraw_approved',
            'withdraw_done',
            'withdraw_failed'
          }
        : const {'done', 'open', 'refunded'};
    if (!validStatus.contains(status)) {
      throw const FormatException('Unsupported wallet order status');
    }
    final rawTargetCurrency = _optionalString(json, 'targetCurrency');
    final targetCurrency = rawTargetCurrency.isEmpty
        ? null
        : FundCurrency.parse(rawTargetCurrency);
    final rawTargetAmount = json['targetAmount'];
    String? targetAmount;
    if (rawTargetAmount != null && rawTargetAmount != '') {
      if (targetCurrency == null) {
        // Unused order fields may contain the server's decimal-string zero.
        if (rawTargetAmount is! String ||
            !RegExp(r'^0+(?:\.0+)?$').hasMatch(rawTargetAmount)) {
          throw const FormatException('Missing target currency');
        }
      } else {
        targetAmount = walletFundDecimal(rawTargetAmount, targetCurrency);
      }
    }
    final rawFee = json['fee'];
    final rawQuoteID = json['quoteID'];
    if (rawQuoteID != null &&
        (rawQuoteID is! String || RegExp(r'\s').hasMatch(rawQuoteID))) {
      throw const FormatException('Invalid wallet quote ID');
    }
    return WalletFundOrder(
      orderID: _requiredString(json, 'orderID'),
      clientOrderID: _optionalString(json, 'clientOrderID'),
      biz: biz,
      currency: currency,
      amount: walletFundDecimal(json['amount'], currency, positive: true),
      status: status,
      toAddress: _optionalString(json, 'toAddress'),
      fee: rawFee == null || rawFee == ''
          ? null
          : walletFundDecimal(rawFee, currency),
      targetCurrency: targetCurrency,
      targetAmount: targetAmount,
      quoteID: rawQuoteID as String?,
      createdAt: _millisecondsDate(json['createdAt']),
      scene: _optionalString(json, 'scene'),
      senderID: _optionalString(json, 'senderID'),
      recvID: _optionalString(json, 'recvID'),
      network: _optionalString(json, 'network'),
      chainTxID: _optionalString(json, 'chainTxID'),
      fromAddress: _optionalString(json, 'fromAddress'),
      remark: _optionalString(json, 'remark'),
      recipientType: _optionalString(json, 'recipientType'),
      recipient: _optionalString(json, 'recipient'),
      recipientAreaCode: _optionalString(json, 'recipientAreaCode'),
      reviewedBy: _optionalString(json, 'reviewedBy'),
      reviewReason: _optionalString(json, 'reviewReason'),
      reviewedAt: _millisecondsDate(json['reviewedAt']),
      completedBy: _optionalString(json, 'completedBy'),
      completionReason: _optionalString(json, 'completionReason'),
      completedAt: _millisecondsDate(json['completedAt']),
    );
  }

  final String orderID;
  final String clientOrderID;
  final String biz;
  final FundCurrency currency;
  final String amount;
  final String status;
  final String toAddress;
  final String? fee;
  final FundCurrency? targetCurrency;
  final String? targetAmount;
  final String? quoteID;
  final DateTime? createdAt;
  final String scene;
  final String senderID;
  final String recvID;
  final String network;
  final String chainTxID;
  final String fromAddress;
  final String remark;
  final String recipientType;
  final String recipient;
  final String recipientAreaCode;
  final String reviewedBy;
  final String reviewReason;
  final DateTime? reviewedAt;
  final String completedBy;
  final String completionReason;
  final DateTime? completedAt;
}

class WalletWithdrawResult {
  const WalletWithdrawResult({required this.order, required this.fee});
  final WalletFundOrder order;
  final String fee;
}

class WalletSwapResult {
  const WalletSwapResult({required this.order, required this.received});
  final WalletFundOrder order;
  final String received;
}

/// Validates exact wire decimals without changing their precision or formatting.
String walletFundDecimal(dynamic value, FundCurrency currency,
    {bool positive = false}) {
  if (value is! String || !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)) {
    throw const FormatException('Fund amounts must be decimal strings');
  }
  final amount = FundAmount.parse(value, currency);
  if (positive && !amount.isPositive) {
    throw const FormatException('Invalid positive wallet amount');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key');
  return value.trim();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  if (value.isEmpty) throw FormatException('Missing $key');
  return value;
}

String _optionalString(Map<String, dynamic> json, String key) =>
    json[key] == null ? '' : _string(json, key);

int _nonNegativeInt(dynamic value, String key) {
  final integer = value is int
      ? value
      : value is String && RegExp(r'^\d+$').hasMatch(value)
          ? int.tryParse(value)
          : null;
  if (integer == null || integer < 0) {
    throw FormatException('Invalid $key');
  }
  return integer;
}

DateTime? _millisecondsDate(dynamic value) {
  if (value == null || value == '' || value == 0 || value == '0') return null;
  final milliseconds = _nonNegativeInt(value, 'createdAt');
  try {
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  } on ArgumentError {
    throw const FormatException('Invalid createdAt');
  }
}
