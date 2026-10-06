import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_page_colors.dart';
import '../share/wallet_deposit_share_tokens.dart';
import 'wallet_deposit_qr.dart';

/// The complete address card captured by the existing save/share service.
/// Actions belong to the surrounding sheet and never appear in this image.
class WalletDepositSharePreview extends StatefulWidget {
  const WalletDepositSharePreview({
    super.key,
    required this.address,
    required this.currency,
    this.createdAt,
  });

  final WalletDepositAddress address;
  final FundCurrency currency;
  final DateTime? createdAt;

  @override
  State<WalletDepositSharePreview> createState() =>
      _WalletDepositSharePreviewState();
}

class _WalletDepositSharePreviewState extends State<WalletDepositSharePreview> {
  // Legacy callers also keep one real opening time through subsequent rebuilds.
  late final DateTime _openedAt;

  @override
  void initState() {
    super.initState();
    _openedAt = widget.createdAt ?? DateTime.now();
  }

  String get _timestamp {
    final value = (widget.createdAt ?? _openedAt).toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}/${two(value.month)}/'
        '${two(value.day)} ${two(value.hour)}:${two(value.minute)}:'
        '${two(value.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: WalletDepositShareTokens.cardMaxWidth,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: WalletDepositShareTokens.cardColor(dark: colors.dark),
            borderRadius:
                BorderRadius.circular(WalletDepositShareTokens.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                WalletDepositShareTokens.cardPadding,
                WalletDepositShareTokens.cardPadding,
                WalletDepositShareTokens.cardPadding,
                WalletDepositShareTokens.cardBottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, colors),
                const SizedBox(height: WalletDepositShareTokens.dividerGap),
                Divider(
                  height: 1,
                  thickness: 1,
                  color:
                      WalletDepositShareTokens.dividerColor(dark: colors.dark),
                ),
                const SizedBox(height: WalletDepositShareTokens.titleTopGap),
                Text(
                  i18n.format(
                    zhHans: '将{coin}充值到99Chat',
                    zhHant: '將{coin}儲值到99Chat',
                    en: 'Deposit {coin} to 99Chat',
                    ja: '{coin}を99Chatに入金',
                    ko: '99Chat에 {coin} 입금',
                    vars: {'coin': widget.currency.code},
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: WalletDepositShareTokens.titleFontSize,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: WalletDepositShareTokens.titleQrGap),
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                        WalletDepositShareTokens.qrRadius),
                    child: WalletDepositQr(
                      address: widget.address,
                      currency: widget.currency,
                      size: WalletDepositShareTokens.qrSize,
                      quietZone: WalletDepositShareTokens.qrQuietZone,
                    ),
                  ),
                ),
                const SizedBox(height: WalletDepositShareTokens.qrDetailsGap),
                _detailRow(
                  colors,
                  i18n.t(
                    zhHans: '网络名称',
                    zhHant: '網路名稱',
                    en: 'Network',
                    ja: 'ネットワーク',
                    ko: '네트워크',
                  ),
                  widget.address.network,
                ),
                const SizedBox(height: WalletDepositShareTokens.detailRowGap),
                _detailRow(
                  colors,
                  i18n.t(
                    zhHans: '地址',
                    zhHant: '地址',
                    en: 'Address',
                    ja: 'アドレス',
                    ko: '주소',
                  ),
                  widget.address.address,
                  valueKey: const ValueKey('wallet-deposit-share-address'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, WalletPageColors colors) {
    final brandStyle = TextStyle(
      fontSize: WalletDepositShareTokens.brandFontSize,
      fontWeight: FontWeight.w700,
      color: colors.text,
    );
    final timestampStyle = TextStyle(
      fontSize: WalletDepositShareTokens.timestampFontSize,
      color: colors.subText,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    double textWidth(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
            text: value,
            style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    final brandWidth = WalletDepositShareTokens.brandLogoSize +
        WalletDepositShareTokens.brandGap +
        textWidth('99Chat', brandStyle);
    final timestamp = Text(
      _timestamp,
      key: const ValueKey('wallet-deposit-share-created-at'),
      textAlign: TextAlign.end,
      style: timestampStyle,
    );
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.min(brandWidth, constraints.maxWidth);
      final brand = SizedBox(
        width: width,
        child: Row(children: [
          Image.asset(
            WalletDepositShareTokens.brandLogo,
            width: WalletDepositShareTokens.brandLogoSize,
            height: WalletDepositShareTokens.brandLogoSize,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: WalletDepositShareTokens.brandGap),
          Expanded(child: Text('99Chat', style: brandStyle)),
        ]),
      );
      final fits = brandWidth +
              WalletDepositShareTokens.headerGap +
              textWidth(_timestamp, timestampStyle) <=
          constraints.maxWidth;
      if (fits) {
        return Row(children: [
          brand,
          const SizedBox(width: WalletDepositShareTokens.headerGap),
          Expanded(child: timestamp),
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: brand),
          const SizedBox(height: WalletDepositShareTokens.brandGap),
          timestamp,
        ],
      );
    });
  }

  Widget _detailRow(WalletPageColors colors, String label, String value,
      {Key? valueKey}) {
    final style = TextStyle(
      fontSize: WalletDepositShareTokens.detailFontSize,
      height: WalletDepositShareTokens.detailLineHeight,
      color: colors.text,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: WalletDepositShareTokens.detailLabelWidth,
          child: Text(label, style: style.copyWith(color: colors.subText)),
        ),
        const SizedBox(width: WalletDepositShareTokens.detailColumnGap),
        Expanded(
          child: Text(value,
              key: valueKey, textAlign: TextAlign.end, style: style),
        ),
      ],
    );
  }
}
