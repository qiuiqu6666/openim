// Adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../services/fund_models.dart';
import 'fund_send_tokens.dart';

class FundCoinIcon extends StatelessWidget {
  const FundCoinIcon({super.key, required this.currency, required this.size});
  final FundCurrency currency;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (currency == FundCurrency.bi99) {
      return ClipOval(
          child: Image.asset('assets/img/platform_99.webp',
              width: size, height: size, fit: BoxFit.cover));
    }
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: currency == FundCurrency.usdt
                ? FundWalletTokens.usdtFace
                : FundWalletTokens.otherCoinFace,
            shape: BoxShape.circle),
        child: Center(
            child: currency == FundCurrency.usdt
                ? CustomPaint(
                    size: Size.square(size * .72), painter: _UsdtPainter())
                : Text(currency.displayName.substring(0, 1),
                    style: TextStyle(
                        color: AppTokens.onAccent,
                        fontSize: size * .4,
                        fontWeight: FontWeight.w800))));
  }
}

/// Reference wallet's USDT fallback; no fake network logo requests.
class _UsdtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()
      ..color = AppTokens.onAccent
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = AppTokens.onAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .08
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * .08, h * .12, w * .84, h * .16),
            Radius.circular(w * .02)),
        fill);
    final stem = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .41, h * .12, w * .18, h * .76),
        Radius.circular(w * .02));
    canvas.drawRRect(stem, fill);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(w / 2, h * .53), width: w * .92, height: h * .28),
        .06,
        6.16,
        false,
        stroke);
    canvas.drawRect(Rect.fromLTWH(w * .35, h * .43, w * .30, h * .13),
        Paint()..color = FundWalletTokens.usdtFace);
    canvas.drawRRect(stem, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
