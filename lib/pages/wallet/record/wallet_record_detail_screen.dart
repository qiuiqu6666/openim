import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../host/wallet_i18n.dart';
import '../host/wallet_navigation.dart';
import '../widgets/platform_coin_icon.dart';
import '../widgets/wallet_99chat_scale.dart';
import '../widgets/wallet_page_colors.dart';
import 'wallet_record_models.dart';

class WalletRecordDetailScreen extends StatelessWidget {
  final WalletRecordDto item;

  const WalletRecordDetailScreen({super.key, required this.item});

  String _short(String value) {
    final v = value.trim();
    if (v.isEmpty) return '--';
    if (v.length <= 18) return v;
    return '${v.substring(0, 8)}...${v.substring(v.length - 8)}';
  }

  String get _statusText {
    switch (item.status) {
      case WalletRecordStatus.success:
        return item.income
            ? AppI18n.current.t(
                zhHans: '已收到', zhHant: '已收到', en: 'Received', ja: '受取済み', ko: '수령 완료')
            : AppI18n.current.t(
                zhHans: '已发出', zhHant: '已發出', en: 'Sent', ja: '送信済み', ko: '전송 완료');
      case WalletRecordStatus.pending:
        return item.income
            ? AppI18n.current.t(
                zhHans: '确认中', zhHant: '確認中', en: 'Confirming', ja: '確認中', ko: '확인 중')
            : AppI18n.current.t(
                zhHans: '处理中', zhHant: '處理中', en: 'Processing', ja: '処理中', ko: '처리 중');
      case WalletRecordStatus.failed:
        return AppI18n.current.t(
          zhHans: '失败', zhHant: '失敗', en: 'Failed', ja: '失敗', ko: '실패');
    }
  }

  String get _networkTitle {
    final raw = item.network.trim();
    if (raw.toUpperCase().contains('TRC20') ||
        raw.toUpperCase().contains('TRON') ||
        item.coin.toUpperCase() == 'TRX') {
      return 'Tron';
    }
    return raw.isEmpty ? '--' : raw;
  }

  bool get _showTronNetworkIcon => _networkTitle == 'Tron';

  String get _incomingLabel => item.isChainDeposit
      ? AppI18n.current.t(
          zhHans: '收款地址', zhHant: '收款地址', en: 'Receiving Address', ja: '受取アドレス', ko: '수령 주소')
      : AppI18n.current.t(
          zhHans: '转入地址', zhHant: '轉入地址', en: 'Incoming Address', ja: '入金先アドレス', ko: '입금 주소');

  String get _incomingValue {
    final isWithdraw = item.title == '提现';
    final isDeposit = item.title == '链上充值';
    final isTransfer = item.title == '收到转账' || item.title == '发起转账';
    final candidates = isWithdraw
        ? <String>[item.addr, item.payee]
        : isDeposit
            ? <String>[item.addr, item.payee]
            : isTransfer
                ? <String>[item.payee, item.addr]
                : <String>[item.addr, item.payee, item.payer];
    return candidates.map((e) => e.trim()).firstWhere(
          (e) => e.isNotEmpty && e != '--' && e != '外部地址' && e != '我的钱包',
          orElse: () => '--',
        );
  }

  String get _outgoingValue {
    final isWithdraw = item.title == '提现';
    final isDeposit = item.title == '链上充值';
    final isTransfer = item.title == '收到转账' || item.title == '发起转账';
    final candidates = isWithdraw
        ? <String>[item.payer, '我的钱包']
        : isDeposit
            ? <String>[item.payer]
            : isTransfer
                ? <String>[item.payer, item.payee]
                : <String>[item.payer, item.addr, item.payee];
    return candidates.map((e) => e.trim()).firstWhere(
          (e) => e.isNotEmpty && e != '--' && e != '外部地址',
          orElse: () => '--',
        );
  }

  bool get _platformTransfer {
    if (item.isChainDeposit || item.isChainWithdraw) return false;
    final title = item.title.trim().toLowerCase();
    return title.contains('转账') || title.contains('transfer');
  }

  String get _referenceValue {
    if (item.isSwap) {
      final order = item.orderNo.trim();
      return order.isEmpty ? '--' : order;
    }
    final hash = item.hash.trim();
    return hash.isEmpty ? '--' : hash;
  }

  bool get _showReferenceRow =>
      item.isSwap ? _referenceValue != '--' : (_referenceValue != '--' && !_platformTransfer);

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final appBar = WalletAppBarColors.of(context);
    final i18n = AppI18n.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: cs.bg,
        appBar: AppBar(
          leading: const AppBackButton(),
          centerTitle: true,
          backgroundColor: appBar.background,
          foregroundColor: appBar.title,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: walletPageOverlayStyle(context),
          title: Text(
            i18n.t(
              zhHans: '交易详情',
              zhHant: '交易詳情',
              en: 'Transaction Details',
              ja: '取引詳細',
              ko: '거래 상세',
            ),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: appBar.title,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(22.w99, 24.h99, 22.w99, 24.h99),
            children: [
              Center(
                child: _DetailCoinLogo(
                  coin: item.coin,
                  size: 111.w99,
                ),
              ),
              SizedBox(height: 27.h99),
              _DetailAmountHeader(item: item),
              SizedBox(height: 15.h99),
              Text(
                '--',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24.sp99,
                  fontWeight: FontWeight.w400,
                  color: cs.subText,
                ),
              ),
              SizedBox(height: 51.h99),
              Container(
                decoration: BoxDecoration(
                  color: cs.dark ? cs.inputFill : cs.surfaceAlt,
                  borderRadius: BorderRadius.circular(30.r99),
                ),
                padding: EdgeInsets.symmetric(horizontal: 27.w99, vertical: 15.h99),
                child: Column(
                  children: [
                    if (!item.isSwap) ...[
                      _DetailRow(
                        label: _incomingLabel,
                        value: _short(_incomingValue),
                        copyValue: _incomingValue == '--' ? null : _incomingValue,
                      ),
                      _DetailRow(
                        label: i18n.t(
                          zhHans: '转出地址', zhHant: '轉出地址', en: 'Outgoing Address', ja: '送信元アドレス', ko: '출금 주소'),
                        value: _short(_outgoingValue),
                        copyValue: _outgoingValue == '--' ? null : _outgoingValue,
                      ),
                    ],
                    _DetailRow(
                      label: i18n.t(
                        zhHans: '网络', zhHant: '網路', en: 'Network', ja: 'ネットワーク', ko: '네트워크'),
                      value: _networkTitle,
                      valueWidget: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          if (_showTronNetworkIcon) ...[
                            _DetailCoinLogo(coin: 'TRX', size: 33.w99),
                            SizedBox(width: 12.w99),
                          ],
                          Text(
                            _networkTitle,
                            style: TextStyle(
                              fontSize: 22.5.sp99,
                              fontWeight: FontWeight.w500,
                              color: cs.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _DetailRow(
                      label: i18n.t(
                        zhHans: '交易状态', zhHant: '交易狀態', en: 'Status', ja: 'ステータス', ko: '상태'),
                      value: _statusText,
                    ),
                    if (_showReferenceRow)
                      _DetailRow(
                        label: i18n.t(
                          zhHans: item.isSwap ? '订单号' : '交易哈希',
                          zhHant: item.isSwap ? '訂單號' : '交易雜湊',
                          en: item.isSwap ? 'Order No.' : 'Transaction Hash',
                          ja: item.isSwap ? '注文番号' : 'トランザクションハッシュ',
                          ko: item.isSwap ? '주문 번호' : '거래 해시',
                        ),
                        value: _short(_referenceValue),
                        copyValue: _referenceValue == '--' ? null : _referenceValue,
                      ),
                    _DetailRow(
                      label: i18n.t(
                        zhHans: '交易时间', zhHant: '交易時間', en: 'Time', ja: '取引時間', ko: '거래 시간'),
                      value: item.time.trim().isEmpty ? '--' : item.time,
                      showDivider: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _DetailAmountHeader extends StatelessWidget {
  const _DetailAmountHeader({required this.item});

  final WalletRecordDto item;

  bool get _platformCoin {
    final raw = item.coin.trim();
    return raw.toUpperCase() == '99' || raw == '元';
  }

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    if (!_platformCoin) {
      return Text(
        '${item.amount} ${item.coin}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 51.sp99,
          fontWeight: FontWeight.w700,
          color: cs.text,
          height: 1.05,
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.amount,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 51.sp99,
            fontWeight: FontWeight.w700,
            color: cs.text,
            height: 1.05,
          ),
        ),
        SizedBox(width: 12.w99),
        ClipOval(
          child: Image.asset(
            'assets/img/platform_99.webp',
            width: 42.w99,
            height: 42.w99,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }
}

class _DetailCoinLogo extends StatelessWidget {
  const _DetailCoinLogo({required this.coin, required this.size});

  final String coin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final raw = coin.trim();
    final upper = raw.toUpperCase();
    if (upper == '99' || raw == '元') {
      return ClipOval(
        child: Image.asset(
          'assets/img/platform_99.webp',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    if (upper == 'USDT') {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF26A17B),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size(size * .62, size * .62),
          painter: _DetailUsdtPainter(),
        ),
      );
    }
    if (upper == 'TRX') {
      return SizedBox(
        width: size,
        height: size,
        child: SvgPicture.string(
          _tronLogoSvg,
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF5B8CFF),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        upper.isEmpty ? '?' : upper.substring(0, 1),
        style: TextStyle(
          fontSize: size * .46,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

const String _tronLogoSvg = '''
<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <path d="M512.85 511.04m-447.5 0a447.5 447.5 0 1 0 895 0 447.5 447.5 0 1 0-895 0Z" fill="#D80917"/>
  <path d="M477.1 787.2c-0.84 0-1.71-0.05-2.55-0.18a18.645 18.645 0 0 1-15.04-12.25L277.69 259.74c-2.31-6.56-0.78-13.86 3.97-18.94s11.96-7.12 18.63-5.23l366.29 102.15c2.37 0.66 4.63 1.8 6.56 3.35l68.87 54.7c7.76 6.15 9.36 17.3 3.64 25.36L492.32 779.31a18.628 18.628 0 0 1-15.22 7.89zM324.8 281.12l157.87 447.25L705 414.01l-52.08-41.37-328.12-91.52z" fill="#FFFFFF"/>
  <path d="M477.13 787.2c-0.69 0-1.35-0.04-2.04-0.11-10.23-1.11-17.63-10.31-16.53-20.54l27.42-253.89c1.09-10.27 10.6-17.48 20.54-16.53 10.23 1.11 17.63 10.31 16.53 20.54l-27.42 253.89c-1.02 9.55-9.1 16.64-18.5 16.64z" fill="#FFFFFF"/>
  <path d="M504.52 533.31c-4.73 0-9.47-1.78-13.11-5.37-7.32-7.25-7.39-19.05-0.15-26.38L648.3 342.57c7.25-7.32 19.05-7.39 26.37-0.16 7.32 7.25 7.39 19.05 0.15 26.38L517.77 527.77a18.59 18.59 0 0 1-13.25 5.54z" fill="#FFFFFF"/>
  <path d="M504.52 533.31c-7.03 0-13.77-4.01-16.93-10.83-4.3-9.34-0.22-20.43 9.1-24.75l225.9-104.28c9.4-4.32 20.43-0.24 24.76 9.12 4.3 9.34 0.22 20.43-9.1 24.75L512.35 531.6a18.857 18.857 0 0 1-7.83 1.71z" fill="#FFFFFF"/>
  <path d="M507.21 536.55c-5.46 0-10.85-2.39-14.53-6.99L280.73 265.19c-6.45-8.03-5.15-19.76 2.9-26.2 8.01-6.41 19.79-5.12 26.2 2.9l211.91 264.37c6.45 8.03 5.17 19.76-2.88 26.2a18.563 18.563 0 0 1-11.65 4.09z" fill="#FFFFFF"/>
</svg>
''';

class _DetailUsdtPainter extends CustomPainter {
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
      ..strokeWidth = w * .08
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .08, h * .12, w * .84, h * .16),
        Radius.circular(w * .02),
      ),
      fill,
    );
    final stem = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * .41, h * .12, w * .18, h * .76),
      Radius.circular(w * .02),
    );
    canvas.drawRRect(stem, fill);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w / 2, h * .53),
        width: w * .92,
        height: h * .28,
      ),
      .06,
      6.16,
      false,
      stroke,
    );
    final cover = Paint()
      ..color = const Color(0xFF26A17B)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(w * .35, h * .43, w * .30, h * .13), cover);
    canvas.drawRRect(stem, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.copyValue,
    this.showDivider = true,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final String? copyValue;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 19.5.h99),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 129.w99,
            child: Text(
              label,
              style: TextStyle(
                color: cs.subText,
                fontSize: 24.sp99,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          SizedBox(width: 18.w99),
          Expanded(
            child: valueWidget ??
                Text(
                  value ?? '--',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: cs.text,
                    fontSize: 24.sp99,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
          ),
          if ((copyValue ?? '').isNotEmpty) ...[
            SizedBox(width: 15.w99),
            InkWell(
              onTap: () => Clipboard.setData(ClipboardData(text: copyValue!)),
              child: Icon(Icons.copy_rounded, size: 27.sp99, color: cs.blue),
            ),
          ],
        ],
      ),
    );
  }
}
