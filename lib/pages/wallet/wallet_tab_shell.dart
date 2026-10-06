import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../mine/mine_logic.dart';
import 'host/wallet_i18n.dart';
import 'host/wallet_navigation.dart';
import 'host/wallet_qr_scanner.dart';
import 'host/wallet_toast.dart';
import 'wallet_screen.dart';
import 'wallet_repository.dart';
import 'widgets/wallet_page_colors.dart';

class WalletTabShell extends StatelessWidget {
  const WalletTabShell({
    super.key,
    required this.activeTabIndexListenable,
    this.mainTabIndex = 3,
    this.repository,
  });

  final ValueListenable<int> activeTabIndexListenable;
  final int mainTabIndex;
  final WalletRepository? repository;

  Future<void> _openScanner(BuildContext context) async {
    final code = await openWalletPage<String>(
      context,
      const WalletQrScannerPage(),
    );
    if (!context.mounted || code == null || code.trim().isEmpty) return;
    final i18n = AppI18n.of(context);
    ToastUtils.toast(
      i18n.t(
        zhHans: '扫码结果暂不可用',
        zhHant: '掃碼結果暫不可用',
        en: 'This QR result is not available yet',
        ja: 'このQR結果はまだ利用できません',
        ko: '이 QR 결과는 아직 사용할 수 없습니다',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final title = AppI18n.of(context).t(
      zhHans: '钱包',
      zhHant: '錢包',
      en: 'Wallet',
      ja: 'ウォレット',
      ko: '지갑',
    );
    // PersistentTabView exposes the occupied bottom-tab area through the
    // inherited MediaQuery. SafeArea consumes that inset exactly once.
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: _WalletMainTabHeader(
        onScan: () => _openScanner(context),
        title: title,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: WalletScreen(
          key: const ValueKey('wallet-main-tab'),
          embeddedInMainTab: true,
          activeTabIndexListenable: activeTabIndexListenable,
          mainTabIndex: mainTabIndex,
          repository: repository,
        ),
      ),
    );
  }
}

class _WalletMainTabHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const _WalletMainTabHeader({required this.onScan, required this.title});

  final VoidCallback onScan;
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final theme = Theme.of(context);
    final titleColor = colors.text;
    final screenWidth = MediaQuery.sizeOf(context).width;

    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: colors.bg,
      foregroundColor: titleColor,
      systemOverlayStyle: walletPageOverlayStyle(context),
      titleSpacing: 16,
      title: Text(
        title,
        key: const ValueKey('wallet-title-text'),
        style: theme.textTheme.titleLarge?.copyWith(
          color: titleColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        _WalletHeaderIconButton(
          tooltip: AppI18n.of(context).t(
            zhHans: '扫一扫',
            zhHant: '掃一掃',
            en: 'Scan QR code',
            ja: 'QRコードをスキャン',
            ko: 'QR 코드 스캔',
          ),
          onPressed: onScan,
          child: _WalletScanIcon(
            size: 24,
            color: titleColor,
          ),
        ),
        _WalletHeaderIconButton(
          tooltip: AppI18n.of(context).t(
            zhHans: '消息通知',
            zhHant: '消息通知',
            en: 'Notifications',
            ja: '通知',
            ko: '알림',
          ),
          onPressed: () => Get.find<MineLogic>().openNotifications(context),
          child: CustomPaint(
            size: const Size.square(24),
            painter: _WalletBellIconPainter(titleColor),
          ),
        ),
        SizedBox(width: screenWidth * 0.020),
      ],
    );
  }
}

class _WalletHeaderIconButton extends StatelessWidget {
  const _WalletHeaderIconButton(
      {required this.onPressed, required this.child, required this.tooltip});

  final VoidCallback onPressed;
  final Widget child;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: child,
    );
  }
}

class _WalletScanIcon extends StatelessWidget {
  const _WalletScanIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _WalletScanIconPainter(color: color),
    );
  }
}

class _WalletScanIconPainter extends CustomPainter {
  _WalletScanIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 28);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(8.4, 3)
        ..lineTo(5.2, 3)
        ..quadraticBezierTo(3, 3, 3, 5.4)
        ..lineTo(3, 8.6)
        ..moveTo(19.6, 3)
        ..lineTo(22.8, 3)
        ..quadraticBezierTo(25, 3, 25, 5.4)
        ..lineTo(25, 8.6)
        ..moveTo(3, 19)
        ..lineTo(3, 22.2)
        ..quadraticBezierTo(3, 24.4, 5.2, 24.4)
        ..lineTo(8.4, 24.4)
        ..moveTo(19.6, 24.4)
        ..lineTo(22.8, 24.4)
        ..quadraticBezierTo(25, 24.4, 25, 22.2)
        ..lineTo(25, 19)
        ..moveTo(8, 13.8)
        ..lineTo(20, 13.8),
      stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WalletScanIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _WalletBellIconPainter extends CustomPainter {
  const _WalletBellIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 28);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(12.4, 3.6)
        ..cubicTo(12.4, 1.5, 15.6, 1.5, 15.6, 3.6)
        ..moveTo(6.4, 16.8)
        ..lineTo(6.4, 11)
        ..cubicTo(6.4, 6.5, 9.8, 3.9, 14, 3.9)
        ..cubicTo(18.2, 3.9, 21.6, 6.5, 21.6, 11)
        ..lineTo(21.6, 16.8)
        ..lineTo(23.6, 20.1)
        ..lineTo(4.4, 20.1)
        ..close(),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(10, 22.6)
        ..lineTo(18, 22.6)
        ..cubicTo(17.3, 27, 10.7, 27, 10, 22.6)
        ..close(),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WalletBellIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
