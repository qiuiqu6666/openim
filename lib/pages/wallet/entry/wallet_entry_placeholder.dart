import 'package:flutter/material.dart';

import '../home/wallet_home_tokens.dart';
import '../host/wallet_i18n.dart';
import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';
import 'wallet_entry_coordinator.dart';

/// Mirrors WalletHomeView's overview, action row and token list using the same
/// layout tokens. No controller, account values or transaction handlers exist
/// in this placeholder. Static shapes also respect reduced-motion settings.
class WalletEntryPlaceholder extends StatelessWidget {
  const WalletEntryPlaceholder(
      {super.key, required this.phase, required this.onRetry, this.message});

  final WalletEntryPhase phase;
  final Future<void> Function() onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final needsPassword = phase == WalletEntryPhase.needsPassword;
    return LayoutBuilder(builder: (context, constraints) {
      final gutter = constraints.maxWidth >= WalletHomeTokens.wideBreakpoint
          ? AppTokens.s8
          : AppTokens.s5;
      return RefreshIndicator(
          color: colors.blue,
          onRefresh: onRetry,
          child: SizedBox.expand(
              child: SingleChildScrollView(
            key: const ValueKey('wallet-entry-placeholder'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTokens.s2),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: WalletHomeTokens.maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      label: i18n.t(
                          zhHans: '正在加载钱包',
                          zhHant: '正在載入錢包',
                          en: 'Loading wallet',
                          ja: 'ウォレットを読み込み中',
                          ko: '지갑 불러오는 중'),
                      child: ExcludeSemantics(
                          child: ColoredBox(
                        color: colors.card,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppTokens.s4,
                              AppTokens.s2, AppTokens.s4, AppTokens.s4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(
                                  height: WalletHomeTokens.minTap,
                                  child: Row(children: [
                                    Expanded(child: _Bar(fraction: .46)),
                                    _IconSpace(),
                                    _IconSpace(),
                                  ])),
                              const _Bar(
                                  fraction: .56,
                                  height: WalletHomeTokens.totalAmount * 1.2),
                              const SizedBox(
                                  height: WalletHomeTokens.minTap,
                                  child: _Bar(
                                      fraction: .6,
                                      height: WalletHomeTokens.body)),
                              const SizedBox(height: AppTokens.s3),
                              Row(
                                  key:
                                      const ValueKey('wallet-skeleton-actions'),
                                  children: [
                                    for (var i = 0; i < 3; i++) ...[
                                      if (i != 0)
                                        const SizedBox(width: AppTokens.s4),
                                      const Expanded(
                                          child: _Bar(
                                              fraction: 1,
                                              height: WalletHomeTokens
                                                  .primaryActionHeight)),
                                    ]
                                  ]),
                            ],
                          ),
                        ),
                      )),
                    ),
                    if (needsPassword)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            gutter, AppTokens.s3, gutter, 0),
                        child: Column(children: [
                          Text(message ?? '',
                              key: const ValueKey('wallet-entry-message'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.subText,
                                  fontSize: WalletHomeTokens.body)),
                          const SizedBox(height: AppTokens.s2),
                          TextButton(
                            key: const ValueKey('wallet-entry-retry'),
                            onPressed: onRetry,
                            style: TextButton.styleFrom(
                                foregroundColor:
                                    WalletHomeTokens.accentText(context),
                                minimumSize: const Size(WalletHomeTokens.minTap,
                                    WalletHomeTokens.minTap)),
                            child: Text(i18n.t(
                                zhHans: '设置支付密码',
                                zhHant: '設定支付密碼',
                                en: 'Set payment password',
                                ja: '支払いパスワードを設定',
                                ko: '결제 비밀번호 설정')),
                          ),
                        ]),
                      ),
                    const SizedBox(height: AppTokens.s5),
                    ExcludeSemantics(
                        child: ColoredBox(
                      color: colors.card,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: gutter),
                        child: Column(children: [
                          const SizedBox(
                              height: WalletHomeTokens.minTap,
                              child: Row(children: [
                                Expanded(
                                    child: _Bar(
                                        fraction: .25,
                                        height: WalletHomeTokens.body)),
                                _IconSpace(),
                                _IconSpace(),
                              ])),
                          const Row(children: [
                            Expanded(child: _Bar(fraction: .5)),
                            Expanded(
                                child: _Bar(
                                    fraction: .7,
                                    align: Alignment.centerRight)),
                          ]),
                          const SizedBox(height: AppTokens.s3),
                          for (var i = 0; i < 3; i++) ...[
                            if (i != 0)
                              Divider(
                                  height: WalletHomeTokens.divider,
                                  thickness: WalletHomeTokens.divider,
                                  color: colors.line),
                            SizedBox(
                                key: ValueKey('wallet-skeleton-asset-$i'),
                                height: WalletHomeTokens.assetRowHeight,
                                child: const Row(children: [
                                  _Shape(
                                      width: WalletHomeTokens.coinLogo,
                                      height: WalletHomeTokens.coinLogo,
                                      round: true),
                                  SizedBox(width: AppTokens.s3),
                                  Expanded(
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                        _Bar(
                                            fraction: .48,
                                            height: WalletHomeTokens.rowAmount),
                                        SizedBox(height: AppTokens.s2),
                                        _Bar(fraction: .64),
                                      ])),
                                  Expanded(
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                        _Bar(
                                            fraction: .7,
                                            height: WalletHomeTokens.rowAmount,
                                            align: Alignment.centerRight),
                                        SizedBox(height: AppTokens.s2),
                                        _Bar(
                                            fraction: .45,
                                            align: Alignment.centerRight),
                                      ])),
                                ])),
                          ],
                          const SizedBox(height: AppTokens.s3),
                        ]),
                      ),
                    )),
                  ],
                ),
              ),
            ),
          )));
    });
  }
}

class _IconSpace extends StatelessWidget {
  const _IconSpace();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: WalletHomeTokens.minTap,
        child: Center(
            child: _Shape(
                width: WalletHomeTokens.icon, height: WalletHomeTokens.icon)),
      );
}

class _Bar extends StatelessWidget {
  const _Bar(
      {required this.fraction,
      this.height = WalletHomeTokens.caption,
      this.align = Alignment.centerLeft});
  final double fraction;
  final double height;
  final Alignment align;

  @override
  Widget build(BuildContext context) => Align(
        alignment: align,
        child: FractionallySizedBox(
            widthFactor: fraction, child: _Shape(height: height)),
      );
}

class _Shape extends StatelessWidget {
  const _Shape({this.width, required this.height, this.round = false});
  final double? width;
  final double height;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color.lerp(colors.card, colors.subText, .16),
        borderRadius: BorderRadius.circular(round ? height / 2 : AppTokens.rSm),
      ),
    );
  }
}
