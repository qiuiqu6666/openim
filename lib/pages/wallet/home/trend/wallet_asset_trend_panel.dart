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
        zhHans: '展示近期资产余额的变化。按住图表左右滑动可查看历史余额，松开后显示当前余额。',
        zhHant: '顯示近期資產餘額的變化。按住圖表左右滑動可查看歷史餘額，鬆開後顯示目前餘額。',
        en: 'Shows recent changes in your asset balance. Press and slide left or right to view past balances. Release to show your current balance.',
        ja: '最近の資産残高の変化を表示します。グラフを押したまま左右に動かすと過去の残高を確認できます。指を離すと現在の残高に戻ります。',
        ko: '최근 자산 잔액의 변화를 보여줍니다. 차트를 누른 채 좌우로 움직이면 과거 잔액을 확인할 수 있습니다. 손을 떼면 현재 잔액이 표시됩니다.');
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
