import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../home/widgets/main_tab_title.dart';
import '../mine/mine_logic.dart';
import 'host/wallet_i18n.dart';
import 'host/wallet_navigation.dart';
import 'host/wallet_qr_scanner.dart';
import 'host/wallet_toast.dart';
import 'wallet_screen.dart';
import 'widgets/wallet_system_ui.dart';

class WalletTabShell extends StatelessWidget {
  const WalletTabShell({
    super.key,
    required this.activeTabIndexListenable,
    this.mainTabIndex = 3,
  });

  final ValueListenable<int> activeTabIndexListenable;
  final int mainTabIndex;

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: dark ? Alignment.topLeft : Alignment.topCenter,
          end: dark ? Alignment.bottomRight : Alignment.bottomCenter,
          colors: dark
              ? kDecorativePageGradientColorsDark
              : kDecorativePageGradientColorsLight,
          stops: dark ? kDecorativePageGradientStopsDark : null,
        ),
      ),
      // PersistentTabView exposes the occupied bottom-tab area through the
      // inherited MediaQuery. SafeArea consumes that inset exactly once.
      // Adding another kBottomNavigationBarHeight here lifts the fixed invite
      // card by a full nav-bar height, which diverges from 99chat.
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _WalletMainTabHeader(onScan: () => _openScanner(context)),
        body: SafeArea(
          top: false,
          bottom: true,
          child: WalletScreen(
            key: const ValueKey('wallet-main-tab'),
            embeddedInMainTab: true,
            activeTabIndexListenable: activeTabIndexListenable,
            mainTabIndex: mainTabIndex,
          ),
        ),
      ),
    );
  }
}

class _WalletMainTabHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const _WalletMainTabHeader({required this.onScan});

  final VoidCallback onScan;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final titleColor = theme.appBarTheme.foregroundColor ??
        theme.colorScheme.onSurface;
    final screenWidth = MediaQuery.sizeOf(context).width;

    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      foregroundColor: titleColor,
      systemOverlayStyle: decorativeMainTabOverlayStyle(
        dark: dark,
        navigationBarBackground: theme.scaffoldBackgroundColor,
      ),
      titleSpacing: 16,
      flexibleSpace: _WalletHeaderSparkles(isDark: dark),
      title: MainTabTitle(
        title: AppI18n.of(context).t(
          zhHans: '钱包',
          zhHant: '錢包',
          en: 'Wallet',
          ja: 'ウォレット',
          ko: '지갑',
        ),
        color: titleColor,
        titleKey: const ValueKey('wallet-title-text'),
        indicatorLineKey: const ValueKey('wallet-title-indicator-line'),
        indicatorDotKey: const ValueKey('wallet-title-indicator-dot'),
      ),
      actions: [
        _WalletHeaderIconButton(
          onPressed: onScan,
          child: _WalletScanIcon(
            size: screenWidth * 0.058,
            color: titleColor,
          ),
        ),
        _WalletHeaderIconButton(
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
  const _WalletHeaderIconButton({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: child,
    );
  }
}

class _WalletHeaderSparkles extends StatelessWidget {
  const _WalletHeaderSparkles({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          return Stack(
            children: [
              Positioned(
                left: width * 0.19,
                top: height * 0.30,
                child: _DecorativeSparkle(
                  size: width * 0.022,
                  opacity: isDark ? 0.42 : 0.58,
                  isDark: isDark,
                ),
              ),
              Positioned(
                left: width * 0.33,
                top: height * 0.52,
                child: _DecorativeSparkle(
                  size: width * 0.034,
                  opacity: isDark ? 0.48 : 0.62,
                  isDark: isDark,
                ),
              ),
              Positioned(
                right: width * 0.18,
                top: height * 0.36,
                child: _DecorativeSparkle(
                  size: width * 0.024,
                  opacity: isDark ? 0.38 : 0.52,
                  isDark: isDark,
                ),
              ),
              Positioned(
                right: width * 0.34,
                top: height * 0.70,
                child: _DecorativeSparkle(
                  size: width * 0.014,
                  opacity: isDark ? 0.32 : 0.42,
                  isDark: isDark,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DecorativeSparkle extends StatelessWidget {
  const _DecorativeSparkle({
    required this.size,
    required this.opacity,
    required this.isDark,
  });

  final double size;
  final double opacity;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: 0.78,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF8EBBFF).withValues(alpha: 0.55)
                : Colors.white,
            borderRadius: BorderRadius.circular(size * 0.18),
            boxShadow: defaultTargetPlatform == TargetPlatform.android
                ? const <BoxShadow>[]
                : [
                    BoxShadow(
                      color: const Color(0xFF8EBBFF)
                          .withValues(alpha: isDark ? 0.28 : 0.20),
                      blurRadius: size,
                    ),
                  ],
          ),
          child: SizedBox(width: size, height: size),
        ),
      ),
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
