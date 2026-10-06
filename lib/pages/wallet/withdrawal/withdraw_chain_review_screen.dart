import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'wallet_withdrawal_feedback.dart';
import 'package:openim_common/openim_common.dart' show DataSp;
import '../../../services/fund_api.dart' show FundApiException;

import '../../mine/settings/settings_service.dart';
import '../../fund/withdrawal_security/withdrawal_security.dart';

import '../data/wallet_fund_api.dart';
import '../data/currency_rules/wallet_withdrawal_policy.dart';
import '../data/wallet_operation_coordinator.dart';
import '../data/wallet_operation_pending_store.dart';
import '../widgets/wallet_coin_logo.dart';
import '../host/wallet_navigation.dart';
import '../operations/wallet_payment_password_navigation.dart';
import '../order/wallet_order.dart';
import '../pay_auth_helper.dart';
import '../wallet_repository.dart';
import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';
import '../widgets/wallet_tip.dart';
import '../host/wallet_i18n.dart';
import '../widgets/currency_rules/wallet_withdrawal_policy_labels.dart';
import 'wallet_withdrawal_review_labels.dart';
import 'widgets/wallet_withdrawal_rule_summary.dart';
import 'widgets/wallet_withdrawal_pending_actions.dart';

class WithdrawChainReviewScreen extends StatefulWidget {
  const WithdrawChainReviewScreen({
    super.key,
    required this.coin,
    required this.payMethod,
    required this.toAddress,
    required this.amountMinor,
    this.api,
    this.coordinator,
    this.settingsService,
    this.securityAuthorizer,
  });

  final CoinDto coin;
  final WalletPayMethodDto payMethod;
  final String toAddress;
  final int amountMinor;
  final WalletFundApi? api;
  final WalletOperationCoordinator? coordinator;
  final SettingsService? settingsService;
  final Future<FundSecurityProof?> Function(
      BuildContext context, FundSecurityRequest request)? securityAuthorizer;

  @override
  State<WithdrawChainReviewScreen> createState() =>
      _WithdrawChainReviewScreenState();
}

class _WithdrawChainReviewScreenState extends State<WithdrawChainReviewScreen>
    with WidgetsBindingObserver {
  late final WalletOperationCoordinator _operation;
  late final String? _token;
  bool _foreground = true;
  bool _loading = true, _sheetOpen = false;
  bool _loadInProgress = false;
  String? _loadError;
  List<FundBalance> _balances = const [];
  WalletCurrencyRule? _rule;

  bool get _currentSession =>
      _operation.sameAccount &&
      (widget.coordinator != null ||
          (_token?.isNotEmpty == true && _token == DataSp.chatToken));
  bool get _canAuthorize => mounted && _foreground && _currentSession;
  bool get _canFeedback =>
      _canAuthorize && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _token = DataSp.chatToken;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _operation = widget.coordinator ??
        WalletOperationCoordinator(
            kind: WalletOperationKind.withdraw, api: widget.api);
    _operation.addListener(_changed);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  void _changed() {
    if (mounted && _currentSession) setState(() {});
  }

  FundAmount get _amount {
    if (_operation.draft != null) return _operation.draft!.amount;
    final currency = walletFundCurrency(widget.payMethod.code.isEmpty
        ? widget.payMethod.coin
        : widget.payMethod.code);
    if (currency == FundCurrency.bi99 ||
        widget.amountMinor <= 0 ||
        widget.payMethod.scale != currency.decimals) {
      throw const FormatException('请选择 USDT/TRX 并输入有效提现金额');
    }
    return FundAmount.parse(
        WalletAmount.formatMinor(widget.amountMinor, currency.decimals),
        currency);
  }

  String get _address => _operation.draft?.toAddress ?? widget.toAddress.trim();
  FundBalance? get _balance => _balances
      .where((balance) => balance.currency == _amount.currency)
      .firstOrNull;

  WalletWithdrawalReviewLabels get _labels =>
      WalletWithdrawalReviewLabels(AppI18n.of(context));
  WalletWithdrawalPolicyLabels get _policyLabels =>
      WalletWithdrawalPolicyLabels(AppI18n.of(context));

  WalletWithdrawalPolicy? get _policy =>
      _rule == null ? null : WalletWithdrawalPolicy(rule: _rule!);

  String? _validationError(FundAmount amount) {
    if (!_operation.canSubmit) return null;
    final policy = _policy;
    if (policy == null || !_rule!.isWithdrawalComplete) {
      return _policyLabels.unavailable;
    }
    final balance = _balance;
    if (balance == null) {
      return _policyLabels.issue(
          WalletWithdrawalPolicyIssue.insufficientBalance, _rule);
    }
    final issue = policy.validate(amount: amount, available: balance.available);
    return issue == null ? null : _policyLabels.issue(issue, _rule);
  }

  Future<({List<FundBalance> balances, WalletCurrencyRule? rule})> _fetchInputs(
      FundCurrency currency) async {
    final results = await Future.wait<Object>([
      _operation.api.fetchBalances(),
      _operation.api.fetchDepositAddress(),
    ]);
    final deposit = results[1] as WalletDepositAddress;
    return (
      balances: results[0] as List<FundBalance>,
      rule: deposit.ruleFor(currency),
    );
  }

  Future<void> _load() async {
    if (!mounted || _loadInProgress || _sheetOpen) return;
    _loadInProgress = true;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _operation.load();
      if (!mounted || !_currentSession) return;
      if (!_amount.isPositive) throw const FormatException('请输入有效提现金额');
      final inputs = await _fetchInputs(_amount.currency);
      if (!mounted || !_currentSession) return;
      setState(() {
        _balances = inputs.balances;
        _rule = inputs.rule;
      });
    } catch (failure) {
      if (mounted && _currentSession) {
        setState(() {
          _rule = null;
          _loadError = walletOperationError(failure);
        });
      }
    } finally {
      _loadInProgress = false;
      if (mounted) {
        setState(() {
          _loading = false;
          if (!_currentSession) {
            _balances = const [];
            _rule = null;
            _loadError = _policyLabels.accountChanged;
          }
        });
      }
    }
  }

  Future<void> _confirm() async {
    if (!_canAuthorize ||
        _sheetOpen ||
        !_operation.canSubmit ||
        _loading ||
        _loadError != null) {
      return;
    }
    final amount = _amount;
    final labels = _labels;
    final policyLabels = _policyLabels;
    setState(() => _sheetOpen = true);
    try {
      // The displayed policy is informational until this fresh read succeeds.
      // An existing submitted draft is handled only by the order query path.
      final inputs = await _fetchInputs(amount.currency);
      if (!mounted || !_currentSession || !_operation.canSubmit) return;
      setState(() {
        _balances = inputs.balances;
        _rule = inputs.rule;
        _loadError = null;
      });
      if (_validationError(amount) != null) return;
      final balance = _balance!;
      final totalDebit = _policy!.totalDebit(amount);
      if (!await ensureWalletPaymentPassword(context,
          service: widget.settingsService, isActive: () => _canAuthorize)) {
        return;
      }
      if (!mounted || !_currentSession) return;
      final draft = await _operation.prepareWithdrawal(
          amount: amount, toAddress: _address);
      if (!mounted || !_currentSession) return;
      final request = FundSecurityRequest.withdrawal(draft.withdrawalRequest);
      Future<FundSecurityProof?> authorize() =>
          widget.securityAuthorizer?.call(context, request) ??
          authorizeFundSecurity(context,
              request: request,
              api: _operation.api.transport,
              isCurrent: () => _canAuthorize);
      var proof = await authorize();
      if (proof == null || !mounted || !_canAuthorize) return;
      await PayAuthHelper.collectAndSubmit(
        context: context,
        title: labels.chainTitle,
        amountText: totalDebit.displayDecimal,
        amountCoin: amount.currency.displayName,
        payText: '${amount.currency.displayName} · TRON',
        payCoinCode: amount.currency.code,
        receiverName: labels.receiver,
        receiverId: _address,
        walletSubtitle: '${labels.available(balance.available)} · '
            '${policyLabels.total(totalDebit)}',
        onSubmit: (password) async {
          if (!_canAuthorize) {
            return policyLabels.accountChanged;
          }
          try {
            if (proof?.isExpired == true) proof = null;
            proof ??= await authorize();
            if (proof == null) return '请先完成本次提现的安全验证';
            if (!_canAuthorize) {
              return policyLabels.accountChanged;
            }
            final result = await _operation.submit(
                amount: amount,
                toAddress: _address,
                payPassword: password,
                verifyChallengeID: proof!.challengeID,
                verifyCode: proof!.code);
            if (!mounted || !_currentSession) {
              return policyLabels.accountChanged;
            }
            return result.accepted
                ? null
                : walletWithdrawalResultMessage(result);
          } catch (failure) {
            if (failure is FundApiException &&
                const {20076, 20077, 20078}.contains(failure.code)) {
              proof = null;
            }
            return walletWithdrawalErrorMessage(failure,
                unresolved: _operation.unresolved);
          }
        },
      );
    } catch (failure) {
      if (mounted && _canFeedback) {
        WalletTip.show(context, walletWithdrawalErrorMessage(failure));
      }
    } finally {
      // Keep the frozen request for retries within the password sheet. Only
      // release it after the entire interaction has closed and the API has
      // either not submitted it or confirmed its result.
      final receipt = _operation.receipt;
      final canContinue = await _finishInteraction();
      if (mounted) {
        setState(() {
          _sheetOpen = false;
          if (!_currentSession) {
            _balances = const [];
            _rule = null;
            _loadError = policyLabels.accountChanged;
          }
        });
      }
      if (mounted && _canFeedback && canContinue && receipt != null) {
        WalletTip.show(context, walletWithdrawalResultMessage(receipt));
        if (receipt.accepted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<bool> _finishInteraction() async {
    if (!mounted || !_currentSession) return false;
    try {
      return await _operation.finishWithdrawalInteraction();
    } catch (failure) {
      if (mounted && _canFeedback) {
        WalletTip.show(
            context,
            walletWithdrawalErrorMessage(failure,
                unresolved: _operation.unresolved));
      }
      return false;
    }
  }

  Future<void> _query() async {
    if (!mounted || !_canFeedback || _sheetOpen) return;
    try {
      final receipt = await _operation.refreshOrder();
      final canContinue = await _finishInteraction();
      if (!mounted || !_canFeedback) return;
      WalletTip.show(context, walletWithdrawalResultMessage(receipt));
      if (canContinue && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (failure) {
      if (mounted && _canFeedback) {
        WalletTip.show(
            context,
            walletWithdrawalErrorMessage(failure,
                unresolved: _operation.unresolved));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _operation.removeListener(_changed);
    _operation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final appBar = WalletAppBarColors.of(context);
    FundAmount? amount;
    try {
      amount = _amount;
    } catch (_) {}
    final currency = amount?.currency;
    final labels = _labels;
    final fee = _operation.receipt?.fee ??
        _operation.receipt?.order.fee ??
        (_operation.draft?.submitted == true ||
                _rule?.withdrawFeeCurrency != currency
            ? null
            : _rule?.withdrawFee);
    FundAmount? totalDebit;
    if (amount != null && fee != null) {
      totalDebit = WalletWithdrawalPolicy.addFee(
          amount, FundAmount.parse(fee, amount.currency));
    }
    final validationError =
        _loading || amount == null ? null : _validationError(amount);
    return wrapWalletPage(
        context,
        Scaffold(
          backgroundColor: cs.bg,
          appBar: AppBar(
            leading: const AppBackButton(),
            title: Text(labels.title),
            centerTitle: true,
            backgroundColor: appBar.background,
            foregroundColor: appBar.title,
            surfaceTintColor: appBar.background,
            systemOverlayStyle: walletPageOverlayStyle(context),
          ),
          body: SafeArea(
              child: ListView(
            padding: const EdgeInsets.all(AppTokens.s5),
            children: [
              Center(
                  child: WalletCoinLogo(
                type:
                    currency == FundCurrency.trx ? CoinType.trx : CoinType.usdt,
                logoUrl: widget.coin.logoUrl,
                size: AppTokens.s10,
              )),
              const SizedBox(height: AppTokens.s5),
              Text(
                  amount == null
                      ? '--'
                      : '${amount.displayDecimal} ${currency!.displayName}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(color: cs.text)),
              const SizedBox(height: AppTokens.s7),
              Card(
                  color: cs.card,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s5),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${labels.receiver} · TRON',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: AppTokens.s3),
                          SelectableText(_address),
                          TextButton.icon(
                              onPressed: () => Clipboard.setData(
                                  ClipboardData(text: _address)),
                              icon: const Icon(Icons.copy_outlined),
                              label: Text(labels.copyAddress)),
                          const Divider(),
                          if (currency != null)
                            WalletWithdrawalRuleSummary(
                              currency: currency,
                              rule: _rule,
                              fee: fee,
                              totalDebit: totalDebit,
                            ),
                          const SizedBox(height: AppTokens.s3),
                          Text(labels.broadcastExplanation),
                        ]),
                  )),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_loadError != null || validationError != null) ...[
                Text(_loadError ?? validationError!,
                    key: const ValueKey('wallet-withdraw-validation'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.red)),
                TextButton(
                    key: const ValueKey('wallet-withdraw-retry'),
                    onPressed: _loading || _sheetOpen ? null : _load,
                    child: Text(_policyLabels.retry)),
              ],
              const SizedBox(height: AppTokens.s5),
              WalletWithdrawalPendingActions(
                  coordinator: _operation, onQuery: _query),
              const SizedBox(height: AppTokens.s5),
              ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: AppTokens.buttonHeight),
                  child: FilledButton(
                    key: const ValueKey('wallet-withdraw-confirm'),
                    onPressed: !_loading &&
                            _loadError == null &&
                            !_sheetOpen &&
                            _operation.canSubmit &&
                            amount != null &&
                            validationError == null
                        ? _confirm
                        : null,
                    child: Text(
                        _operation.busy ? labels.submitting : labels.submit),
                  )),
            ],
          )),
        ));
  }
}
