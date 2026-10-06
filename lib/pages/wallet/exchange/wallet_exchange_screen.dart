import 'package:flutter/material.dart';

import '../../mine/settings/settings_service.dart';

import '../data/wallet_fund_api.dart';
import '../data/wallet_operation_coordinator.dart';
import '../data/wallet_operation_pending_store.dart';
import '../host/wallet_navigation.dart';
import '../operations/wallet_operation_detail_screen.dart';
import '../operations/wallet_payment_password_navigation.dart';
import '../operations/widgets/wallet_operation_status_card.dart';
import '../order/wallet_order.dart';
import '../pay_auth_helper.dart';
import '../record/wallet_record_amount.dart';
import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';
import '../widgets/wallet_system_ui.dart';
import '../widgets/wallet_tip.dart';
import 'wallet_exchange_tokens.dart';
import 'data/wallet_swap_quote_controller.dart';
import 'data/wallet_swap_error.dart';
import 'widgets/wallet_swap_quote_sheet.dart';
import 'widgets/wallet_exchange_amount.dart';
import 'widgets/wallet_exchange_form.dart';
import 'widgets/wallet_exchange_keypad.dart';
import 'widgets/wallet_exchange_layout.dart';

class WalletExchangeScreen extends StatefulWidget {
  const WalletExchangeScreen(
      {super.key,
      this.api,
      this.coordinator,
      this.settingsService,
      this.quoteController});
  final WalletFundApi? api;
  final WalletOperationCoordinator? coordinator;
  final SettingsService? settingsService;
  final WalletSwapQuoteController? quoteController;

  @override
  State<WalletExchangeScreen> createState() => _WalletExchangeScreenState();
}

class _WalletExchangeScreenState extends State<WalletExchangeScreen>
    with WidgetsBindingObserver {
  final _amount = TextEditingController();
  late final WalletOperationCoordinator _operation;
  late final WalletSwapQuoteController _quotes;
  FundCurrency _from = FundCurrency.usdt, _to = FundCurrency.bi99;
  List<FundBalance> _balances = const [];
  bool _loading = true, _sheetOpen = false;
  String? _loadError;
  String? _resetError;

  @override
  void initState() {
    super.initState();
    _operation = widget.coordinator ??
        WalletOperationCoordinator(
            kind: WalletOperationKind.swap, api: widget.api);
    _operation.addListener(_changed);
    _quotes = widget.quoteController ??
        WalletSwapQuoteController(
          api: _operation.api,
          isActive: () =>
              mounted && _operation.sameAccount && !_operation.unresolved,
        );
    _quotes.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _changed() {
    if (mounted && _operation.sameAccount) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _quotes.setForeground(state == AppLifecycleState.resumed);
  }

  void _updateQuote() => _quotes.update(_parsedAmount, _to);

  bool _completed(WalletOperationReceipt? receipt) =>
      receipt != null &&
      receipt.accepted &&
      receipt.terminal &&
      receipt.order.biz == 'swap' &&
      receipt.order.status == 'done';

  Future<void> _prepareNext(WalletOperationReceipt receipt) async {
    if (!_completed(receipt) ||
        _operation.draft?.orderID != receipt.order.orderID) {
      throw StateError('请先确认本次闪兑完成');
    }
    // Retry the verified terminal marker if saving the result previously
    // failed. A durable uncertain request is never discarded here.
    await _operation.store.save(_operation.draft!);
    await _operation.startNewOperation();
    if (!mounted || !_operation.sameAccount) return;
    _amount.clear();
    _quotes.clear();
    _resetError = null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _operation.load();
      if (!mounted || !_operation.sameAccount) return;
      var completion = _operation.receipt;
      if (completion == null && _operation.draft?.terminal == true) {
        // Reopening an old result requires a current server confirmation.
        completion = await _operation.refreshOrder();
        if (!mounted || !_operation.sameAccount) return;
      }
      if (_completed(completion)) {
        try {
          await _prepareNext(completion!);
          if (!mounted || !_operation.sameAccount) return;
        } catch (_) {
          _resetError = '闪兑已成功，暂未恢复输入，请点击继续闪兑重试';
        }
      }
      final draft = _operation.draft;
      if (draft != null) {
        _from = draft.amount.currency;
        _to = draft.toCurrency!;
        _amount.text = draft.amount.decimal;
      }
      final balances = await _operation.api.fetchBalances();
      if (!mounted || !_operation.sameAccount) return;
      setState(() => _balances = balances);
    } catch (failure) {
      if (mounted) setState(() => _loadError = walletOperationError(failure));
    } finally {
      if (mounted) setState(() => _loading = false);
      if (mounted && _operation.sameAccount && _operation.draft == null) {
        _updateQuote();
      }
    }
  }

  FundBalance? get _balance =>
      _balances.where((balance) => balance.currency == _from).firstOrNull;
  bool get _locked => _sheetOpen || _operation.busy || _operation.draft != null;
  FundAmount? get _parsedAmount {
    try {
      return FundAmount.parse(_amount.text, _from);
    } catch (_) {
      return null;
    }
  }

  bool get _valid {
    final amount = _parsedAmount;
    final balance = _balance;
    return amount != null &&
        amount.isPositive &&
        balance != null &&
        amount.compareTo(balance.available) <= 0 &&
        _from != _to;
  }

  void _selectFrom(FundCurrency currency) {
    if (_locked || !_operation.sameAccount) return;
    setState(() {
      final previous = _from;
      _from = currency;
      if (_to == currency) _to = previous;
      _amount.clear();
    });
    _updateQuote();
  }

  void _selectTo(FundCurrency currency) {
    if (_locked || !_operation.sameAccount) return;
    setState(() {
      final previous = _to;
      _to = currency;
      if (_from == currency) _from = previous;
      _amount.clear();
    });
    _updateQuote();
  }

  void _reverse() {
    if (_locked || !_operation.sameAccount) return;
    setState(() {
      final previous = _from;
      _from = _to;
      _to = previous;
      _amount.clear();
    });
    _updateQuote();
  }

  void _input(String digit) {
    if (_loading || _locked || !_operation.sameAccount) return;
    final value = WalletAmount.clean('${_amount.text}$digit',
        scale: _from.decimals, maxInt: 19);
    setState(() => _amount.text = value);
    _updateQuote();
  }

  void _delete() {
    if (_loading ||
        _locked ||
        !_operation.sameAccount ||
        _amount.text.isEmpty) {
      return;
    }
    setState(() =>
        _amount.text = _amount.text.substring(0, _amount.text.length - 1));
    _updateQuote();
  }

  Future<void> _submit() async {
    if (_sheetOpen || !_operation.canSubmit || !_valid || _loading) return;
    final amount = _parsedAmount!;
    final target = _to;
    FocusScope.of(context).unfocus();
    setState(() => _sheetOpen = true);
    try {
      // A business refusal permits a newly reviewed quote. An uncertain write
      // retains its original ID and can only be queried, never repriced here.
      final draft = _operation.draft;
      if (draft != null &&
          !draft.submitted &&
          _quotes.validQuote?.quoteID != draft.quoteID) {
        await _operation.startNewOperation();
      }
      _updateQuote();
      final preview = await _quotes.ensureQuote();
      if (!mounted || !_operation.sameAccount) return;
      if (preview == null) {
        WalletTip.show(context, _quotes.error ?? '暂时无法获取报价，请重试');
        return;
      }
      final quote = await showWalletSwapQuoteSheet(context, _quotes);
      if (quote == null || !mounted || !_operation.sameAccount) return;
      if (!await ensureWalletPaymentPassword(context,
          service: widget.settingsService,
          isActive: () => mounted && _operation.sameAccount)) {
        return;
      }
      if (!mounted || !_operation.sameAccount) return;
      if (quote.isExpired(_quotes.now())) {
        WalletTip.show(context, '报价已过期，请重新预览');
        return;
      }
      var expiredDuringPayment = false;
      String? quoteRefusal;
      var paymentSheetActive = true;
      try {
        await PayAuthHelper.collectAndSubmit(
          context: context,
          title: '闪兑 · ${amount.currency.displayName} → ${target.displayName}',
          amountText: walletRecordAmountTwoDecimals(amount.decimal),
          amountCoin: amount.currency.displayName,
          payText: '${amount.currency.displayName} 钱包',
          payCoinCode: amount.currency.code,
          walletSubtitle:
              '可用 ${walletRecordAmountTwoDecimals(_balance!.available.decimal)} ${amount.currency.displayName}',
          receiverName:
              '预计实得 ${walletRecordAmountTwoDecimals(quote.estimatedReceived.decimal)}',
          receiverId: target.displayName,
          onSubmit: (password) async {
            try {
              if (quote.isExpired(_quotes.now())) {
                expiredDuringPayment = true;
                if (mounted && paymentSheetActive && _operation.sameAccount) {
                  Navigator.of(context, rootNavigator: true).pop(false);
                }
                return '报价已过期，请重新预览';
              }
              final receipt = await _operation.submit(
                  amount: amount,
                  toCurrency: target,
                  payPassword: password,
                  quote: quote);
              if (!mounted || !_operation.sameAccount) return '账号已变化，请重新打开钱包';
              // Dismissing the PIN does not cancel a write already sent. A
              // late success still refreshes real balances in this page.
              if (!paymentSheetActive) {
                _quotes.clear();
                WalletTip.show(context, receipt.description);
                await _load();
              }
              return receipt.accepted ? null : receipt.description;
            } catch (failure) {
              if (walletSwapRequiresNewQuote(failure)) {
                quoteRefusal = walletSwapErrorMessage(failure);
                if (mounted && _operation.sameAccount) {
                  _quotes.clear();
                }
                if (mounted && paymentSheetActive && _operation.sameAccount) {
                  Navigator.of(context, rootNavigator: true).pop(false);
                }
              }
              return _operation.unresolved
                  ? walletOperationError(failure, unresolved: true)
                  : walletSwapErrorMessage(failure);
            }
          },
        );
      } finally {
        paymentSheetActive = false;
      }
      if (mounted && _operation.sameAccount && expiredDuringPayment) {
        WalletTip.show(context, '报价已过期，请重新预览');
      }
      if (mounted && _operation.sameAccount && quoteRefusal != null) {
        WalletTip.show(context, quoteRefusal!);
        _updateQuote();
      }
      if (mounted && _operation.sameAccount && _operation.receipt != null) {
        _quotes.clear();
        WalletTip.show(context, _operation.receipt!.description);
        // No local subtraction or invented output: refresh actual balances.
        await _load();
      }
    } catch (failure) {
      if (mounted && _operation.sameAccount) {
        WalletTip.show(context, walletOperationError(failure));
      }
    } finally {
      if (mounted) setState(() => _sheetOpen = false);
    }
  }

  Future<void> _query() async {
    try {
      final receipt = await _operation.refreshOrder();
      if (!mounted || !_operation.sameAccount) return;
      await openWalletPage<void>(
          context, WalletOperationDetailScreen(receipt: receipt));
      if (mounted && _operation.sameAccount) await _load();
    } catch (failure) {
      if (mounted) {
        WalletTip.show(context,
            walletOperationError(failure, unresolved: _operation.unresolved));
      }
    }
  }

  Future<void> _new() async {
    if (_loading || _sheetOpen || _operation.busy || !_operation.sameAccount) {
      return;
    }
    setState(() => _loading = true);
    try {
      if (_completed(_operation.receipt)) {
        await _prepareNext(_operation.receipt!);
      } else {
        await _operation.startNewOperation();
      }
      if (!mounted || !_operation.sameAccount) return;
      _amount.clear();
      _quotes.clear();
      _resetError = null;
      await _load();
    } catch (failure) {
      if (mounted) WalletTip.show(context, walletOperationError(failure));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quotes.removeListener(_changed);
    _quotes.dispose();
    _operation.removeListener(_changed);
    _operation.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final background = WalletExchangeTokens.background(context);
    final overlay = immersiveOverlayForColors(
        statusBarBackground: background, navigationBarBackground: background);
    final locked = _loading || _locked || !_operation.sameAccount;
    final amount = _parsedAmount;
    final balance = _balance;
    final quote = _quotes.validQuote;
    final continueSwap =
        _operation.canStartNew && _operation.receipt?.terminal == true;
    final received = _operation.receipt?.received ??
        _operation.receipt?.order.targetAmount ??
        quote?.estimatedReceived.decimal;
    final insufficient = !locked &&
        _loadError == null &&
        amount != null &&
        amount.isPositive &&
        balance != null &&
        amount.compareTo(balance.available) > 0;
    final Widget? balanceFeedback = _loadError != null
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_loadError!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.red)),
            TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('重新加载余额')),
          ])
        : insufficient
            ? Text('余额不足',
                key: const ValueKey('wallet-swap-validation'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.red))
            : null;
    final Widget? feedback = _resetError != null
        ? Text(_resetError!,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.red))
        : balanceFeedback ??
            (_quotes.loading
                ? Text('正在获取报价…',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.subText))
                : _quotes.error != null && _operation.draft == null
                    ? Text(_quotes.error!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.red))
                    : null);
    return AnnotatedRegion(
      value: overlay,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('闪兑'),
          centerTitle: true,
          backgroundColor: background,
          foregroundColor: cs.text,
          surfaceTintColor: background,
          systemOverlayStyle: overlay,
        ),
        body: SafeArea(
          child: WalletExchangeLayout(
            loading: _loading,
            amount: WalletExchangeAmount(
                controller: _amount,
                currency: _from,
                locked: locked,
                inputValueUsd: quote?.inputValueUsd),
            form: WalletExchangeForm(
              from: _from,
              to: _to,
              amountController: _amount,
              available: balance == null
                  ? '--'
                  : walletRecordAmountTwoDecimals(balance.available.decimal),
              outputAmount: received == null
                  ? '--'
                  : walletRecordAmountTwoDecimals(received),
              outputEstimated: _operation.receipt == null && quote != null,
              locked: locked,
              onFrom: _selectFrom,
              onTo: _selectTo,
              onReverse: _reverse,
              onAmountChanged: () => setState(() {}),
            ),
            feedback: feedback,
            button: SizedBox(
              height: AppTokens.buttonHeight,
              child: FilledButton(
                key: const ValueKey('wallet-swap-submit'),
                style: FilledButton.styleFrom(
                  backgroundColor: WalletExchangeTokens.action(context),
                  foregroundColor: WalletExchangeTokens.onAction(context),
                  disabledBackgroundColor: WalletExchangeTokens.panel(context),
                  disabledForegroundColor: cs.subText,
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: WalletExchangeTokens.bodyFont,
                      fontWeight: FontWeight.w600),
                ),
                onPressed: continueSwap &&
                        !_loading &&
                        !_sheetOpen &&
                        !_operation.busy &&
                        _operation.sameAccount
                    ? _new
                    : !_loading &&
                            _loadError == null &&
                            !_sheetOpen &&
                            _operation.canSubmit &&
                            _valid
                        ? _submit
                        : null,
                child: Text(_operation.busy
                    ? '提交中'
                    : continueSwap
                        ? '继续闪兑'
                        : '预览'),
              ),
            ),
            keypad: WalletExchangeKeypad(
                enabled: !locked, onInput: _input, onDelete: _delete),
            status: _operation.draft == null || _completed(_operation.receipt)
                ? const SizedBox.shrink()
                : WalletOperationStatusCard(
                    coordinator: _operation, onQuery: _query, onNew: _new),
          ),
        ),
      ),
    );
  }
}
