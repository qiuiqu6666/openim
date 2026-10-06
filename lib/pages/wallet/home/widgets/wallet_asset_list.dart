import 'dart:math' as math;
import 'wallet_asset_value_sort.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../host/app_empty_state.dart';
import '../../host/wallet_i18n.dart';
import '../../wallet_controller.dart';
import '../../wallet_repository.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_home_tokens.dart';
import '../wallet_amount_display.dart';
import '../../widgets/wallet_coin_logo.dart';

class WalletAssetList extends StatefulWidget {
  const WalletAssetList({
    super.key,
    required this.onOpenCoin,
    this.horizontalPadding = AppTokens.s5,
  });

  final ValueChanged<CoinDto> onOpenCoin;
  final double horizontalPadding;

  @override
  State<WalletAssetList> createState() => _WalletAssetListState();
}

class _WalletAssetListState extends State<WalletAssetList> {
  bool? _descending;
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final source =
        context.select<WalletController, List<CoinDto>>((c) => c.coins);
    final showBal = context.select<WalletController, bool>((c) => c.showBal);
    final loading = context.select<WalletController, bool>((c) => c.loading);
    // A stable partition preserves the backend order within either group.
    final ordered = <CoinDto>[
      ...source.where((c) => c.platformCoin),
      ...source.where((c) => !c.platformCoin),
    ];
    final visible = _descending == null
        ? ordered
        : sortWalletAssetsByValue(source, descending: _descending!);
    final cs = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    // Controller.loading is true only until the first successful snapshot.
    // Retrying an unavailable wallet can already have unknown product rows.
    final initiallyLoading = loading;

    return Material(
      key: const ValueKey('wallet-assets-section'),
      color: cs.card,
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  i18n.t(
                    zhHans: '代币',
                    zhHant: '代幣',
                    en: 'Tokens',
                    ja: 'トークン',
                    ko: '토큰',
                  ),
                  style: TextStyle(
                      fontSize: WalletHomeTokens.body,
                      fontWeight: FontWeight.w600,
                      color: cs.text),
                ),
              ),
              _filter(context, enabled: !initiallyLoading),
              IconButton(
                key: const ValueKey('wallet-assets-toggle'),
                isSelected: _expanded,
                tooltip: _expanded
                    ? i18n.t(
                        zhHans: '收起代币',
                        zhHant: '收起代幣',
                        en: 'Hide tokens',
                        ja: 'トークンを閉じる',
                        ko: '토큰 접기')
                    : i18n.t(
                        zhHans: '展开代币',
                        zhHant: '展開代幣',
                        en: 'Show tokens',
                        ja: 'トークンを開く',
                        ko: '토큰 펼치기'),
                onPressed: () => setState(() => _expanded = !_expanded),
                style: _iconStyle(context),
                icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: WalletHomeTokens.icon),
              ),
            ]),
            if (_expanded) ...[
              _columnLabels(context),
              const SizedBox(height: AppTokens.s3),
              Container(
                key: const ValueKey('wallet-assets-list'),
                child: initiallyLoading
                    ? _LoadingAssets(
                        message: i18n.t(
                        zhHans: '正在加载资产',
                        zhHant: '正在載入資產',
                        en: 'Loading assets',
                        ja: '資産を読み込み中',
                        ko: '자산 불러오는 중',
                      ))
                    : visible.isEmpty
                        ? AppEmptyState(
                            key: const ValueKey('wallet-home-empty'),
                            imageWidth: WalletHomeTokens.emptyIllustration,
                            padding: const EdgeInsets.all(AppTokens.s7),
                            message: i18n.t(
                              zhHans: '暂无资产',
                              zhHant: '暫無資產',
                              en: 'No assets yet',
                              ja: '資産はまだありません',
                              ko: '아직 자산이 없습니다',
                            ),
                          )
                        : Column(children: [
                            for (var index = 0;
                                index < visible.length;
                                index++) ...[
                              if (index != 0)
                                Divider(
                                  height: WalletHomeTokens.divider,
                                  thickness: WalletHomeTokens.divider,
                                  color: cs.line,
                                ),
                              _AssetRow(
                                item: visible[index],
                                showBal: showBal,
                                onTap: () => widget.onOpenCoin(visible[index]),
                              ),
                            ],
                          ]),
              ),
              const SizedBox(height: AppTokens.s3),
            ],
          ],
        ),
      ),
    );
  }

  Widget _columnLabels(BuildContext context) {
    final i18n = AppI18n.of(context);
    final style = TextStyle(
        fontSize: WalletHomeTokens.caption,
        color: WalletHomeTokens.muted(context));
    final nameLabel = i18n.t(
        zhHans: '名称/数量',
        zhHant: '名稱/數量',
        en: 'Name/quantity',
        ja: '名称/数量',
        ko: '이름/수량');
    final valueLabel = i18n.t(
        zhHans: '价值/现货收益',
        zhHant: '價值/現貨收益',
        en: 'Value/spot earnings',
        ja: '評価額/現物收益',
        ko: '가치/현물 수익');
    final name = Text(
      nameLabel,
      key: const ValueKey('wallet-assets-column-name'),
      style: style,
    );
    final value = Text(
      valueLabel,
      key: const ValueKey('wallet-assets-column-value'),
      textAlign: TextAlign.end,
      style: style,
    );
    return LayoutBuilder(builder: (context, constraints) {
      final valueWidth = _textWidth(context, valueLabel, style);
      final requiredWidth =
          _textWidth(context, nameLabel, style) + valueWidth + AppTokens.s4;
      if (requiredWidth > constraints.maxWidth) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [name, const SizedBox(height: AppTokens.s2), value],
        );
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: name),
        const SizedBox(width: AppTokens.s4),
        SizedBox(width: valueWidth, child: value),
      ]);
    });
  }

  Widget _filter(BuildContext context, {required bool enabled}) {
    final label = AppI18n.of(context).t(
      zhHans: '按价值排序',
      zhHant: '按價值排序',
      en: 'Sort by value',
      ja: '評価額で並べ替え',
      ko: '가치순 정렬',
    );
    return Semantics(
      toggled: _descending != null,
      child: IconButton(
        key: const ValueKey('wallet-assets-filter'),
        tooltip: label,
        isSelected: _descending != null,
        onPressed: enabled
            ? () => setState(() => _descending = _descending != true)
            : null,
        style: _iconStyle(context, selected: _descending != null),
        icon: Icon(
            _descending == null
                ? Icons.filter_list_rounded
                : _descending!
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
            size: WalletHomeTokens.icon),
      ),
    );
  }

  ButtonStyle _iconStyle(BuildContext context, {bool selected = false}) =>
      IconButton.styleFrom(
        minimumSize: const Size.square(WalletHomeTokens.minTap),
        foregroundColor: selected
            ? WalletHomeTokens.accentText(context)
            : WalletHomeTokens.muted(context),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.rSm)),
      );
}

class _LoadingAssets extends StatelessWidget {
  const _LoadingAssets({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return Padding(
      key: const ValueKey('wallet-home-loading'),
      padding: const EdgeInsets.all(AppTokens.s8),
      child: Column(
        children: [
          SizedBox.square(
            dimension: WalletHomeTokens.progressSize,
            child: CircularProgressIndicator(
              color: cs.blue,
              strokeWidth: WalletHomeTokens.progressStroke,
            ),
          ),
          const SizedBox(height: AppTokens.s5),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: WalletHomeTokens.muted(context),
                  fontSize: WalletHomeTokens.body)),
        ],
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow(
      {required this.item, required this.showBal, required this.onTap});
  final CoinDto item;
  final bool showBal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final balance = showBal ? walletAmountDisplay(item.bal) : '******';
    final fiat = showBal ? walletAmountDisplay(item.fiat) : '******';
    final code = _coinCode(item);
    final nameStyle = TextStyle(
        color: cs.text,
        fontSize: WalletHomeTokens.rowAmount,
        fontWeight: FontWeight.w600);
    final detailStyle = TextStyle(
        color: WalletHomeTokens.muted(context),
        fontSize: WalletHomeTokens.caption);
    final amountStyle = TextStyle(
      color: cs.text,
      fontSize: WalletHomeTokens.rowAmount,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final value = Text(fiat,
        key: ValueKey('wallet-asset-value-$code'),
        textAlign: TextAlign.end,
        style: amountStyle);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_known(item.name), style: nameStyle),
        const SizedBox(height: AppTokens.s2),
        Text(balance,
            key: ValueKey('wallet-asset-quantity-$code'), style: detailStyle),
      ],
    );

    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('wallet-asset-$code'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: WalletHomeTokens.assetRowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
            child: LayoutBuilder(builder: (context, constraints) {
              final amountWidth = _textWidth(context, fiat, amountStyle);
              final nameWidth = math.max(
                  _textWidth(context, _known(item.name), nameStyle),
                  _textWidth(context, balance, detailStyle));
              const chromeWidth =
                  WalletHomeTokens.coinLogo + AppTokens.s4 + AppTokens.s5;
              final stacked =
                  amountWidth + nameWidth + chromeWidth > constraints.maxWidth;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      WalletCoinLogo(type: item.type, logoUrl: item.logoUrl),
                      const SizedBox(width: AppTokens.s4),
                      Expanded(child: identity),
                    ]),
                    const SizedBox(height: AppTokens.s3),
                    value,
                  ],
                );
              }
              return Row(children: [
                WalletCoinLogo(type: item.type, logoUrl: item.logoUrl),
                const SizedBox(width: AppTokens.s4),
                Expanded(child: identity),
                const SizedBox(width: AppTokens.s5),
                SizedBox(width: amountWidth, child: value),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  static String _known(String value) => value.trim().isEmpty ? '--' : value;

  static String _coinCode(CoinDto item) {
    if (item.code.isNotEmpty) return item.code;
    return switch (item.type) {
      CoinType.usdt => 'USDT',
      CoinType.trx => 'TRX',
      CoinType.cny => '99',
    };
  }
}

double _textWidth(BuildContext context, String value, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
        text: value, style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}
