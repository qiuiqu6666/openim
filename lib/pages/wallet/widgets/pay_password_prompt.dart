import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wallet_coin_logo.dart';
import 'platform_coin_icon.dart';
import '../host/wallet_i18n.dart';
import '../wallet_repository.dart';
import 'wallet_99chat_scale.dart';
import 'wallet_page_colors.dart';

class PayMethodDisplay {
  final String amountText;
  final String? amountCoin;
  final String payText;
  final String? payCoinCode;
  final String? payLogoUrl;
  final String? walletSubtitle;

  const PayMethodDisplay({
    required this.amountText,
    this.amountCoin,
    required this.payText,
    this.payCoinCode,
    this.payLogoUrl,
    this.walletSubtitle,
  });
}

class PayPasswordPrompt extends StatefulWidget {
  final String title;
  final String amountText;
  final String? amountCoin;
  final String payText;
  final String? payCoinCode;
  final String? payLogoUrl;
  final Future<String?> Function(String pwd) onSubmit;
  final String? receiverName;
  final String? receiverId;
  final String? receiverAvatar;
  final String? walletSubtitle;
  final Future<PayMethodDisplay?> Function()? onChangePayMethod;

  const PayPasswordPrompt({
    super.key,
    required this.title,
    required this.amountText,
    this.amountCoin,
    required this.payText,
    this.payCoinCode,
    this.payLogoUrl,
    required this.onSubmit,
    this.receiverName,
    this.receiverId,
    this.receiverAvatar,
    this.walletSubtitle,
    this.onChangePayMethod,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String amountText,
    String? amountCoin,
    required String payText,
    String? payCoinCode,
    String? payLogoUrl,
    required Future<String?> Function(String pwd) onSubmit,
    String? receiverName,
    String? receiverId,
    String? receiverAvatar,
    String? walletSubtitle,
    Future<PayMethodDisplay?> Function()? onChangePayMethod,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      enableDrag: true,
      builder: (_) => PayPasswordPrompt(
        title: title,
        amountText: amountText,
        amountCoin: amountCoin,
        payText: payText,
        payCoinCode: payCoinCode,
        payLogoUrl: payLogoUrl,
        onSubmit: onSubmit,
        receiverName: receiverName,
        receiverId: receiverId,
        receiverAvatar: receiverAvatar,
        walletSubtitle: walletSubtitle,
        onChangePayMethod: onChangePayMethod,
      ),
    );
  }

  @override
  State<PayPasswordPrompt> createState() => _PayPasswordPromptState();
}

class _PayPasswordPromptState extends State<PayPasswordPrompt> {
  String pwd = '';
  String err = '';
  bool sending = false;
  bool succeeded = false;
  bool changingPay = false;

  late String _amountText = widget.amountText;
  late String? _amountCoin = widget.amountCoin;
  late String _payText = widget.payText;
  late String? _payCoinCode = widget.payCoinCode;
  late String? _payLogoUrl = widget.payLogoUrl;
  late String? _walletSubtitle = widget.walletSubtitle;

  Future<void> _changePayMethod() async {
    final cb = widget.onChangePayMethod;
    if (cb == null || sending || changingPay) return;
    setState(() => changingPay = true);
    try {
      final next = await cb();
      if (!mounted || next == null) return;
      setState(() {
        _amountText = next.amountText;
        _amountCoin = next.amountCoin;
        _payText = next.payText;
        _payCoinCode = next.payCoinCode;
        _payLogoUrl = next.payLogoUrl;
        _walletSubtitle = next.walletSubtitle;
        err = '';
      });
    } finally {
      if (mounted) setState(() => changingPay = false);
    }
  }

  Future<void> _tap(String value) async {
    if (sending || pwd.length >= 6) return;
    setState(() {
      pwd += value;
      err = '';
    });
    HapticFeedback.selectionClick();
    if (pwd.length != 6) return;

    setState(() => sending = true);
    final msg = await widget.onSubmit(pwd);
    if (!mounted) return;
    if (msg == null || msg.isEmpty) {
      setState(() => succeeded = true);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      sending = false;
      pwd = '';
      err = msg;
    });
  }

  void _delete() {
    if (sending || pwd.isEmpty) return;
    setState(() {
      pwd = pwd.substring(0, pwd.length - 1);
      err = '';
    });
  }

  void _close() {
    if (sending) return;
    Navigator.of(context).pop(false);
  }

  Widget _buildBigAmount(WalletPageColors cs) {
    final full = _amountText;
    final coin = (_amountCoin ?? '').trim();
    var value = full;
    var unit = '';
    if (coin.isNotEmpty && full.trimRight().endsWith(coin)) {
      value = full.trimRight();
      value = value.substring(0, value.length - coin.length).trimRight();
      unit = coin;
    }

    if (coin.isNotEmpty && double.tryParse(full.trim()) != null) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                full,
                style: TextStyle(
                  fontSize: 66.sp99,
                  color: cs.text,
                  fontWeight: FontWeight.w600,
                  height: 1.05,
                ),
              ),
              SizedBox(width: 12.w99),
              Semantics(
                label: coin,
                child: _PayCoinIcon(
                  coinCode: (_payCoinCode ?? coin).trim(),
                  logoUrl: _payLogoUrl,
                  size: 48.w99,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (unit.isEmpty) {
      return Text(
        full,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 66.sp99,
          color: cs.text,
          fontWeight: FontWeight.w600,
          height: 1.05,
        ),
      );
    }

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 66.sp99,
              color: cs.text,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: 8.w99, bottom: 12.h99),
            child: Text(
              unit,
              style: TextStyle(
                fontSize: 28.sp99,
                color: cs.subText,
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    final subtitle = (_walletSubtitle ?? '').trim();
    final canChangePay = widget.onChangePayMethod != null && !sending;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final maxSheetH = (MediaQuery.sizeOf(context).height *
            (0.88 + math.max(0.0, textScale - 1.0) * 0.05))
        .clamp(480.0, MediaQuery.sizeOf(context).height * 0.96)
        .toDouble();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final statusText = succeeded
        ? ''
        : sending
            ? i18n.t(
                zhHans: '正在验证...',
                zhHant: '驗證中...',
                en: 'Verifying...',
                ja: '確認中...',
                ko: '확인 중...',
              )
            : (err.isEmpty ? '' : err);
    final statusColor = err.isEmpty ? cs.subText : cs.red;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetH),
      child: Container(
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30.r99)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow,
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 14.h99),
              Container(
                width: 82.w99,
                height: 6.5.h99,
                decoration: BoxDecoration(
                  color: cs.line,
                  borderRadius: BorderRadius.circular(99.r99),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12.w99, 12.h99, 12.w99, 4.h99),
                child: SizedBox(
                  height: 56.h99,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(30.r99),
                          onTap: sending ? null : _close,
                          child: Padding(
                            padding: EdgeInsets.all(8.w99),
                            child: Icon(
                              Icons.close_rounded,
                              size: 39.sp99,
                              color: sending
                                  ? cs.subText.withValues(alpha: 0.4)
                                  : cs.subText,
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 25.sp99,
                            color: cs.subText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(32.w99, 16.h99, 32.w99, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 4.h99),
                      _buildBigAmount(cs),
                      SizedBox(height: 28.h99),
                      Row(
                        children: [
                          Text(
                            i18n.t(
                              zhHans: '付款方式',
                              zhHant: '付款方式',
                              en: 'Payment Method',
                              ja: '支払い方法',
                              ko: '결제 수단',
                            ),
                            style: TextStyle(
                              fontSize: 24.sp99,
                              color: cs.subText,
                            ),
                          ),
                          const Spacer(),
                          if (widget.onChangePayMethod != null)
                            InkWell(
                              borderRadius: BorderRadius.circular(20.r99),
                              onTap: canChangePay ? _changePayMethod : null,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6.w99,
                                  vertical: 4.h99,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      i18n.t(
                                        zhHans: '更改',
                                        zhHant: '更改',
                                        en: 'Change',
                                        ja: '変更',
                                        ko: '변경',
                                      ),
                                      style: TextStyle(
                                        fontSize: 24.sp99,
                                        color: cs.blue,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 30.sp99,
                                      color: cs.blue,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 12.h99),
                      _PayMethodCard(
                        payText: _payText,
                        payCoinCode: _payCoinCode,
                        payLogoUrl: _payLogoUrl,
                        highlight: true,
                        onTap: canChangePay ? _changePayMethod : null,
                        title: i18n.t(
                          zhHans: '我的钱包',
                          zhHant: '我的錢包',
                          en: 'My Wallet',
                          ja: 'マイウォレット',
                          ko: '내 지갑',
                        ),
                        subtitle: subtitle.isEmpty ? _payText : subtitle,
                      ),
                      SizedBox(height: 22.h99),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (i) {
                          return Padding(
                            padding: EdgeInsets.symmetric(horizontal: 7.w99),
                            child: _PwdCell(
                              size: 58.w99,
                              filled: pwd.length > i,
                              hasError: err.isNotEmpty,
                              cs: cs,
                            ),
                          );
                        }),
                      ),
                      SizedBox(height: 8.h99),
                      SizedBox(
                        height: 22.h99,
                        child: Text(
                          statusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15.sp99,
                            color: statusColor,
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h99),
                    ],
                  ),
                ),
              ),
              Container(
                color: cs.surfaceAlt,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: succeeded
                    ? SizedBox(
                        width: double.infinity,
                        height: 432.h99,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded, size: 32, color: cs.blue),
                            const SizedBox(height: 12),
                            Text(i18n.t(
                                zhHans: '支付成功',
                                zhHant: '支付成功',
                                en: 'Payment successful',
                                ja: '支払い成功',
                                ko: '결제 성공')),
                          ],
                        ),
                      )
                    : _KeyPad(
                        cs: cs,
                        enabled: !sending,
                        onTap: _tap,
                        onDel: _delete,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PwdCell extends StatelessWidget {
  final double size;
  final bool filled;
  final bool hasError;
  final WalletPageColors cs;

  const _PwdCell({
    required this.size,
    required this.filled,
    required this.hasError,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final dot = (size * 0.26).clamp(10.0, 14.0);
    final borderColor = hasError ? cs.red : cs.line;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.inputFill,
        borderRadius: BorderRadius.circular(8.r99),
        border: Border.all(
          color: borderColor,
          width: hasError ? 1 : 0.5,
        ),
      ),
      child: filled
          ? Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: cs.text,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

class _PayMethodCard extends StatelessWidget {
  final String payText;
  final String? payCoinCode;
  final String? payLogoUrl;
  final String title;
  final String subtitle;
  final bool highlight;
  final VoidCallback? onTap;

  const _PayMethodCard({
    required this.payText,
    this.payCoinCode,
    this.payLogoUrl,
    required this.title,
    required this.subtitle,
    this.highlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final coinCode = (payCoinCode?.trim().isNotEmpty ?? false)
        ? payCoinCode!.trim().toUpperCase()
        : _coinFromPayText(payText);
    final bg = highlight
        ? cs.blue.withValues(alpha: cs.dark ? 0.18 : 0.08)
        : (cs.dark ? cs.inputFill : cs.surfaceAlt);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20.r99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.r99),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w99, vertical: 24.h99),
          child: Row(
            children: [
              _PayCoinIcon(
                coinCode: coinCode,
                logoUrl: payLogoUrl,
                size: 74.w99,
              ),
              SizedBox(width: 20.w99),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 27.sp99,
                        color: cs.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 10.h99),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 22.sp99,
                        color: cs.subText,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.check_rounded,
                size: 42.sp99,
                color: cs.blue,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _coinFromPayText(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    return parts.first.toUpperCase();
  }
}

class _KeyPad extends StatelessWidget {
  final WalletPageColors cs;
  final bool enabled;
  final ValueChanged<String> onTap;
  final VoidCallback onDel;

  static const double _rowHeight = 108;
  static const double _digitFontSize = 50;
  static const double _deleteIconSize = 48;

  const _KeyPad({
    required this.cs,
    required this.enabled,
    required this.onTap,
    required this.onDel,
  });

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];
    final line = cs.line;
    return Table(
      defaultColumnWidth: const FlexColumnWidth(),
      border: TableBorder(
        top: BorderSide(color: line, width: 0.5),
        horizontalInside: BorderSide(color: line, width: 0.5),
        verticalInside: BorderSide(color: line, width: 0.5),
      ),
      children: [
        for (final row in rows)
          TableRow(
            children: [
              for (final key in row)
                _KeyPadButton(
                  cs: cs,
                  enabled: enabled,
                  keyValue: key,
                  rowHeight: _rowHeight,
                  digitFontSize: _digitFontSize,
                  deleteIconSize: _deleteIconSize,
                  onTap: onTap,
                  onDel: onDel,
                ),
            ],
          ),
      ],
    );
  }
}

class _KeyPadButton extends StatelessWidget {
  final WalletPageColors cs;
  final bool enabled;
  final String keyValue;
  final double rowHeight;
  final double digitFontSize;
  final double deleteIconSize;
  final ValueChanged<String> onTap;
  final VoidCallback onDel;

  const _KeyPadButton({
    required this.cs,
    required this.enabled,
    required this.keyValue,
    required this.rowHeight,
    required this.digitFontSize,
    required this.deleteIconSize,
    required this.onTap,
    required this.onDel,
  });

  @override
  Widget build(BuildContext context) {
    final isDigit = keyValue.isNotEmpty && keyValue != 'del';
    final isEmpty = keyValue.isEmpty;
    final bg = isDigit ? cs.card : cs.surfaceAlt;
    final tapHandler = (isEmpty || !enabled)
        ? null
        : (keyValue == 'del' ? onDel : () => onTap(keyValue));
    return TableCell(
      child: Material(
        color: bg,
        child: InkWell(
          onTap: tapHandler,
          child: SizedBox(
            height: rowHeight.h99,
            child: Center(
              child: keyValue == 'del'
                  ? Icon(
                      Icons.backspace_rounded,
                      size: deleteIconSize.sp99,
                      color: enabled ? cs.text : cs.subText,
                    )
                  : Text(
                      keyValue,
                      style: TextStyle(
                        fontSize: digitFontSize.sp99,
                        color: enabled ? cs.text : cs.subText,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PayCoinIcon extends StatelessWidget {
  final String coinCode;
  final String? logoUrl;
  final double size;

  const _PayCoinIcon({
    required this.coinCode,
    this.logoUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final upper = coinCode.trim().toUpperCase();
    final url = logoUrl?.trim() ?? '';
    if (upper == 'USDT' || upper == 'TRX') {
      return WalletCoinLogo(
        type: upper == 'USDT' ? CoinType.usdt : CoinType.trx,
        size: size,
      );
    }
    final isPlatform = const {'99', '99BI', 'BI99', '99币'}.contains(upper);
    if (isPlatform) return PlatformCoinIcon(size: size);
    if (url.isNotEmpty && !isPlatform) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(upper, isPlatform),
        ),
      );
    }
    return _fallback(upper, isPlatform);
  }

  Widget _fallback(String upper, bool isPlatform) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF20B282),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: isPlatform
              ? ClipOval(
                  child: Image.asset(
                    'assets/img/platform_99.webp',
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  ),
                )
              : Text(
                  upper.isEmpty ? '?' : upper.substring(0, 1),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30.sp99,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }
}
