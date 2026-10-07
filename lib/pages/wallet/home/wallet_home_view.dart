import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../deposit/coin_picker/wallet_deposit_coin_picker_screen.dart';
import '../host/wallet_i18n.dart';
import '../host/wallet_navigation.dart';
import '../order/wallet_order_events.dart';
import '../record/wallet_record_screen.dart';
import '../wallet_controller.dart';
import '../wallet_exchange_screen.dart';
import '../wallet_repository.dart';
import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';
import '../withdraw_coin_picker_screen.dart';
import 'wallet_home_tokens.dart';
import 'trend/wallet_asset_trend_panel.dart';
import 'widgets/wallet_asset_list.dart';
import 'widgets/wallet_balance_overview.dart';
import 'widgets/wallet_daily_profit_row.dart';
import 'widgets/wallet_home_action.dart';
import 'widgets/wallet_withdraw_type_sheet.dart';

/// Wallet home presentation. The public WalletScreen owns the controller and
/// tab lifecycle; this view only observes its state and starts existing routes.
class WalletHomeView extends StatefulWidget {
  const WalletHomeView({super.key, this.embeddedInMainTab = false});

  final bool embeddedInMainTab;

  @override
  State<WalletHomeView> createState() => _WalletHomeViewState();
}

class _WalletHomeViewState extends State<WalletHomeView> {
  // Keep the user's filter when the page is resized or the theme changes.
  final _assetsKey = GlobalKey(debugLabel: 'wallet-home-assets');
  bool _trendExpanded = false;
  bool _withdrawSheetOpen = false;

  Future<void> _openWithdrawal(BuildContext context) async {
    if (_withdrawSheetOpen) return;
    _withdrawSheetOpen = true;
    final owner = WalletOrderEvents.currentAccountKey;
    try {
      final kind = await showWalletWithdrawTypeSheet(context);
      if (!mounted ||
          !context.mounted ||
          kind == null ||
          owner != WalletOrderEvents.currentAccountKey) {
        return;
      }
      await openWalletPage<void>(
          context, WithdrawCoinPickerScreen(initialTargetKind: kind),
          activityPage: 'wallet_withdraw');
    } finally {
      _withdrawSheetOpen = false;
    }
  }

  void _openRecords(BuildContext context, [CoinDto? coin]) {
    final code = coin == null
        ? null
        : coin.code.isNotEmpty
            ? coin.code
            : switch (coin.type) {
                CoinType.usdt => 'USDT',
                CoinType.trx => 'TRX',
                CoinType.cny => '99',
              };
    openWalletPage<void>(
      context,
      WalletRecordScreen(initialCoin: code),
      activityPage: 'wallet_history',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final content = ColoredBox(
      color: colors.bg,
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= WalletHomeTokens.wideBreakpoint;
        final gutter = wide ? AppTokens.s8 : AppTokens.s5;
        return RefreshIndicator(
          color: colors.blue,
          onRefresh: () => context.read<WalletController>().load(force: true),
          // Short content still needs a full-height pull-to-refresh target.
          child: SizedBox.expand(
            child: SingleChildScrollView(
              key: const PageStorageKey('wallet-home-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                0,
                AppTokens.s2,
                0,
                AppTokens.s5,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: WalletHomeTokens.maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _overview(context),
                      const SizedBox(height: AppTokens.s5),
                      _assets(context, gutter: gutter),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
    if (widget.embeddedInMainTab) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: walletPageOverlayStyle(context),
        child: content,
      );
    }
    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: colors.bg,
        appBar: AppBar(
          leading:
              Navigator.of(context).canPop() ? const AppBackButton() : null,
          backgroundColor: colors.bg,
          foregroundColor: colors.text,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(AppI18n.of(context).t(
              zhHans: '钱包', zhHant: '錢包', en: 'Wallet', ja: 'ウォレット', ko: '지갑')),
        ),
        body: SafeArea(top: false, child: content),
      ),
    );
  }

  Widget _assets(BuildContext context, {required double gutter}) =>
      WalletAssetList(
        key: _assetsKey,
        horizontalPadding: gutter,
        onOpenCoin: (coin) => _openRecords(context, coin),
      );

  Widget _overview(BuildContext context) {
    final i18n = AppI18n.of(context);
    return ColoredBox(
      color: WalletPageColors.of(context).card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.s4, AppTokens.s2, AppTokens.s4, AppTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WalletBalanceOverview(
              onRecords: () => _openRecords(context),
              onOverview: () {
                setState(() => _trendExpanded = !_trendExpanded);
                context
                    .read<WalletController>()
                    .setTrendEnabled(_trendExpanded);
              },
              overviewExpanded: _trendExpanded,
            ),
            const WalletDailyProfitRow(),
            if (_trendExpanded)
              WalletAssetTrendPanel(
                currency: 'CNY',
              ),
            const SizedBox(height: AppTokens.s3),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: WalletHomeAction(
                      key: const ValueKey('wallet-action-receive'),
                      label: i18n.t(
                          zhHans: '充值',
                          zhHant: '儲值',
                          en: 'Deposit',
                          ja: '入金',
                          ko: '입금'),
                      primary: true,
                      onTap: () => openWalletPage<void>(
                        context,
                        const WalletDepositCoinPickerScreen(),
                        activityPage: 'wallet_receive',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s4),
                  Expanded(
                    child: WalletHomeAction(
                      key: const ValueKey('wallet-action-transfer'),
                      label: i18n.t(
                          zhHans: '提现',
                          zhHant: '提現',
                          en: 'Withdraw',
                          ja: '出金',
                          ko: '출금'),
                      onTap: () => _openWithdrawal(context),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s4),
                  Expanded(
                    child: WalletHomeAction(
                      key: const ValueKey('wallet-action-swap'),
                      label: i18n.t(
                          zhHans: '划转',
                          zhHant: '劃轉',
                          en: 'Transfer',
                          ja: '振替',
                          ko: '이체'),
                      onTap: () => openWalletPage<void>(
                        context,
                        const WalletExchangeScreen(),
                        activityPage: 'wallet_swap',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
