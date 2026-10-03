import 'host/wallet_i18n.dart';

import 'wallet_amount.dart';

class WalletMe {
  WalletMe({
    required this.depositAddress,
    required this.usdtContract,
    required this.minDepositUsdt,
    required this.usdtMicro,
    required this.platformFen,
    required this.payPinSet,
    this.exchangeRate,
    this.usdtCnyFen = 0,
    this.totalAssetsFen = 0,
    this.usdtUnitPriceFen = 0,
    this.platformUnitPriceFen = 0,
    this.usdtPrice,
    this.platformCurrency = '',
  });

  final String depositAddress;
  final String usdtContract;
  final String minDepositUsdt;
  final int usdtMicro;
  final int platformFen;
  final bool payPinSet;
  final WalletExchangeRate? exchangeRate;
  /// 服务端已折算的 USDT→人民币分（若有则优先使用）。
  final int usdtCnyFen;
  /// 服务端总资产（分），若有则优先用于首页总资产。
  final int totalAssetsFen;
  /// 服务端 USDT 单价（分/枚），若有则优先展示。
  final int usdtUnitPriceFen;
  /// 服务端平台币单价（分/枚），若有则优先展示。
  final int platformUnitPriceFen;
  final WalletUsdtPrice? usdtPrice;
  /// 平台币币种代码（如 `99`），用于展示名称，不是余额。
  final String platformCurrency;

  /// 合并顶层与 `wallet` 子对象，避免汇率、余额落在嵌套外被丢弃。
  static Map<String, dynamic> mergeWalletPayload(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    final wallet = json['wallet'];
    if (wallet is Map) {
      out.remove('wallet');
      out.addAll(Map<String, dynamic>.from(wallet));
    }
    return out;
  }

  factory WalletMe.fromJson(Map<String, dynamic> json) {
    final payload = mergeWalletPayload(json);
    final balances = payload['balances'];
    final balMap = balances is Map
        ? Map<String, dynamic>.from(balances)
        : <String, dynamic>{};

    return WalletMe(
      depositAddress: readDepositAddress(payload),
      usdtContract: _readString(payload, const [
        'usdtContract',
        'usdt_contract',
      ]),
      minDepositUsdt: _readString(payload, const [
        'minDepositUsdt',
        'min_deposit_usdt',
      ], fallback: '1'),
      usdtMicro: _readUsdtMicro(balMap, payload),
      platformFen: _readPlatformFen(balMap, payload),
      payPinSet: payload['payPinSet'] as bool? ??
          payload['pay_pin_set'] as bool? ??
          false,
      usdtPrice: WalletUsdtPrice.parse(
        payload['usdtPrice'] ?? payload['usdt_price'],
      ),
      platformCurrency: payload['platformCurrency']?.toString() ??
          payload['platform_currency']?.toString() ??
          '',
      exchangeRate: WalletExchangeRate.parseFromWalletJson(payload),
      usdtCnyFen: _asInt(
        balMap['usdtCnyFen'] ??
            balMap['usdt_cny_fen'] ??
            balMap['usdtValueFen'] ??
            balMap['usdt_value_fen'] ??
            balMap['usdtPlatformFen'] ??
            payload['usdtCnyFen'] ??
            payload['usdt_cny_fen'],
      ),
      totalAssetsFen: _asInt(
        payload['totalAssetsFen'] ??
            payload['total_assets_fen'] ??
            payload['totalBalanceFen'] ??
            payload['total_balance_fen'] ??
            payload['totalCnyFen'] ??
            payload['total_cny_fen'] ??
            balMap['totalAssetsFen'] ??
            balMap['total_assets_fen'],
      ),
      usdtUnitPriceFen: _readUsdtUnitPriceFen(balMap, payload),
      platformUnitPriceFen: _asInt(
        balMap['platformUnitPriceFen'] ??
            balMap['platform_unit_price_fen'] ??
            payload['platformUnitPriceFen'] ??
            payload['platform_unit_price_fen'],
      ),
    );
  }

  static int _readUsdtUnitPriceFen(
    Map<String, dynamic> balMap,
    Map<String, dynamic> payload,
  ) {
    final fen = _asInt(
      balMap['usdtUnitPriceFen'] ??
          balMap['usdt_unit_price_fen'] ??
          payload['usdtUnitPriceFen'] ??
          payload['usdt_unit_price_fen'],
    );
    if (fen > 0) return fen;

    final usdtPrice = WalletUsdtPrice.parse(
      payload['usdtPrice'] ?? payload['usdt_price'],
    );
    if (usdtPrice != null && usdtPrice.cnyPerUsdt > 0) {
      return (usdtPrice.cnyPerUsdt * 100).round();
    }

    final yuan = _asDouble(
      balMap['usdtUnitPrice'] ??
          balMap['usdt_unit_price'] ??
          balMap['usdtCny'] ??
          balMap['usdt_cny'] ??
          payload['usdtUnitPrice'] ??
          payload['usdt_unit_price'] ??
          payload['usdtCny'] ??
          payload['usdt_cny'],
    );
    if (yuan > 0) return (yuan * 100).round();
    return 0;
  }

  static String platformDisplayName(String platformCurrency) {
    final code = platformCurrency.trim();
    if (code.isEmpty) {
      return AppI18n.current.t(
        zhHans: '平台币',
        zhHant: '平台幣',
        en: 'Platform coin',
        ja: 'プラットフォーム通貨',
        ko: '플랫폼 코인',
      );
    }
    return code;
  }

  static double _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// 兼容 v1.0 `depositAddress` 与历史字段 `trxAddr` 等。
  static String readDepositAddress(Map<String, dynamic> json) {
    for (final key in const [
      'depositAddress',
      'deposit_address',
      'trxAddr',
      'trx_addr',
      'trxAddress',
      'address',
    ]) {
      final v = json[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    final wallet = json['wallet'];
    if (wallet is Map) {
      return readDepositAddress(Map<String, dynamic>.from(wallet));
    }
    return '';
  }

  static String _readString(
    Map<String, dynamic> json,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final v = json[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// 平台币余额（分）。
  static int _readPlatformFen(
    Map<String, dynamic> balMap,
    Map<String, dynamic> root,
  ) {
    if (balMap.containsKey('platformFen') ||
        balMap.containsKey('platform_fen') ||
        root.containsKey('platformFen') ||
        root.containsKey('platform_fen')) {
      return _asInt(
        balMap['platformFen'] ??
            balMap['platform_fen'] ??
            root['platformFen'] ??
            root['platform_fen'],
      );
    }

    final fromKeys = _asInt(
      balMap['platformAmount'] ??
          balMap['platform_amount'] ??
          balMap['amountFen'] ??
          balMap['amount_fen'] ??
          root['platformAmount'] ??
          root['platform_amount'],
    );
    if (fromKeys > 0) return fromKeys;

    final platformCode = root['platformCurrency']?.toString().trim() ?? '';
    if (platformCode.isNotEmpty) {
      final fromCode = _asInt(balMap[platformCode] ?? root[platformCode]);
      if (fromCode > 0) return fromCode;
    }

    final fromCurrency = _amountFromCurrencyMap(balMap, const ['99']);
    if (fromCurrency > 0) return fromCurrency;

    return _amountFromBalanceList(
      balMap['items'] ?? balMap['list'] ?? root['balances'] ?? root['balanceList'],
      const ['99'],
    );
  }

  static int _readUsdtMicro(
    Map<String, dynamic> balMap,
    Map<String, dynamic> root,
  ) {
    final fromKeys = _asInt(
      balMap['usdtMicro'] ??
          balMap['usdt_micro'] ??
          balMap['usdtAmount'] ??
          balMap['usdt_amount'] ??
          root['usdtMicro'] ??
          root['usdt_micro'],
    );
    if (fromKeys > 0) return fromKeys;

    final fromCurrency = _amountFromCurrencyMap(
      balMap,
      const ['USDT', 'usdt'],
    );
    if (fromCurrency > 0) return fromCurrency;

    return _amountFromBalanceList(
      balMap['items'] ?? balMap['list'] ?? root['balances'] ?? root['balanceList'],
      const ['USDT', 'usdt'],
    );
  }

  static int _amountFromCurrencyMap(
    Map<String, dynamic> map,
    List<String> currencies,
  ) {
    for (final key in currencies) {
      final raw = map[key];
      final amount = _amountFromDynamic(raw);
      if (amount > 0) return amount;
    }
    return 0;
  }

  static int _amountFromBalanceList(dynamic raw, List<String> currencies) {
    if (raw is! List) return 0;
    for (final item in raw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final currency = row['currency']?.toString().toUpperCase() ?? '';
      final name = row['name']?.toString() ?? '';
      final matched = currencies.any(
        (c) =>
            currency == c.toUpperCase() ||
            name == c ||
            name.contains(c),
      );
      if (!matched) continue;
      final amount = _amountFromDynamic(row);
      if (amount > 0) return amount;
    }
    return 0;
  }

  static int _amountFromDynamic(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is! Map) return 0;
    final map = Map<String, dynamic>.from(raw);
    return _asInt(
      map['platformFen'] ??
          map['platform_fen'] ??
          map['amountFen'] ??
          map['amount_fen'] ??
          map['amount'] ??
          map['balance'] ??
          map['available'] ??
          map['usdtMicro'] ??
          map['usdt_micro'],
    );
  }
}

/// `GET /wallet/currencies` 单条币种资产。
class WalletCurrencyItem {
  WalletCurrencyItem({
    required this.code,
    required this.name,
    required this.logoUrl,
    required this.price,
    required this.priceCurrency,
    required this.amount,
    required this.amountUnit,
    required this.decimals,
    required this.amountDisplay,
    required this.availableAmount,
    required this.frozenAmount,
    required this.depositEnabled,
    required this.withdrawEnabled,
    required this.platformCoin,
    required this.sortOrder,
    this.priceChangePercent,
  });

  final String code;
  final String name;
  final String logoUrl;
  final double? price;
  final String priceCurrency;
  final int amount;
  final String amountUnit;
  final int decimals;
  final String amountDisplay;
  final int availableAmount;
  final int frozenAmount;
  final bool depositEnabled;
  final bool withdrawEnabled;
  final bool platformCoin;
  final int sortOrder;
  /// 24h 涨跌幅百分比数值（如 `0.12`）；接口未返回时为 null。
  final double? priceChangePercent;

  factory WalletCurrencyItem.fromJson(Map<String, dynamic> json) {
    return WalletCurrencyItem(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      logoUrl: json['logoUrl']?.toString() ??
          json['logo_url']?.toString() ??
          '',
      price: _readNullableDouble(json['price']),
      priceCurrency: json['priceCurrency']?.toString() ??
          json['price_currency']?.toString() ??
          'CNY',
      amount: _asInt(json['amount']),
      amountUnit: json['amountUnit']?.toString() ??
          json['amount_unit']?.toString() ??
          '',
      decimals: _asInt(json['decimals']),
      amountDisplay: json['amountDisplay']?.toString() ??
          json['amount_display']?.toString() ??
          '0',
      availableAmount: _asInt(
        json['availableAmount'] ?? json['available_amount'],
      ),
      frozenAmount: _asInt(json['frozenAmount'] ?? json['frozen_amount']),
      depositEnabled: json['depositEnabled'] as bool? ??
          json['deposit_enabled'] as bool? ??
          true,
      withdrawEnabled: json['withdrawEnabled'] as bool? ??
          json['withdraw_enabled'] as bool? ??
          true,
      platformCoin: json['platformCoin'] as bool? ??
          json['platform_coin'] as bool? ??
          false,
      sortOrder: _asInt(json['sortOrder'] ?? json['sort_order']),
      priceChangePercent: _readNullableDouble(
        json['priceChangePercent'] ??
            json['price_change_percent'] ??
            json['changePercent'] ??
            json['change_percent'] ??
            json['change24h'] ??
            json['change_24h'],
      ),
    );
  }

  static double? _readNullableDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

/// `GET /wallet/currencies` 响应。
class WalletCurrenciesResponse {
  WalletCurrenciesResponse({
    required this.currencies,
    this.priceUpdatedAt,
  });

  final List<WalletCurrencyItem> currencies;
  final DateTime? priceUpdatedAt;

  factory WalletCurrenciesResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['currencies'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map(
              (e) => WalletCurrencyItem.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList()
        : <WalletCurrencyItem>[];
    items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final updatedRaw =
        json['priceUpdatedAt'] ?? json['price_updated_at'];
    DateTime? updatedAt;
    if (updatedRaw != null) {
      updatedAt = DateTime.tryParse(updatedRaw.toString());
    }
    return WalletCurrenciesResponse(
      currencies: items,
      priceUpdatedAt: updatedAt,
    );
  }
}

class WalletRegisterWalletInfo {
  WalletRegisterWalletInfo({
    required this.depositAddress,
    required this.usdtContract,
    required this.minDepositUsdt,
  });

  final String depositAddress;
  final String usdtContract;
  final String minDepositUsdt;

  factory WalletRegisterWalletInfo.fromJson(Map<String, dynamic> json) {
    final payload = WalletMe.mergeWalletPayload(json);
    return WalletRegisterWalletInfo(
      depositAddress: WalletMe.readDepositAddress(payload),
      usdtContract: WalletMe._readString(payload, const [
        'usdtContract',
        'usdt_contract',
      ]),
      minDepositUsdt: WalletMe._readString(payload, const [
        'minDepositUsdt',
        'min_deposit_usdt',
      ], fallback: '1'),
    );
  }
}
