import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../host/wallet_i18n.dart';
import '../../wallet_controller.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_home_tokens.dart';
import 'wallet_trend_chart.dart';
import '../../data/wallet_trend_data.dart';

/// Event-driven history priced by the server at each historical event.
class WalletAssetTrendPanel extends StatelessWidget {
  const WalletAssetTrendPanel({
    super.key,
    required this.currency,
  });

  final String currency;

  @override
  Widget build(BuildContext context) {
    final (visible, data, loading, failed) =
        context.select<WalletController, (bool, WalletTrendData?, bool, bool)>(
            (c) => (c.showBal, c.trend, c.trendLoading, c.trendFailed));
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final muted = WalletHomeTokens.muted(context);
    final title = i18n.t(
        zhHans: '资产趋势',
        zhHant: '資產趨勢',
        en: 'Asset trend',
        ja: '資産推移',
        ko: '자산 추이');
    final explanation = i18n.t(
        zhHans: '使用最新40条记录，固定40个滑动点，不足部分在前面补零。按住横向滑动查看余额，松开恢复当前余额。',
        zhHant: '使用最新40筆記錄，固定40個滑動點，不足部分在前面補零。按住橫向滑動查看餘額，鬆開恢復目前餘額。',
        en: 'Latest 40 records, padded with leading zeros to 40 points. Hold and slide to inspect; release to restore the current balance.',
        ja: '選択期間の資産評価額の変化。資産推移データはまだありません。',
        ko: '선택 기간의 자산 가치 변화입니다. 자산 추이 데이터가 없습니다.');
    return Column(
      key: const ValueKey('wallet-trend-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Flexible(
            child: Text(title,
                style: TextStyle(
                    fontSize: WalletHomeTokens.caption,
                    fontWeight: FontWeight.w600,
                    color: colors.text)),
          ),
          Tooltip(
            message: explanation,
            triggerMode: TooltipTriggerMode.tap,
            child: SizedBox.square(
              dimension: WalletHomeTokens.minTap,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppTokens.s2),
                  child: Icon(Icons.info_rounded,
                      size: WalletHomeTokens.body, color: muted),
                ),
              ),
            ),
          ),
        ]),
        Semantics(
          liveRegion: true,
          label: '$title · $currency',
          child: SizedBox(
            height: WalletHomeTokens.trendPlotHeight,
            child: !visible
                ? Center(
                    child: Text(
                        i18n.t(
                            zhHans: '资产已隐藏',
                            zhHant: '資產已隱藏',
                            en: 'Balances are hidden',
                            ja: '残高は非表示です',
                            ko: '자산이 숨겨졌습니다'),
                        key: const ValueKey('wallet-trend-hidden'),
                        style: TextStyle(color: muted)))
                : loading && data == null
                    ? const Center(child: CircularProgressIndicator())
                    : failed
                        ? Center(
                            child: TextButton(
                                onPressed: () => context
                                    .read<WalletController>()
                                    .loadTrend(),
                                child: Text(i18n.t(
                                    zhHans: '趋势加载失败，点击重试',
                                    zhHant: '趨勢載入失敗，點擊重試',
                                    en: 'Trend failed. Tap to retry',
                                    ja: '再試行',
                                    ko: '다시 시도'))))
                        : data == null
                            ? Center(
                                child: Text(
                                    i18n.t(
                                        zhHans: '暂无资产趋势数据',
                                        zhHant: '暫無資產趨勢資料',
                                        en: 'No asset history yet',
                                        ja: '資産推移データはまだありません',
                                        ko: '자산 추이 데이터가 없습니다'),
                                    key: const ValueKey('wallet-trend-empty'),
                                    style: TextStyle(color: muted)))
                            : WalletTrendChart(
                                data: data,
                                onInspect: context
                                    .read<WalletController>()
                                    .inspectTrendBalance,
                                onInspectEnd: context
                                    .read<WalletController>()
                                    .endTrendInspection),
          ),
        ),
      ],
    );
  }
}
