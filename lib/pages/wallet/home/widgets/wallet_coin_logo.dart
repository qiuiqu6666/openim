import 'package:flutter/material.dart';

import '../../host/wallet_image_cache.dart';
import '../../host/wallet_network_image.dart';
import '../../wallet_repository.dart';
import '../../widgets/platform_coin_icon.dart';
import '../wallet_home_tokens.dart';

/// Keeps the existing wallet coin artwork, including the network fallback.
class WalletCoinLogo extends StatelessWidget {
  const WalletCoinLogo({
    super.key,
    required this.type,
    this.logoUrl,
    this.size = WalletHomeTokens.coinLogo,
  });

  final CoinType type;
  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim() ?? '';
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
    final inner = size * 0.84;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: type == CoinType.trx ? _tronRed : _usdtGreen,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: type == CoinType.trx
            ? Image.asset(
                'assets/img/TRX.png',
                width: inner,
                height: inner,
                fit: BoxFit.contain,
                color: _logoInk,
                colorBlendMode: BlendMode.srcIn,
              )
            : CustomPaint(
                size: Size.square(inner),
                painter: _UsdtPainter(),
              ),
      ),
    );
  }
}

// Official coin marks keep their original branding in either app theme.
const _tronRed = Color(0xFFFF001F);
const _usdtGreen = Color(0xFF26A17B);
const _logoInk = Color(0xFFFFFFFF);

class _UsdtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = _logoInk;
    final stroke = Paint()
      ..color = _logoInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.078
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.07, h * 0.11, w * 0.86, h * 0.16),
        Radius.circular(w * 0.02),
      ),
      fill,
    );
    final stem = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.405, h * 0.11, w * 0.19, h * 0.78),
      Radius.circular(w * 0.02),
    );
    canvas.drawRRect(stem, fill);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.53),
        width: w * 0.93,
        height: h * 0.28,
      ),
      0.06,
      6.16,
      false,
      stroke,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.35, h * 0.43, w * 0.30, h * 0.13),
      Paint()..color = _usdtGreen,
    );
    canvas.drawRRect(stem, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
