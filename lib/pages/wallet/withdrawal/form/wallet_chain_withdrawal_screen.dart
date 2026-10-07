import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../wallet_withdrawal_feedback.dart';
import '../wallet_withdrawal_success_screen.dart';
import '../../../../services/fund_api.dart' show FundApiException;

import '../../../customer_service/customer_service.dart';
import '../../../fund/withdrawal_security/withdrawal_security.dart';
import '../../../mine/settings/settings_service.dart';
import '../../data/wallet_fund_api.dart';
import '../../data/wallet_fund_repository.dart';
import '../../data/wallet_operation_coordinator.dart';
import '../../host/wallet_i18n.dart';
import '../../host/wallet_navigation.dart';
import '../../host/wallet_qr_scanner.dart';
import '../../operations/wallet_payment_password_navigation.dart';
import '../../pay_auth_helper.dart';
import '../../wallet_asset_record_screen.dart';
import '../../wallet_repository.dart';
import '../../widgets/currency_rules/wallet_withdrawal_policy_labels.dart';
import '../../widgets/wallet_page_colors.dart';
import '../../widgets/wallet_tip.dart';
import '../../withdraw_transfer_target_validator.dart';
import '../wallet_withdrawal_review_labels.dart';
import 'wallet_chain_withdrawal_controller.dart';
import 'wallet_chain_withdrawal_labels.dart';
import 'wallet_chain_withdrawal_tokens.dart';
import 'widgets/wallet_chain_withdrawal_body.dart';
import 'widgets/wallet_chain_withdrawal_info_dialog.dart';
import 'widgets/wallet_chain_withdrawal_network_sheet.dart';

/// Address, network and amount share one draft and the existing payment flow.
class WalletChainWithdrawalScreen extends StatefulWidget {
  const WalletChainWithdrawalScreen({
    super.key,
    required this.coin,
    required this.payMethod,
    this.api,
    this.coordinator,
    this.accountProvider,
    this.settingsService,
    this.initialAddress = '',
    this.scanAddress,
    this.securityAuthorizer,
  });

  final CoinDto coin;
  final WalletPayMethodDto payMethod;
  final WalletFundApi? api;
  final WalletOperationCoordinator? coordinator;
  final String Function()? accountProvider;
  final SettingsService? settingsService;
  final String initialAddress;
  final Future<String?> Function(BuildContext context)? scanAddress;
  final Future<FundSecurityProof?> Function(
      BuildContext context, FundSecurityRequest request)? securityAuthorizer;

  @override
  State<WalletChainWithdrawalScreen> createState() =>
      _WalletChainWithdrawalScreenState();
}

class _WalletChainWithdrawalScreenState
    extends State<WalletChainWithdrawalScreen> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _amount = TextEditingController();
  late final WalletChainWithdrawalController _controller;
  bool _visible = false, _foreground = true, _authorizing = false;
  bool _picking = false, _infoOpen = false, _routeTicking = false;
  int _inputWindow = 0;
  String? _actionError;

  WalletChainWithdrawalLabels get _labels =>
      WalletChainWithdrawalLabels(AppI18n.of(context));
  WalletWithdrawalPolicyLabels get _policyLabels =>
      WalletWithdrawalPolicyLabels(AppI18n.of(context));

  @override
  void initState() {
    super.initState();
    FundCurrency currency;
    try {
      currency = walletFundCurrency(widget.payMethod.code.isEmpty
          ? widget.payMethod.coin
          : widget.payMethod.code);
    } catch (_) {
      currency = FundCurrency.bi99;
    }
    _controller = WalletChainWithdrawalController(
        initialCurrency: currency,
        api: widget.api,
        operation: widget.coordinator,
        accountProvider: widget.accountProvider);
    if (widget.initialAddress.isNotEmpty) {
      _controller.setAddress(widget.initialAddress);
    }
    _controller.addListener(_changed);
    _syncInputs();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  void _syncInputs() {
    void sync(TextEditingController input, String value) {
      if (input.text == value) return;
      input.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length));
    }

    sync(_address, _controller.address);
    sync(_amount, _controller.amountText);
  }

  void _changed() {
    if (!mounted) return;
    _syncInputs();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeTicking = TickerMode.valuesOf(context).enabled;
    _visible = (ModalRoute.isCurrentOf(context) ?? true) && _routeTicking;
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncActivity();
  }

  void _syncActivity() {
    if (!_shouldBeActive) {
      _controller.setActive(false);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shouldBeActive) _controller.setActive(true);
    });
  }

  // Reading an explanation does not invalidate the form. Backgrounding or
  // covering it with another page still pauses reads and refreshes on return.
  bool get _shouldBeActive =>
      _foreground && _routeTicking && (_visible || _infoOpen);

  bool get _editable =>
      _controller.canEdit && !_authorizing && !_controller.loading && !_picking;

  void _setAddress(String value) {
    if (!_editable) return;
    _inputWindow++;
    _actionError = null;
    _controller.setAddress(value);
  }

  void _setAmount(String value) {
    if (!_editable) return;
    _inputWindow++;
    _actionError = null;
    _controller.setAmount(value);
  }

  bool _pickCurrent(int window) =>
      mounted &&
      _controller.isCurrentAccount &&
      !_authorizing &&
      _controller.canEdit &&
      window == _inputWindow;

  Future<void> _paste() async {
    if (!_editable) return;
    final window = _inputWindow;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!_pickCurrent(window) || data?.text?.trim().isEmpty != false) return;
    _inputWindow++;
    _actionError = null;
    _controller.setAddress(
        WithdrawTransferTargetValidator.normalizedTargetValue(data!.text!));
  }

  Future<void> _scan() async {
    if (!_editable) return;
    final window = _inputWindow;
    setState(() => _picking = true);
    try {
      final scan = widget.scanAddress;
      final String? value;
      if (scan == null) {
        value =
            await openWalletPage<String>(context, const WalletQrScannerPage());
      } else {
        value = await scan(context);
      }
      if (!_pickCurrent(window) || value == null || value.trim().isEmpty) {
        return;
      }
      _inputWindow++;
      _actionError = null;
      _controller.setAddress(
          WithdrawTransferTargetValidator.normalizedTargetValue(value));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _selectNetwork() async {
    final network = _controller.network;
    if (!_editable || network == null) return;
    final window = _inputWindow;
    final chosen = await showWalletChainWithdrawalNetwork(context,
        network: network, selected: _controller.networkSelected);
    if (!_pickCurrent(window) || chosen != true) return;
    _inputWindow++;
    _controller.selectNetwork();
  }

  void _all() {
    if (!_editable) return;
    _inputWindow++;
    _actionError = null;
    _controller.applyAll();
  }

  Future<void> _info(String title, String message) async {
    if (_authorizing ||
        _infoOpen ||
        !_visible ||
        !_foreground ||
        !_controller.isCurrentAccount) {
      return;
    }
    _infoOpen = true;
    FocusScope.of(context).unfocus();
    try {
      await showWalletChainWithdrawalInfo(context,
          title: title, message: message);
    } finally {
      // Pop completes before the parent route's visibility update. Keep the
      // read-only dialog exemption until that update to avoid a false resume.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        _routeTicking = TickerMode.valuesOf(context).enabled;
        _visible = (ModalRoute.isCurrentOf(context) ?? true) && _routeTicking;
        _infoOpen = false;
        _syncActivity();
      }
    }
  }

  Future<void> _submit() async {
    if (_authorizing ||
        !_controller.canSubmit ||
        !_foreground ||
        !_visible ||
        _form.currentState?.validate() != true) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _authorizing = true;
      _actionError = null;
    });
    try {
      final preflight = await _controller.prepareSubmission();
      if (!mounted ||
          !_foreground ||
          preflight == null ||
          !_controller.matches(preflight)) {
        return;
      }
      if (!await ensureWalletPaymentPassword(context,
          service: widget.settingsService,
          isActive: () => mounted && _controller.isCurrentAccount)) {
        return;
      }
      // Navigator completes a setup route before its parent visibility updates.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_foreground || !_controller.isCurrentAccount) return;
      if ((ModalRoute.isCurrentOf(context) ?? true) != true ||
          !TickerMode.valuesOf(context).enabled) {
        return;
      }
      // Password checks/setup can take time. Join resume reads and revalidate.
      _controller.setActive(true);
      var submission = await _controller.prepareSubmission();
      if (!mounted ||
          !_foreground ||
          submission == null ||
          !_controller.matches(submission)) {
        return;
      }
      final draft = await _controller.operation.prepareWithdrawal(
          amount: submission.amount, toAddress: submission.address);
      if (!mounted || !_foreground || !_controller.isCurrentAccount) return;
      final request = FundSecurityRequest.withdrawal(draft.withdrawalRequest);
      Future<FundSecurityProof?> authorize() =>
          widget.securityAuthorizer?.call(context, request) ??
          authorizeFundSecurity(context,
              request: request,
              api: _controller.operation.api.transport,
              isCurrent: () =>
                  mounted && _foreground && _controller.isCurrentAccount);
      var proof = await authorize();
      if (proof == null ||
          !mounted ||
          !_foreground ||
          !_controller.isCurrentAccount) {
        return;
      }
      // The SMS sheet may have covered/resumed this page. Refresh the policy
      // before PIN collection while preserving the verified draft verbatim.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_foreground || !_controller.isCurrentAccount) return;
      _controller.setActive(true);
      submission = await _controller.prepareSubmission();
      if (submission == null ||
          !mounted ||
          !_controller.matches(submission) ||
          submission.amount != draft.amount ||
          submission.address != draft.toAddress) {
        return;
      }
      final verifiedSubmission = submission;
      final labels = WalletWithdrawalReviewLabels(AppI18n.of(context));
      final policyLabels = _policyLabels;
      await PayAuthHelper.collectAndSubmit(
        context: context,
        title: labels.chainTitle,
        amountText: verifiedSubmission.totalDebit.displayDecimal,
        amountCoin: verifiedSubmission.amount.currency.displayName,
        payText:
            '${verifiedSubmission.amount.currency.code} · ${verifiedSubmission.network}',
        payCoinCode: verifiedSubmission.amount.currency.code,
        receiverName: labels.receiver,
        receiverId: verifiedSubmission.address,
        walletSubtitle:
            '${labels.available(verifiedSubmission.balance.available)} · '
            '${policyLabels.total(verifiedSubmission.totalDebit)}',
        onSubmit: (password) async {
          if (!mounted ||
              !_foreground ||
              !_controller.matches(verifiedSubmission)) {
            return policyLabels.accountChanged;
          }
          try {
            if (proof?.isExpired == true) proof = null;
            proof ??= await authorize();
            if (proof == null) return '请先完成本次提现的安全验证';
            if (!mounted || !_foreground || !_controller.isCurrentAccount) {
              return policyLabels.accountChanged;
            }
            final receipt = await _controller.operation.submit(
                amount: verifiedSubmission.amount,
                toAddress: verifiedSubmission.address,
                payPassword: password,
                verifyChallengeID: proof!.challengeID,
                verifyCode: proof!.code);
            if (!mounted || !_controller.isCurrentAccount) {
              return policyLabels.accountChanged;
            }
            return receipt.accepted
                ? null
                : walletWithdrawalResultMessage(receipt);
          } catch (failure) {
            if (failure is FundApiException &&
                const {20076, 20077, 20078}.contains(failure.code)) {
              proof = null;
            }
            return walletWithdrawalErrorMessage(failure,
                unresolved: _controller.operation.unresolved);
          }
        },
      );
      if (mounted && _controller.isCurrentAccount) {
        final receipt = _controller.operation.receipt;
        if (receipt != null) {
          await _showResult(receipt);
        }
      }
    } catch (failure) {
      if (mounted && _controller.isCurrentAccount) {
        WalletTip.show(context, walletWithdrawalErrorMessage(failure));
      }
    } finally {
      await _finishInteraction();
      if (mounted) setState(() => _authorizing = false);
    }
  }

  Future<void> _showResult(WalletOperationReceipt receipt) async {
    if (!receipt.accepted) {
      WalletTip.show(context, walletWithdrawalResultMessage(receipt));
      return;
    }
    final finished = await _controller.finishInteraction();
    if (!finished ||
        !mounted ||
        !_foreground ||
        !_controller.isCurrentAccount ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WalletWithdrawalSuccessScreen(receipt: receipt)));
  }

  Future<void> _finishInteraction() async {
    if (!mounted ||
        !_controller.isCurrentAccount ||
        _controller.operation.busy) {
      return;
    }
    try {
      await _controller.finishInteraction();
    } catch (failure) {
      if (mounted && _controller.isCurrentAccount) {
        WalletTip.show(context, walletWithdrawalErrorMessage(failure));
      }
    }
  }

  Future<void> _query() async {
    if (_authorizing || !_controller.isCurrentAccount) return;
    try {
      final receipt = await _controller.operation.refreshOrder();
      if (mounted && _controller.isCurrentAccount) {
        await _showResult(receipt);
        await _finishInteraction();
      }
    } catch (failure) {
      if (mounted && _controller.isCurrentAccount) {
        WalletTip.show(
            context,
            walletWithdrawalErrorMessage(failure,
                unresolved: _controller.operation.unresolved));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    _address.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final labels = _labels;
    final currency = _controller.currency;
    final operation = _controller.operation;
    final title = labels.title(currency);
    final titleStyle = Theme.of(context).textTheme.titleLarge!.copyWith(
        fontSize: WalletChainWithdrawalTokens.titleSize,
        fontWeight: FontWeight.w600,
        color: colors.text);
    // Symmetric action reservations keep long or scaled titles centered.
    final titleWidth = MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal -
        WalletChainWithdrawalTokens.tapSize * 4 -
        WalletChainWithdrawalTokens.pagePadding * 2;
    final titlePainter = TextPainter(
        text: TextSpan(text: title, style: titleStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout(maxWidth: math.max(1, titleWidth));
    final toolbarHeight = math.max(
        kToolbarHeight,
        titlePainter.height +
            WalletChainWithdrawalTokens.titleVerticalPadding * 2);
    final titleLines = titlePainter.computeLineMetrics().length;
    titlePainter.dispose();
    return wrapWalletPage(
        context,
        Scaffold(
          key: const ValueKey('wallet-chain-withdrawal-screen'),
          backgroundColor: colors.card,
          appBar: AppBar(
            backgroundColor: colors.card,
            foregroundColor: colors.text,
            surfaceTintColor: colors.card,
            elevation: 0,
            centerTitle: true,
            toolbarHeight: toolbarHeight,
            titleSpacing: WalletChainWithdrawalTokens.pagePadding,
            leadingWidth: WalletChainWithdrawalTokens.tapSize * 2,
            leading: const Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(width: kToolbarHeight, child: AppBackButton())),
            systemOverlayStyle: walletPageOverlayStyle(context),
            title: Text(title,
                textAlign: TextAlign.center,
                maxLines: titleLines,
                softWrap: true,
                style: titleStyle),
            actions: [
              SizedBox(
                  width: WalletChainWithdrawalTokens.tapSize,
                  height: WalletChainWithdrawalTokens.tapSize,
                  child: IconButton(
                      key: const ValueKey('wallet-chain-help'),
                      tooltip: labels.help,
                      onPressed: () => showCustomerServiceSheet(context),
                      icon: const Icon(Icons.help_outline_rounded))),
              SizedBox(
                  width: WalletChainWithdrawalTokens.tapSize,
                  height: WalletChainWithdrawalTokens.tapSize,
                  child: IconButton(
                      key: const ValueKey('wallet-chain-records'),
                      tooltip: labels.records,
                      onPressed: !_controller.isCurrentAccount
                          ? null
                          : () => openWalletPage<void>(
                                context,
                                WalletWithdrawRecordScreen(
                                    repository: WalletFundRepository(
                                        api: operation.api,
                                        accountProvider:
                                            widget.accountProvider)),
                                activityPage: 'wallet_history',
                              ),
                      icon: const Icon(Icons.history_rounded))),
            ],
          ),
          body: WalletChainWithdrawalBody(
            controller: _controller,
            formKey: _form,
            addressController: _address,
            amountController: _amount,
            editable: _editable,
            authorizing: _authorizing,
            picking: _picking,
            actionError: _actionError,
            onAddressChanged: _setAddress,
            onAmountChanged: _setAmount,
            onPaste: _paste,
            onScan: _scan,
            onNetwork: _selectNetwork,
            onAll: _all,
            onInfo: _info,
            onQuery: _query,
            onSubmit: _submit,
          ),
        ));
  }
}
