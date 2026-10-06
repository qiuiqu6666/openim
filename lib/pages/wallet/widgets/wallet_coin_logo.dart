import 'package:flutter/material.dart';

import '../host/wallet_image_cache.dart';
import '../host/wallet_network_image.dart';
import '../wallet_repository.dart';
import 'platform_coin_icon.dart';

/// TRX and USDT always use the bundled, user-provided currency artwork.
class WalletCoinLogo extends StatelessWidget {
  const WalletCoinLogo({
    super.key,
    required this.type,
    this.logoUrl,
    this.size = defaultSize,
  });

  /// Shared currency face size, matching the existing wallet asset rows.
  static const double defaultSize = 36;

  final CoinType type;

  /// Optional platform-coin image; TRX and USDT retain their local artwork.
  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = type == CoinType.cny ? logoUrl?.trim() ?? '' : '';
    final cacheSize = ImageMemCacheSize.forLogicalSize(size, context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: url.isEmpty
            ? _fallback()
            : ClipOval(
                child: AppNetworkImage(
                  url: url,
                  width: size,
                  height: size,
                  memCacheWidth: cacheSize,
                  memCacheHeight: cacheSize,
                  errorWidget: (_, __, ___) => _fallback(),
                ),
              ),
      ),
    );
  }

  Widget _fallback() {
    if (type == CoinType.cny) return PlatformCoinIcon(size: size);
    return ClipOval(
      child: Image.asset(
        type == CoinType.trx
            ? 'lib/pages/wallet/widgets/assets/trx.png'
            : 'lib/pages/wallet/widgets/assets/usdt.webp',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
