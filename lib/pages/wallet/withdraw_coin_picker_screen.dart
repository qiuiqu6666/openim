import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'host/wallet_i18n.dart';

import 'wallet_controller.dart';
import 'wallet_repository.dart';
import 'widgets/wallet_page_colors.dart';
import 'withdraw_address_screen.dart';
import 'host/wallet_navigation.dart';


class WithdrawCoinPickerScreen extends StatelessWidget {
  const WithdrawCoinPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WalletController()..load(),
      child: const _WithdrawCoinPickerView(),
    );
  }
}

class _WithdrawCoinPickerView extends StatelessWidget {
  const _WithdrawCoinPickerView();

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final ctl = context.watch<WalletController>();
    final cs = WalletPageColors.of(context);
    final appBar = WalletAppBarColors.of(context);

    return wrapWalletPage(
      context,
      Scaffold(
      backgroundColor: cs.bg,
      appBar: AppBar(
        leading: const AppBackButton(),
        centerTitle: true,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: appBar.background,
        foregroundColor: appBar.title,
        systemOverlayStyle: walletPageOverlayStyle(context),
        title: Text(
          i18n.t(
            zhHans: '选择币种',
            zhHant: '選擇幣種',
            en: 'Select coin',
            ja: '通貨を選択',
            ko: '코인 선택',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: appBar.title,
          ),
        ),
      ),
      body: ctl.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: cs.inputFill,
                      borderRadius: const BorderRadius.all(Radius.circular(18)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: cs.inputHint,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          i18n.t(
                            zhHans: '代币名称或者合约地址',
                            zhHant: '代幣名稱或者合約地址',
                            en: 'Token name or contract address',
                            ja: 'トークン名またはコントラクトアドレス',
                            ko: '토큰 이름 또는 컨트랙트 주소',
                          ),
                          style: TextStyle(
                            color: cs.inputHint,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: ctl.coins.where((c) => c.withdrawEnabled).length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final coins =
                          ctl.coins.where((c) => c.withdrawEnabled).toList();
                      final item = coins[i];
                      final payMethod = _toPayMethod(item, i18n);
                      return _CoinRow(
                        item: item,
                        payMethod: payMethod,
                        onTap: () {
                          openWalletPage<void>(
                            context,
                            WithdrawAddressScreen(
                              coin: item,
                              payMethod: payMethod,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    ),
    );
  }

  WalletPayMethodDto _toPayMethod(CoinDto item, AppI18n i18n) {
    final net = item.platformCoin
        ? i18n.t(
            zhHans: '平台币',
            zhHant: '平台幣',
            en: 'Platform coin',
            ja: 'プラットフォーム通貨',
            ko: '플랫폼 코인',
          )
        : 'Tron(TRC20)';
    return item.toPayMethod(net: net);
  }
}

class _CoinRow extends StatelessWidget {
  final CoinDto item;
  final WalletPayMethodDto payMethod;
  final VoidCallback onTap;

  const _CoinRow({
    required this.item,
    required this.payMethod,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(
          children: [
            _WithdrawCoinIcon(item: payMethod, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 16,
                      color: cs.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    payMethod.net,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.subText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.bal,
                  style: TextStyle(
                    fontSize: 16,
                    color: cs.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.fiat,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.subText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WithdrawCoinIcon extends StatelessWidget {
  final WalletPayMethodDto item;
  final double size;

  const _WithdrawCoinIcon({
    required this.item,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final url = item.logoUrl?.trim() ?? '';
    final isUsdt = item.coin == 'USDT';
    final isPlatform = item.platformCoin || item.id == '99' || item.code == '99';

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (url.isNotEmpty)
            ClipOval(
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackCoinFace(
                  isUsdt: isUsdt,
                  isPlatform: isPlatform,
                ),
              ),
            )
          else
            _fallbackCoinFace(isUsdt: isUsdt, isPlatform: isPlatform),
          if (!isPlatform || url.isEmpty)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  item.badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallbackCoinFace({required bool isUsdt, required bool isPlatform}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isUsdt ? const Color(0xFF26A17B) : item.color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: isUsdt
            ? CustomPaint(
                size: Size(size * 0.72, size * 0.72),
                painter: _UsdtPainter(),
              )
            : isPlatform
                ? Image.asset(
                    'assets/img/platform_99.webp',
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  )
                : Text(
                    item.coin.substring(0, 1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
      ),
    );
  }
}

class _UsdtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.12, w * 0.84, h * 0.16),
        Radius.circular(w * 0.02),
      ),
      fill,
    );
    final stem = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.41, h * 0.12, w * 0.18, h * 0.76),
      Radius.circular(w * 0.02),
    );
    canvas.drawRRect(stem, fill);
    final oval = Rect.fromCenter(
      center: Offset(w / 2, h * 0.53),
      width: w * 0.92,
      height: h * 0.28,
    );
    canvas.drawArc(oval, 0.06, 6.16, false, stroke);
    final cover = Paint()
      ..color = const Color(0xFF26A17B)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.35, h * 0.43, w * 0.30, h * 0.13),
      cover,
    );
    canvas.drawRRect(stem, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
