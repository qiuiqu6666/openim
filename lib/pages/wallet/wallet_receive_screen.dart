import 'package:flutter/material.dart';

import 'data/wallet_fund_api.dart';
import 'data/wallet_fund_repository.dart';
import 'deposit/wallet_deposit_controller.dart';
import 'deposit/wallet_deposit_tokens.dart';
import 'deposit/widgets/wallet_deposit_help_sheet.dart';
import 'deposit/widgets/wallet_deposit_ready_content.dart';
import 'deposit/widgets/wallet_deposit_share_sheet.dart';
import 'home/widgets/wallet_overview_icon.dart';
import 'host/wallet_i18n.dart';
import 'host/wallet_navigation.dart';
import 'host/wallet_toast.dart';
import 'wallet_asset_record_screen.dart';
import 'wallet_share_service.dart';
import 'widgets/wallet_99chat_tokens.dart';
import 'widgets/wallet_page_colors.dart';

/// Compatibility route. Addresses are always fetched independently from the
/// authenticated deposit endpoint; a legacy caller-supplied addr is not used.
class WalletReceiveScreen extends StatefulWidget {
  const WalletReceiveScreen(
      {super.key,
      this.addr = '',
      this.api,
      this.accountProvider,
      this.shareService,
      this.requireSelectedCurrency = false,
      this.currency = FundCurrency.usdt});
  final String addr;
  final WalletFundApi? api;
  final String Function()? accountProvider;
  final WalletShareService? shareService;
  final FundCurrency currency;
  final bool requireSelectedCurrency;

  @override
  State<WalletReceiveScreen> createState() => _WalletReceiveScreenState();
}

class _WalletReceiveScreenState extends State<WalletReceiveScreen>
    with WidgetsBindingObserver {
  late final WalletDepositController _controller;
  late final WalletShareService _share;
  bool _routeVisible = false;
  bool _foreground = true;
  late FundCurrency _currency;

  bool get _canUseSelectedAddress =>
      _controller.canUseAddress &&
      _controller.address!.currencies.contains(_currency);

  @override
  void initState() {
    super.initState();
    _currency = widget.currency;
    _controller = WalletDepositController(
        api: widget.api,
        accountProvider: widget.accountProvider,
        enabled: widget.currency != FundCurrency.bi99);
    _share = widget.shareService ?? WalletShareService();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible = (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    _updateActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateActivity();
  }

  void _updateActivity() {
    if (!_routeVisible || !_foreground) {
      _controller.setActive(false);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _routeVisible && _foreground) _controller.setActive(true);
    });
  }

  Future<void> _copy() async {
    if (!_canUseSelectedAddress) return;
    await _copyValue(_controller.address!.address);
  }

  Future<void> _copyValue(String value) async {
    if (value.isEmpty) return;
    final result = await _share.copyAddr(value);
    if (!mounted || !_controller.isCurrentAccount) return;
    final i18n = AppI18n.of(context);
    ToastUtils.toast(result == WalletCopyResult.success
        ? i18n.t(
            zhHans: '地址已复制',
            zhHant: '地址已複製',
            en: 'Address copied',
            ja: 'アドレスをコピーしました',
            ko: '주소가 복사되었습니다')
        : i18n.t(
            zhHans: '复制失败，请重试',
            zhHant: '複製失敗，請重試',
            en: 'Copy failed. Please retry.',
            ja: 'コピーに失敗しました。再試行してください。',
            ko: '복사에 실패했습니다. 다시 시도해 주세요.'));
  }

  Future<void> _openShare() async {
    if (!_canUseSelectedAddress) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        useRootNavigator: true,
        builder: (_) => WalletDepositShareSheet(
            controller: _controller, currency: _currency, service: _share));
  }

  void _openHelp() {
    if (!_controller.isCurrentAccount) return;
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useRootNavigator: true,
        builder: (_) => WalletDepositHelpSheet(
            currency: _currency, address: _controller.address));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final colors = WalletPageColors.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final address = _controller.address;
        if (address != null &&
            !widget.requireSelectedCurrency &&
            address.currencies.isNotEmpty &&
            !address.currencies.contains(_currency)) {
          _currency = address.currencies.first;
        }
        return wrapWalletPage(
          context,
          Scaffold(
            backgroundColor: colors.card,
            appBar: AppBar(
              backgroundColor: colors.card,
              foregroundColor: colors.text,
              leading: const AppBackButton(),
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              title: _title(i18n, colors),
              actions: [
                IconButton(
                  key: const ValueKey('wallet-deposit-help'),
                  tooltip: i18n.t(
                      zhHans: '充值帮助',
                      zhHant: '儲值說明',
                      en: 'Deposit help',
                      ja: '入金ヘルプ',
                      ko: '입금 도움말'),
                  onPressed: _openHelp,
                  icon: const Icon(Icons.help_outline_rounded),
                ),
                IconButton(
                  key: const ValueKey('wallet-deposit-records'),
                  tooltip: i18n.t(
                      zhHans: '充值记录',
                      zhHant: '儲值記錄',
                      en: 'Deposit records',
                      ja: '入金履歴',
                      ko: '입금 기록'),
                  onPressed: () => openWalletPage<void>(
                    context,
                    WalletDepositRecordScreen(
                      repository: WalletFundRepository(
                          api: widget.api,
                          accountProvider: widget.accountProvider),
                    ),
                    activityPage: 'wallet_history',
                  ),
                  icon: const WalletOverviewIcon.history(),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      maxWidth: WalletDepositTokens.maxWidth),
                  child: RefreshIndicator(
                    onRefresh: _controller.load,
                    child: _canUseSelectedAddress
                        ? WalletDepositReadyContent(
                            address: address!,
                            currency: _currency,
                            onCopy: _copy,
                            onShare: _openShare,
                            onNetworkInfo: _openHelp,
                          )
                        : _status(i18n, colors),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _title(AppI18n i18n, WalletPageColors colors) {
    final text = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            i18n.t(
                zhHans: '充值', zhHant: '儲值', en: 'Deposit', ja: '入金', ko: '입금'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: colors.text),
          ),
        ),
        const SizedBox(width: AppTokens.s3),
        Text(_currency == FundCurrency.bi99 ? '99' : _currency.code,
            key: const ValueKey('wallet-deposit-title-coin'),
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: colors.text)),
      ],
    );
    if (widget.requireSelectedCurrency || !_canUseSelectedAddress) return text;
    return PopupMenuButton<FundCurrency>(
      key: const ValueKey('wallet-deposit-currency'),
      initialValue: _currency,
      onSelected: (value) {
        if (_controller.isCurrentAccount &&
            _controller.address?.currencies.contains(value) == true) {
          setState(() => _currency = value);
        }
      },
      itemBuilder: (_) => [
        for (final item in _controller.address!.currencies)
          PopupMenuItem(value: item, child: Text(item.code)),
      ],
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: WalletDepositTokens.minTap),
        child: text,
      ),
    );
  }

  Widget _status(AppI18n i18n, WalletPageColors colors) => ListView(
        key: const ValueKey('wallet-deposit-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTokens.s7),
        children: [
          const SizedBox(height: AppTokens.s10),
          if (_controller.loading) ...[
            Center(
                child: CircularProgressIndicator(
                    key: const ValueKey('wallet-deposit-loading'),
                    color: colors.blue)),
            const SizedBox(height: AppTokens.s5),
          ],
          Text(
            _message(i18n),
            key: ValueKey(_controller.failed
                ? 'wallet-deposit-error'
                : 'wallet-deposit-pending'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: WalletDepositTokens.body, color: colors.subText),
          ),
          if (_controller.failed)
            TextButton(
              key: const ValueKey('wallet-deposit-retry'),
              onPressed: _controller.load,
              child: Text(i18n.t(
                  zhHans: '重试',
                  zhHant: '重試',
                  en: 'Retry',
                  ja: '再試行',
                  ko: '다시 시도')),
            ),
        ],
      );

  String _message(AppI18n i18n) {
    if (!_controller.enabled) {
      return i18n.t(
          zhHans: '99币不支持链上充值',
          zhHant: '99幣不支援鏈上儲值',
          en: '99 does not support on-chain deposits',
          ja: '99はオンチェーン入金に対応していません',
          ko: '99는 온체인 입금을 지원하지 않습니다');
    }
    if (!_controller.isCurrentAccount) {
      return i18n.t(
          zhHans: '账号已切换，请重新打开充值页面',
          zhHant: '帳號已切換，請重新開啟儲值頁面',
          en: 'Account changed. Reopen this deposit page.',
          ja: 'アカウントが変更されました。入金画面を開き直してください。',
          ko: '계정이 변경되었습니다. 입금 화면을 다시 여세요.');
    }
    if (_controller.failed) return _controller.failureMessage;
    if (widget.requireSelectedCurrency &&
        _controller.address != null &&
        !_controller.address!.currencies.contains(_currency)) {
      return i18n.t(
          zhHans: '该币种暂不支持充值，请返回重新选择',
          zhHant: '此幣種暫不支援儲值，請返回重新選擇',
          en: 'This coin is unavailable for deposits. Go back and choose again.',
          ja: 'この通貨は現在入金できません。戻って選び直してください。',
          ko: '이 코인은 현재 입금할 수 없습니다. 돌아가서 다시 선택하세요.');
    }
    return i18n.t(
        zhHans: '充值地址生成中',
        zhHant: '儲值地址產生中',
        en: 'Generating deposit address',
        ja: '入金アドレスを生成中',
        ko: '입금 주소 생성 중');
  }
}
