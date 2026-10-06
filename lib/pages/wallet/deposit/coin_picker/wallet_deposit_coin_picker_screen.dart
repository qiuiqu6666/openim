import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../host/wallet_navigation.dart';
import '../../wallet_receive_screen.dart';
import '../../wallet_share_service.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_deposit_controller.dart';
import '../wallet_deposit_tokens.dart';
import 'wallet_deposit_coin.dart';
import 'widgets/wallet_deposit_coin_list.dart';
import 'widgets/wallet_deposit_coin_search.dart';

/// The deposit entry lists only currencies declared by the authenticated API.
class WalletDepositCoinPickerScreen extends StatefulWidget {
  const WalletDepositCoinPickerScreen({
    super.key,
    this.api,
    this.accountProvider,
    this.shareService,
  });

  final WalletFundApi? api;
  final String Function()? accountProvider;
  final WalletShareService? shareService;

  @override
  State<WalletDepositCoinPickerScreen> createState() =>
      _WalletDepositCoinPickerScreenState();
}

class _WalletDepositCoinPickerScreenState
    extends State<WalletDepositCoinPickerScreen> with WidgetsBindingObserver {
  late final WalletDepositController _controller;
  final _search = TextEditingController();
  final _focus = FocusNode();
  bool _foreground = true;
  bool _visible = false;
  bool _activationScheduled = false;
  bool _opening = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller = WalletDepositController(
        api: widget.api, accountProvider: widget.accountProvider);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
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

  void _syncActivation() =>
      _controller.setActive(_visible && _foreground && !_opening);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncActivation();
  }

  void _cancelSearch() {
    _search.clear();
    _focus.unfocus();
    setState(() => _query = '');
  }

  Future<void> _select(FundCurrency currency) async {
    if (_opening ||
        !_foreground ||
        !_visible ||
        !_controller.isCurrentAccount ||
        _controller.address?.currencies.contains(currency) != true) {
      return;
    }
    _opening = true;
    _focus.unfocus();
    _syncActivation();
    try {
      // The address route validates a fresh authenticated response and retains
      // ownership of its allocation polling, copying and sharing lifecycle.
      await openWalletPage<void>(
          context,
          WalletReceiveScreen(
              api: widget.api,
              accountProvider: widget.accountProvider,
              shareService: widget.shareService,
              requireSelectedCurrency: true,
              currency: currency));
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
        key: const ValueKey('wallet-deposit-coin-picker'),
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
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: WalletDepositTokens.maxWidth),
              child: Column(children: [
                WalletDepositCoinSearch(
                  controller: _search,
                  focusNode: _focus,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  onCancel: _cancelSearch,
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) => _body(i18n, colors),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppI18n i18n, WalletPageColors colors) {
    if (!_controller.isCurrentAccount) {
      return _message(
          key: 'wallet-deposit-coin-account-changed',
          icon: Icons.person_outline_rounded,
          message: i18n.t(
              zhHans: '账号已切换，请重新打开充值页面',
              zhHant: '帳號已切換，請重新開啟儲值頁面',
              en: 'Account changed. Reopen this deposit page.',
              ja: 'アカウントが変更されました。入金画面を開き直してください。',
              ko: '계정이 변경되었습니다. 입금 화면을 다시 여세요.'),
          colors: colors);
    }
    final address = _controller.address;
    if (address != null) {
      final coins = WalletDepositCoin.fromAddress(address)
          .where((coin) => coin.matches(_query))
          .toList(growable: false);
      if (coins.isNotEmpty) {
        return WalletDepositCoinList(
            coins: coins, onSelected: _select, searching: _query.isNotEmpty);
      }
      return _message(
          key: 'wallet-deposit-coin-empty',
          icon: Icons.search_off_rounded,
          message: i18n.t(
              zhHans: '未找到匹配币种',
              zhHant: '未找到符合的幣種',
              en: 'No matching coins',
              ja: '一致する通貨がありません',
              ko: '일치하는 코인이 없습니다'),
          colors: colors);
    }
    if (_controller.failed) {
      return _message(
          key: 'wallet-deposit-coin-error',
          icon: Icons.cloud_off_rounded,
          message: i18n.t(
              zhHans: '加载币种失败，请重试',
              zhHant: '載入幣種失敗，請重試',
              en: 'Could not load coins. Please retry.',
              ja: '通貨を読み込めませんでした。再試行してください。',
              ko: '코인을 불러오지 못했습니다. 다시 시도해 주세요.'),
          colors: colors,
          retry: i18n.t(
              zhHans: '重试', zhHant: '重試', en: 'Retry', ja: '再試行', ko: '다시 시도'));
    }
    return Center(
      child: CircularProgressIndicator(
          key: const ValueKey('wallet-deposit-coin-loading'),
          color: colors.blue),
    );
  }

  Widget _message({
    required String key,
    required IconData icon,
    required String message,
    required WalletPageColors colors,
    String? retry,
  }) =>
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s7),
          child: Column(
            key: ValueKey(key),
            children: [
              Icon(icon, size: 32, color: colors.subText),
              const SizedBox(height: AppTokens.s4),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: colors.subText)),
              if (retry != null)
                TextButton(
                    key: const ValueKey('wallet-deposit-coin-retry'),
                    onPressed: _controller.load,
                    child: Text(retry)),
            ],
          ),
        ),
      );
}
