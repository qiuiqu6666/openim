import 'dart:convert';

import 'host/wallet_i18n.dart';

/// 钱包双币种金额换算（与后端 wallet.md / 对接文档一致）。
class WalletCurrency {
  WalletCurrency._();

  static const String usdt = 'USDT';
  static const String platform = '99';

  static const int usdtScale = 6;
  static const int platformScale = 2;
}

bool isWalletPlatformCurrency(String currency) {
  return currency.trim() == WalletCurrency.platform;
}

bool _looksLikePlatformCoinLabel(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  if (isWalletPlatformCurrency(text)) return true;
  final upper = text.toUpperCase();
  return text == '元' ||
      upper == 'CNY' ||
      upper == 'C' ||
      upper == '99币' ||
      upper == '99幣';
}

/// 转账详情页币种代码：首帧就用 `99` / `USDT`，避免展示名「元」再被接口 code 替换而闪烁。
String walletDetailCoinCode({
  String? currency,
  String coin = '',
}) {
  final cur = currency?.trim() ?? '';
  if (_looksLikePlatformCoinLabel(cur)) {
    return WalletCurrency.platform;
  }
  if (cur.isNotEmpty) {
    return cur.toUpperCase();
  }
  final text = coin.trim();
  if (_looksLikePlatformCoinLabel(text)) {
    return WalletCurrency.platform;
  }
  return text.toUpperCase();
}

String walletDisplayCoin(String currency) {
  if (isWalletPlatformCurrency(currency)) {
    return AppI18n.current.t(
      zhHans: '元',
      zhHant: '元',
      en: 'CNY',
      ja: '元',
      ko: 'CNY',
    );
  }
  return currency.toUpperCase();
}

String formatUsdtMicro(int micro) {
  return _trimTrailingZeros((micro / 1000000).toStringAsFixed(6));
}

/// USDT 余额展示：固定两位小数（资产列表等）。
String formatUsdtBalanceDisplay(String amountDisplay) {
  final amount = double.tryParse(amountDisplay.trim()) ?? 0;
  return amount.toStringAsFixed(2);
}

String formatPlatformFen(int fen) {
  return (fen / 100).toStringAsFixed(2);
}

String formatCnyFen(int fen) => '¥${formatPlatformFen(fen)}';

/// `GET /wallet/me` → `usdtPrice` 报价块。
class WalletUsdtPrice {
  const WalletUsdtPrice({
    required this.cnyPerUsdt,
    this.cnyPerUsdtBuy = 0,
    this.cnyPerUsdtSell = 0,
    this.quoteCurrency = 'CNY',
    this.updatedAt = '',
  });

  final double cnyPerUsdt;
  final double cnyPerUsdtBuy;
  final double cnyPerUsdtSell;
  final String quoteCurrency;
  final String updatedAt;

  static WalletUsdtPrice? parse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final mid = _asDouble(map['cnyPerUsdt'] ?? map['cny_per_usdt']);
    final buy = _asDouble(
      map['cnyPerUsdtBuy'] ?? map['cny_per_usdt_buy'],
    );
    final sell = _asDouble(
      map['cnyPerUsdtSell'] ?? map['cny_per_usdt_sell'],
    );
    // 中间价用于资产参考；互兑可仅有买卖价。三者皆无则视为不可用。
    if (mid <= 0 && buy <= 0 && sell <= 0) return null;
    return WalletUsdtPrice(
      cnyPerUsdt: mid > 0
          ? mid
          : (buy > 0 && sell > 0 ? (buy + sell) / 2 : (buy > 0 ? buy : sell)),
      cnyPerUsdtBuy: buy,
      cnyPerUsdtSell: sell,
      quoteCurrency: map['quoteCurrency']?.toString() ??
          map['quote_currency']?.toString() ??
          'CNY',
      updatedAt:
          map['updatedAt']?.toString() ?? map['updated_at']?.toString() ?? '',
    );
  }

  WalletExchangeRate toMidRate() => WalletExchangeRate(usdCny: cnyPerUsdt);

  /// USDT→99：用户卖出 USDT，用买入价。
  WalletExchangeRate? toBuyRate() =>
      cnyPerUsdtBuy > 0 ? WalletExchangeRate(usdCny: cnyPerUsdtBuy) : null;

  /// 99→USDT：用户买入 USDT，用卖出价。
  WalletExchangeRate? toSellRate() =>
      cnyPerUsdtSell > 0 ? WalletExchangeRate(usdCny: cnyPerUsdtSell) : null;

  /// 闪兑成交预估专用：勿用中间价，勿再叠 markup/float。
  double? dealCnyPerUsdt({required bool usdtToPlatform}) {
    if (usdtToPlatform) {
      return cnyPerUsdtBuy > 0 ? cnyPerUsdtBuy : null;
    }
    return cnyPerUsdtSell > 0 ? cnyPerUsdtSell : null;
  }

  static double _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}

String formatCnyYuan(double yuan, {int fractionDigits = 4}) {
  if (yuan <= 0) return '--';
  var s = yuan.toStringAsFixed(fractionDigits);
  if (s.contains('.')) {
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
  }
  return '¥$s';
}

/// 互兑汇率（`GET /wallet/me` 的 exchangeRate / rateSnapshot 等）。
class WalletExchangeRate {
  const WalletExchangeRate({
    required this.usdCny,
    this.markupBps = 0,
    this.floatBps = 0,
  });

  final double usdCny;
  final int markupBps;
  final int floatBps;

  static WalletExchangeRate? parse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final usdCny = _asDouble(
      map['usdCny'] ??
          map['usd_cny'] ??
          map['usdtCny'] ??
          map['usdt_cny'] ??
          map['cnyPerUsdt'] ??
          map['cny_per_usdt'] ??
          map['usdtPrice'] ??
          map['usdt_price'] ??
          map['price'] ??
          map['rate'],
    );
    if (usdCny <= 0) return null;
    return WalletExchangeRate(
      usdCny: usdCny,
      markupBps: _asInt(map['markupBps'] ?? map['markup_bps']),
      floatBps: _asInt(map['floatBps'] ?? map['float_bps']),
    );
  }

  static WalletExchangeRate? parseFromWalletJson(Map<String, dynamic> json) {
    final usdtPrice = WalletUsdtPrice.parse(
      json['usdtPrice'] ?? json['usdt_price'],
    );
    if (usdtPrice != null) {
      return usdtPrice.toMidRate();
    }

    for (final key in const [
      'exchangeRate',
      'exchange_rate',
      'rate',
      'exchange',
      'usdtRate',
      'usdt_rate',
    ]) {
      final parsed = parse(json[key]);
      if (parsed != null) return parsed;
    }

    for (final key in const ['rates', 'exchangeRates', 'exchange_rates']) {
      final bucket = json[key];
      if (bucket is! Map) continue;
      final map = Map<String, dynamic>.from(bucket);
      final parsed = parse(
        map['USDT'] ?? map['usdt'] ?? map['Usdt'],
      );
      if (parsed != null) return parsed;
    }

    final snapshot = json['rateSnapshot'] ?? json['rate_snapshot'];
    if (snapshot is String && snapshot.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(snapshot);
        final parsed = parse(decoded);
        if (parsed != null) return parsed;
      } catch (_) {}
    }
    if (snapshot is Map) {
      final parsed = parse(snapshot);
      if (parsed != null) return parsed;
    }

    final unitFen = _asInt(
      json['usdtUnitPriceFen'] ?? json['usdt_unit_price_fen'],
    );
    if (unitFen > 0) {
      return WalletExchangeRate(usdCny: unitFen / 100.0);
    }

    return parse(json);
  }

  double get effectiveCnyPerUsdt {
    if (usdCny <= 0) return 0;
    final factor =
        (1 + markupBps / 10000.0) * (1 + floatBps / 10000.0);
    return usdCny * factor;
  }

  /// USDT micro → 平台币分（折合人民币），与互兑一致向下取整。
  int usdtMicroToPlatformFen(int usdtMicro) {
    if (usdtMicro <= 0 || usdCny <= 0) return 0;
    final usdt = usdtMicro / 1000000.0;
    return (usdt * effectiveCnyPerUsdt * 100).floor();
  }

  static double _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

/// 币种列表副标题：折合人民币单价（1 枚）。
String formatCoinUnitPriceCny({
  required bool isPlatform,
  WalletExchangeRate? rate,
  int serverUnitPriceFen = 0,
}) {
  if (serverUnitPriceFen > 0) {
    return formatCnyFen(serverUnitPriceFen);
  }
  if (isPlatform) {
    return '¥1.00';
  }
  final yuan = rate?.effectiveCnyPerUsdt ?? 0;
  return formatCnyYuan(yuan);
}

/// 将 USDT 余额按汇率折算为人民币分。
int walletUsdtCnyFen({
  required int usdtMicro,
  WalletExchangeRate? rate,
  int serverUsdtCnyFen = 0,
}) {
  if (serverUsdtCnyFen > 0) return serverUsdtCnyFen;
  if (rate == null) return 0;
  return rate.usdtMicroToPlatformFen(usdtMicro);
}

String formatWalletAmount(String currency, int amount) {
  if (isWalletPlatformCurrency(currency)) {
    return formatPlatformFen(amount);
  }
  // Wallet-facing USDT amounts use two decimal places consistently.
  return (amount / 1000000).toStringAsFixed(2);
}

int walletAmountScale(String currency) {
  return isWalletPlatformCurrency(currency)
      ? WalletCurrency.platformScale
      : WalletCurrency.usdtScale;
}

String _trimTrailingZeros(String raw) {
  if (!raw.contains('.')) return raw;
  var s = raw;
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}
