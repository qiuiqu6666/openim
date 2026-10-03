import 'package:flutter/material.dart';

import 'wallet_amount.dart';
import 'record/wallet_record_models.dart';

/// P1 阶段只暴露首页真正需要的数据边界；后续页面按 99chat 接口逐包扩展。
abstract class WalletRepository {
  Future<WalletDto> getWallet();
  Future<List<WalletPayMethodDto>> getPayMethods();
  Future<WalletExchangeOrderDto> exchange(WalletExchangeReq req);
  Future<List<WalletExchangeOrderDto>> getExchangeRecords({int page = 0, int size = 20});
  Future<List<WalletRecordDto>> getDepositRecords();
  Future<List<WalletRecordDto>> getWithdrawRecords();
}

class WalletBackendUnavailableException implements Exception {
  const WalletBackendUnavailableException();

  @override
  String toString() => 'Wallet backend is unavailable';
}

/// 生产环境 Wallet 后端尚未接入时使用。
///
/// 不返回测试余额、测试地址、测试币种或任何伪造成功状态。
class UnavailableWalletRepository implements WalletRepository {
  const UnavailableWalletRepository();

  @override
  Future<WalletDto> getWallet() =>
      Future<WalletDto>.error(const WalletBackendUnavailableException());

  @override
  Future<List<WalletPayMethodDto>> getPayMethods() =>
      Future<List<WalletPayMethodDto>>.error(
        const WalletBackendUnavailableException(),
      );

  @override
  Future<WalletExchangeOrderDto> exchange(WalletExchangeReq req) =>
      Future<WalletExchangeOrderDto>.error(
        const WalletBackendUnavailableException(),
      );

  @override
  Future<List<WalletExchangeOrderDto>> getExchangeRecords({int page = 0, int size = 20}) async => const [];

  @override
  Future<List<WalletRecordDto>> getDepositRecords() async => const [];

  @override
  Future<List<WalletRecordDto>> getWithdrawRecords() async => const [];
}

/// Static product metadata that keeps the 99chat Wallet shell complete when
/// no wallet backend is configured. Values that depend on an account/backend
/// deliberately remain unknown (`--`) and never masquerade as a zero balance.
const List<CoinDto> walletUnavailableProductCoins = <CoinDto>[
  CoinDto(
    name: '99币',
    sub: '--',
    bal: '--',
    fiat: '--',
    type: CoinType.cny,
    code: '99',
    platformCoin: true,
    depositEnabled: false,
    withdrawEnabled: true,
    balMinor: 0,
    scale: 2,
  ),
  CoinDto(
    name: 'USDT',
    sub: '--',
    bal: '--',
    fiat: '--',
    type: CoinType.usdt,
    code: 'USDT',
    depositEnabled: true,
    withdrawEnabled: true,
    balMinor: 0,
    scale: 6,
  ),
];

class WalletDto {
  final String totalBal;
  /// 总资产折合 USD（不含 `$` 前缀）；汇率不可用时为空。
  final String totalBalUsd;
  final String trxAddr;
  final List<CoinDto> coins;

  const WalletDto({
    required this.totalBal,
    this.totalBalUsd = '',
    required this.trxAddr,
    required this.coins,
  });
}

class CoinDto {
  final String name;
  final String sub;
  final String bal;
  final String fiat;
  final CoinType type;
  final String code;
  final String? logoUrl;
  final bool platformCoin;
  final bool depositEnabled;
  final bool withdrawEnabled;
  final int balMinor;
  final int scale;
  /// 24h 涨跌幅（百分比数值，如 `0.12` 表示 +0.12%）；未知时为 null。
  final double? priceChangePercent;

  const CoinDto({
    required this.name,
    required this.sub,
    required this.bal,
    required this.fiat,
    required this.type,
    this.code = '',
    this.logoUrl,
    this.platformCoin = false,
    this.depositEnabled = true,
    this.withdrawEnabled = true,
    this.balMinor = 0,
    this.scale = 6,
    this.priceChangePercent,
  });

  /// 小额资产人民币估值阈值（元）。估值低于该值视为小额。
  static const double smallAssetThresholdCny = 1;

  /// 折合人民币估值是否低于 [smallAssetThresholdCny]（用于「隐藏小额资产」）。
  bool get isSmallAsset {
    final raw = fiat.replaceAll(RegExp(r'[¥$,\s≈]'), '');
    final value = double.tryParse(raw);
    if (value != null) return value < smallAssetThresholdCny;
    // Backend-unavailable product shells use `--` for valuation. Unknown is
    // not the same as a verified small balance, so keep the coin visible.
    return false;
  }

  WalletPayMethodDto toPayMethod({required String net}) {
    final payId = platformCoin
        ? WalletCurrency.platform
        : (code.isNotEmpty ? code.toUpperCase() : name.toUpperCase());
    return WalletPayMethodDto(
      id: payId,
      coin: name,
      net: net,
      bal: bal,
      fiat: fiat,
      balMinor: balMinor,
      scale: scale,
      logoUrl: logoUrl,
      code: code,
      platformCoin: platformCoin,
      color: platformCoin ? const Color(0xFF2B72FF) : const Color(0xFF26A17B),
      badgeColor:
          platformCoin ? const Color(0xFF45C3FF) : const Color(0xFFFF001F),
      badge: platformCoin ? '99' : 'T',
    );
  }
}

enum CoinType { trx, usdt, cny }

/// 发红包 / 转账等场景共用的付款方式 DTO。
class WalletPayMethodDto {
  final String id;
  final String coin;
  final String net;
  final String bal;
  final String fiat;
  final int balMinor;
  final int scale;
  final int feeMinor;
  final String feeCoin;
  final int feeScale;
  final int feeBalanceMinor;
  final Color color;
  final Color badgeColor;
  final String badge;
  final bool enabled;
  final String? logoUrl;
  final String code;
  final bool platformCoin;

  const WalletPayMethodDto({
    required this.id,
    required this.coin,
    required this.net,
    required this.bal,
    required this.fiat,
    required this.balMinor,
    required this.scale,
    this.feeMinor = 0,
    this.feeCoin = '',
    this.feeScale = 0,
    this.feeBalanceMinor = 0,
    required this.color,
    required this.badgeColor,
    required this.badge,
    this.enabled = true,
    this.logoUrl,
    this.code = '',
    this.platformCoin = false,
  });

  static const empty = WalletPayMethodDto(
    id: '',
    coin: 'USDT',
    net: '',
    bal: '--',
    fiat: '--',
    balMinor: 0,
    scale: 6,
    color: Color(0xFF26A17B),
    badgeColor: Color(0xFF999999),
    badge: '-',
    enabled: false,
  );
}



enum WalletExchangeDirection {
  usdtToPlatform,
  platformToUsdt,
}

extension WalletExchangeDirectionX on WalletExchangeDirection {
  String get code {
    switch (this) {
      case WalletExchangeDirection.usdtToPlatform:
        return 'USDT_TO_PLATFORM';
      case WalletExchangeDirection.platformToUsdt:
        return 'PLATFORM_TO_USDT';
    }
  }

  String get inputCoin {
    switch (this) {
      case WalletExchangeDirection.usdtToPlatform:
        return 'USDT';
      case WalletExchangeDirection.platformToUsdt:
        return '99';
    }
  }

  String get outputCoin {
    switch (this) {
      case WalletExchangeDirection.usdtToPlatform:
        return '99';
      case WalletExchangeDirection.platformToUsdt:
        return 'USDT';
    }
  }

  int get inputScale {
    switch (this) {
      case WalletExchangeDirection.usdtToPlatform:
        return WalletCurrency.usdtScale;
      case WalletExchangeDirection.platformToUsdt:
        return WalletCurrency.platformScale;
    }
  }

  int get outputScale {
    switch (this) {
      case WalletExchangeDirection.usdtToPlatform:
        return WalletCurrency.platformScale;
      case WalletExchangeDirection.platformToUsdt:
        return WalletCurrency.usdtScale;
    }
  }
}

class WalletExchangeReq {
  final WalletExchangeDirection direction;
  final int amount;
  final String payPin;

  const WalletExchangeReq({
    required this.direction,
    required this.amount,
    required this.payPin,
  });
}

class WalletExchangeOrderDto {
  final String id;
  final String userId;
  final WalletExchangeDirection direction;
  final int inputAmount;
  final int outputAmount;
  final int surplusFen;
  final String rateSnapshot;
  final String createdAt;

  const WalletExchangeOrderDto({
    required this.id,
    required this.userId,
    required this.direction,
    required this.inputAmount,
    required this.outputAmount,
    required this.surplusFen,
    required this.rateSnapshot,
    required this.createdAt,
  });
}
