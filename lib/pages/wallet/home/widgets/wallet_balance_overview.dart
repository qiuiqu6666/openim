import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../host/wallet_i18n.dart';
import '../../wallet_controller.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_home_tokens.dart';
import '../wallet_amount_display.dart';
import 'wallet_overview_icon.dart';

/// Account values are already formatted by the repository. Display the exact
/// strings rather than parsing or recalculating monetary values in the UI.
class WalletBalanceOverview extends StatelessWidget {
  const WalletBalanceOverview({
    super.key,
    required this.onRecords,
    required this.onOverview,
    this.overviewExpanded = false,
  });

  final VoidCallback onRecords;
  final VoidCallback onOverview;
  final bool overviewExpanded;

  @override
  Widget build(BuildContext context) {
    final (
      total,
      visible,
      inspecting,
      inspected
    ) = context.select<WalletController, (String, bool, bool, String?)>(
        (c) => (c.totalBal, c.showBal, c.inspectingTrend, c.inspectedTrendCny));
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final muted = WalletHomeTokens.muted(context);
    final assetLabel = i18n.t(
      zhHans: '总资产估值',
      zhHant: '總資產估值',
      en: 'Total asset value',
      ja: '総資産評価額',
      ko: '총 자산 가치',
    );
    final visibilityLabel = visible
        ? i18n.t(
            zhHans: '隐藏金额',
            zhHant: '隱藏金額',
            en: 'Hide balances',
            ja: '残高を非表示',
            ko: '잔액 숨기기')
        : i18n.t(
            zhHans: '显示金额',
            zhHant: '顯示金額',
            en: 'Show balances',
            ja: '残高を表示',
            ko: '잔액 표시');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(assetLabel,
                        style: TextStyle(
                            fontSize: WalletHomeTokens.caption, color: muted)),
                  ),
                  IconButton(
                    key: const ValueKey('wallet-toggle-balance'),
                    tooltip: visibilityLabel,
                    onPressed: context.read<WalletController>().toggleBal,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(WalletHomeTokens.minTap),
                      padding: EdgeInsets.zero,
                      foregroundColor: muted,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rSm)),
                    ),
                    icon: Icon(
                        visible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: WalletHomeTokens.body),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('wallet-action-overview'),
              tooltip: overviewExpanded
                  ? i18n.t(
                      zhHans: '收起资产趋势',
                      zhHant: '收起資產趨勢',
                      en: 'Hide asset trend',
                      ja: '資産推移を閉じる',
                      ko: '자산 추이 접기')
                  : i18n.t(
                      zhHans: '展开资产趋势',
                      zhHant: '展開資產趨勢',
                      en: 'Show asset trend',
                      ja: '資産推移を開く',
                      ko: '자산 추이 펼치기'),
              isSelected: overviewExpanded,
              onPressed: onOverview,
              style: _iconStyle(overviewExpanded
                  ? WalletHomeTokens.trendIcon(context)
                  : colors.text),
              icon: const WalletOverviewIcon.details(),
            ),
            IconButton(
              key: const ValueKey('wallet-action-record'),
              tooltip: i18n.t(
                  zhHans: '交易记录',
                  zhHant: '交易記錄',
                  en: 'Transaction history',
                  ja: '取引履歴',
                  ko: '거래 내역'),
              onPressed: onRecords,
              style: _iconStyle(colors.text),
              icon: const WalletOverviewIcon.history(),
            ),
          ],
        ),
        Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppTokens.s2,
            runSpacing: AppTokens.s2,
            children: [
              Text(
                !visible
                    ? '••••••'
                    : inspecting && inspected == null
                        ? '历史价格暂缺'
                        : '¥${walletAmountDisplay(inspecting ? inspected! : total)}',
                key: const ValueKey('wallet-total-amount'),
                // Preserve every supplied digit, even when the value wraps.
                style: TextStyle(
                  fontSize: WalletHomeTokens.totalAmount,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: colors.text,
                ),
              ),
              Text(
                'CNY',
                key: const ValueKey('wallet-display-currency'),
                style: TextStyle(
                    fontSize: WalletHomeTokens.body,
                    fontWeight: FontWeight.w500,
                    color: colors.text),
              ),
            ]),
      ],
    );
  }

  ButtonStyle _iconStyle(Color foreground) => IconButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size.square(WalletHomeTokens.minTap),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.rSm)),
      );
}
