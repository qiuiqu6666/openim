import 'dart:async';

import 'package:flutter/material.dart';

import '../../../fund/fund_send_page.dart';
import '../../../../services/fund_api.dart';
import '../../data/wallet_session_source.dart';
import '../../data/wallet_operation_coordinator.dart';
import '../../host/wallet_i18n.dart';
import '../../host/wallet_navigation.dart';
import '../../wallet_controller.dart';
import '../../wallet_repository.dart';
import '../../wallet_repository_provider.dart';
import '../../order/wallet_order_events.dart';
import '../../widgets/coin_picker/wallet_coin_picker_list.dart';
import '../../widgets/coin_picker/wallet_coin_picker_search.dart';
import '../../widgets/coin_picker/wallet_coin_picker_tokens.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../../withdraw_transfer_target_validator.dart';
import '../form/wallet_chain_withdrawal_screen.dart';
import 'wallet_withdraw_coin_labels.dart';
import 'widgets/wallet_withdraw_coin_row.dart';

/// Existing transfer/withdrawal entry backed by the authenticated wallet source.
class WithdrawCoinPickerScreen extends StatefulWidget {
  const WithdrawCoinPickerScreen({
    super.key,
    this.initialTargetKind = WithdrawTransferTargetKind.friend,
    this.repository,
  });

  final WithdrawTransferTargetKind initialTargetKind;
  final WalletRepository? repository;

  @override
  State<WithdrawCoinPickerScreen> createState() =>
      _WithdrawCoinPickerScreenState();
}

class _WithdrawCoinPickerScreenState extends State<WithdrawCoinPickerScreen>
    with WidgetsBindingObserver {
  late final WalletRepository _repository;
  late final WalletController _controller;
  final _search = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  bool _visible = false;
  bool _foreground = true;
  bool _opening = false;
  bool _started = false;
  bool _activationScheduled = false;

  bool get _isCurrentAccount =>
      _repository is! WalletSessionSource ||
      (_repository as WalletSessionSource).isCurrentAccount;

  bool get _active => _visible && _foreground && !_opening;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? createWalletRepository();
    _controller = WalletController(repo: _repository)..setActive(false);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    if (_activationScheduled) return;
    _activationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activationScheduled = false;
      if (mounted) _syncActivation();
    });
  }

  void _syncActivation() {
    if (!_isCurrentAccount) {
      _controller.setActive(false);
      if (mounted) setState(() {});
      return;
    }
    _controller.setActive(_active);
    if (_active && !_started) {
      _started = true;
      unawaited(_controller.load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncActivation();
  }

  List<CoinDto> _enabledCoins() => _controller.coins
      .where((coin) =>
          coin.withdrawEnabled &&
          (widget.initialTargetKind != WithdrawTransferTargetKind.chain ||
              const ['USDT', 'TRX'].contains(coin.code.toUpperCase())))
      .toList(growable: false);

  void _cancelSearch() {
    _search.clear();
    _focus.unfocus();
    setState(() => _query = '');
  }

  Future<void> _reload() async {
    if (!mounted || !_active || !_isCurrentAccount) return;
    await _controller.load(force: true);
  }

  Future<void> _select(CoinDto item) async {
    if (!mounted) return;
    if (!_active || !_isCurrentAccount || _controller.loadFailed) {
      if (mounted && !_isCurrentAccount) setState(() {});
      return;
    }
    final code = WalletWithdrawCoinLabels.code(item);
    CoinDto? current;
    for (final coin in _enabledCoins()) {
      if (WalletWithdrawCoinLabels.code(coin) == code) {
        current = coin;
        break;
      }
    }
    if (current == null) return;
    final i18n = AppI18n.of(context);
    final network = current.platformCoin
        ? i18n.t(
            zhHans: '平台币',
            zhHant: '平台幣',
            en: 'Platform coin',
            ja: 'プラットフォーム通貨',
            ko: '플랫폼 코인')
        : 'Tron(TRC20)';
    _opening = true;
    final accountKey = WalletOrderEvents.currentAccountKey;
    _focus.unfocus();
    _syncActivation();
    try {
      if (widget.initialTargetKind == WithdrawTransferTargetKind.friend) {
        final order = await openWalletPage<FundOrder>(
          context,
          FundSendPage(
              isRedPacket: false,
              internalWithdrawal: true,
              initialCurrency: walletFundCurrency(current.code)),
          activityPage: 'wallet_transfer',
        );
        if (order != null &&
            WalletOrderEvents.currentAccountKey == accountKey) {
          WalletOrderEvents.notifyBalance(accountKey: accountKey);
          WalletOrderEvents.notifyRecord(accountKey: accountKey);
        }
      } else {
        await openWalletPage<void>(
          context,
          WalletChainWithdrawalScreen(
              coin: current, payMethod: current.toPayMethod(net: network)),
          activityPage: 'wallet_withdraw',
        );
      }
    } finally {
      _opening = false;
      if (mounted) _syncActivation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
        key: const ValueKey('wallet-withdraw-coin-picker'),
        backgroundColor: colors.card,
        appBar: AppBar(
          backgroundColor: colors.card,
          foregroundColor: colors.text,
          systemOverlayStyle: walletPageOverlayStyle(context),
          leading: const AppBackButton(),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Text(
            i18n.t(
                zhHans: '选择币种',
                zhHant: '選擇幣種',
                en: 'Select coin',
                ja: '通貨を選択',
                ko: '코인 선택'),
            style: const TextStyle(
                fontSize: WalletCoinPickerTokens.titleFont,
                fontWeight: FontWeight.w600),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: WalletCoinPickerTokens.maxWidth),
              child: Column(children: [
                WalletCoinPickerSearch(
                  keyPrefix: 'wallet-withdraw-coin',
                  controller: _search,
                  focusNode: _focus,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  onCancel: _cancelSearch,
                  hintText: i18n.t(
                      zhHans: '输入币种名称或代码',
                      zhHant: '輸入幣種名稱或代碼',
                      en: 'Coin name or code',
                      ja: '通貨名またはコードを入力',
                      ko: '코인 이름 또는 코드 입력'),
                ),
                Expanded(
                  child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, __) => _body(i18n, colors)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppI18n i18n, WalletPageColors colors) {
    if (!_isCurrentAccount) {
      return _message(
          'wallet-withdraw-coin-account-changed',
          Icons.person_outline_rounded,
          i18n.t(
              zhHans: '账号已切换，请重新打开页面',
              zhHant: '帳號已切換，請重新開啟頁面',
              en: 'Account changed. Reopen this page.',
              ja: 'アカウントが変更されました。画面を開き直してください。',
              ko: '계정이 변경되었습니다. 화면을 다시 여세요.'),
          colors);
    }
    if (!_started || _controller.loading) {
      return Center(
          child: CircularProgressIndicator(
              key: const ValueKey('wallet-withdraw-coin-loading'),
              color: colors.blue));
    }
    if (_controller.loadFailed) {
      return _message(
          'wallet-withdraw-coin-error',
          Icons.cloud_off_rounded,
          i18n.t(
              zhHans: '加载币种失败，请重试',
              zhHant: '載入幣種失敗，請重試',
              en: 'Could not load coins. Please retry.',
              ja: '通貨を読み込めませんでした。再試行してください。',
              ko: '코인을 불러오지 못했습니다. 다시 시도해 주세요.'),
          colors,
          retry: true);
    }
    final coins = _enabledCoins()
        .where((coin) => WalletWithdrawCoinLabels.matches(coin, _query, i18n))
        .toList(growable: false);
    if (coins.isEmpty) {
      return _message(
          'wallet-withdraw-coin-empty',
          Icons.search_off_rounded,
          _query.isNotEmpty
              ? i18n.t(
                  zhHans: '未找到匹配币种',
                  zhHant: '未找到符合的幣種',
                  en: 'No matching coins',
                  ja: '一致する通貨がありません',
                  ko: '일치하는 코인이 없습니다')
              : i18n.t(
                  zhHans: '暂无可用币种',
                  zhHant: '暫無可用幣種',
                  en: 'No available coins',
                  ja: '利用できる通貨がありません',
                  ko: '사용 가능한 코인이 없습니다'),
          colors);
    }
    return WalletCoinPickerList<CoinDto>(
      keyPrefix: 'wallet-withdraw-coin',
      items: coins,
      codeOf: WalletWithdrawCoinLabels.code,
      searching: _query.isNotEmpty,
      rowBuilder: (coin) =>
          WalletWithdrawCoinRow(coin: coin, onTap: () => _select(coin)),
    );
  }

  Widget _message(
          String key, IconData icon, String text, WalletPageColors colors,
          {bool retry = false}) =>
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s7),
          child: Column(
            key: ValueKey(key),
            children: [
              Icon(icon, size: AppTokens.s8, color: colors.subText),
              const SizedBox(height: AppTokens.s4),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: WalletCoinPickerTokens.bodyFont,
                      color: colors.subText)),
              if (retry)
                TextButton(
                    key: const ValueKey('wallet-withdraw-coin-retry'),
                    onPressed: _reload,
                    child: Text(AppI18n.of(context).t(
                        zhHans: '重试',
                        zhHant: '重試',
                        en: 'Retry',
                        ja: '再試行',
                        ko: '다시 시도'))),
            ],
          ),
        ),
      );
}
