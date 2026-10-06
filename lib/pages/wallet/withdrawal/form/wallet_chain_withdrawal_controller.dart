import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart';

import '../../data/currency_rules/wallet_withdrawal_policy.dart';
import '../../data/wallet_fund_api.dart';
import '../../data/wallet_operation_coordinator.dart';
import '../../data/wallet_operation_pending_store.dart';
import '../../order/wallet_order_events.dart';
import '../../tron_address_validator.dart';

class WalletChainWithdrawalSubmission {
  const WalletChainWithdrawalSubmission._({
    required this.amount,
    required this.address,
    required this.balance,
    required this.rule,
    required String owner,
    required int inputRevision,
    required int dataRevision,
  })  : _owner = owner,
        _inputRevision = inputRevision,
        _dataRevision = dataRevision;

  final FundAmount amount;
  final String address;
  final FundBalance balance;
  final WalletCurrencyRule rule;
  final String _owner;
  final int _inputRevision;
  final int _dataRevision;
  String get network => 'TRON';
  FundCurrency get currency => amount.currency;
  FundAmount get totalDebit =>
      WalletWithdrawalPolicy(rule: rule).totalDebit(amount);
}

/// Owns form reads and immutable payment inputs; never collects a PIN or writes.
class WalletChainWithdrawalController extends ChangeNotifier {
  WalletChainWithdrawalController({
    required this.initialCurrency,
    WalletFundApi? api,
    WalletOperationCoordinator? operation,
    String Function()? accountProvider,
  })  : _api = api ?? operation?.api ?? WalletFundApi(),
        _accountProvider =
            accountProvider ?? (() => WalletOrderEvents.currentAccountKey),
        _guardToken = accountProvider == null,
        _ownsOperation = operation == null,
        _currency = initialCurrency {
    _owner = _accountProvider();
    _token = _guardToken ? DataSp.chatToken : null;
    this.operation = operation ??
        WalletOperationCoordinator(
          kind: WalletOperationKind.withdraw,
          api: _api,
          isAccountCurrent: _sameOwner,
        );
    this.operation.addListener(_operationChanged);
    _syncDraft();
  }

  final FundCurrency initialCurrency;
  final WalletFundApi _api;
  final String Function() _accountProvider;
  final bool _guardToken;
  final bool _ownsOperation;
  late final String _owner;
  String? _token;
  late final WalletOperationCoordinator operation;
  FundCurrency _currency;
  WalletCurrencyRule? _rule;
  FundBalance? _balance;
  String? _network;
  String _ownAddress = '', _address = '', _amountText = '';
  bool _selectedNetwork = false;
  bool _active = false, _dead = false, _restored = false, _reload = false;
  bool _preparing = false;
  bool loading = false, failed = false;
  String? _error;
  int _activation = 0, _inputRevision = 0, _dataRevision = 0;
  Future<void>? _flight;
  WalletOperationDraft? _lastDraft;
  bool _keepInteractionInputs = false;
  Future<bool>? _finishingInteraction;
  static final _maxUnits = BigInt.parse('9223372036854775807');

  bool _sameOwner() =>
      !_dead &&
      _owner == _accountProvider() &&
      (!_guardToken ||
          (_token?.isNotEmpty == true && _token == DataSp.chatToken));
  bool get isCurrentAccount => _sameOwner() && operation.sameAccount;
  bool get isActive => _active && isCurrentAccount;
  FundCurrency get currency => operation.draft?.amount.currency ?? _currency;
  WalletCurrencyRule? get rule => isCurrentAccount ? _rule : null;
  FundBalance? get balance => isCurrentAccount ? _balance : null;
  String? get network => isCurrentAccount ? _network : null;
  String get address => isCurrentAccount ? _address : '';
  String get amountText => isCurrentAccount ? _amountText : '';
  String? get error => isCurrentAccount ? _error : '账号已变化，请重新打开钱包';
  bool get canEdit =>
      isCurrentAccount && operation.draft == null && !operation.busy;
  bool get networkSelected => _selectedNetwork && network == 'TRON';
  bool get addressValid => TronAddressValidator.isValid(address);
  bool get isSelfAddress =>
      _ownAddress.isNotEmpty && address == _ownAddress && isCurrentAccount;
  FundAmount? get amount {
    try {
      return FundAmount.parse(amountText, currency);
    } on FormatException {
      return null;
    }
  }

  WalletWithdrawalPolicyIssue? get policyIssue {
    final value = amount;
    if (value == null || !value.isPositive) return null;
    final currentRule = rule;
    final currentBalance = balance;
    if (currentRule == null || currentBalance == null) {
      return WalletWithdrawalPolicyIssue.incomplete;
    }
    return WalletWithdrawalPolicy(rule: currentRule)
        .validate(amount: value, available: currentBalance.available);
  }

  bool get _validInputs {
    final value = amount;
    return currency != FundCurrency.bi99 &&
        networkSelected &&
        addressValid &&
        !isSelfAddress &&
        value?.isPositive == true &&
        value!.units <= _maxUnits &&
        rule?.isWithdrawalComplete == true &&
        balance != null &&
        policyIssue == null &&
        WalletWithdrawalPolicy(rule: rule!).totalDebit(value).units <=
            _maxUnits;
  }

  bool get canSubmit =>
      isActive &&
      _restored &&
      !loading &&
      !failed &&
      operation.canSubmit &&
      _validInputs;

  void _notify() {
    if (!_dead) notifyListeners();
  }

  void setActive(bool active) {
    if (_dead || _active == active && isCurrentAccount) return;
    _active = active;
    _activation++;
    if (!isCurrentAccount) {
      _clearData();
      failed = true;
      _notify();
      return;
    }
    if (active) {
      if (_flight != null) {
        _reload = true;
      } else {
        unawaited(load());
      }
    }
  }

  void setAddress(String value) {
    if (!canEdit || _address == value.trim()) return;
    _address = value.trim();
    _inputRevision++;
    _notify();
  }

  void setAmount(String value) {
    if (!canEdit || _amountText == value.trim()) return;
    _amountText = value.trim();
    _inputRevision++;
    _notify();
  }

  void selectNetwork() {
    if (!canEdit || network != 'TRON' || _selectedNetwork) return;
    _selectedNetwork = true;
    _inputRevision++;
    _notify();
  }

  void applyAll() {
    if (!canEdit || rule?.isWithdrawalComplete != true || balance == null) {
      return;
    }
    setAmount(WalletWithdrawalPolicy(rule: rule!)
        .spendable(balance!.available)
        .decimal);
  }

  /// A closed payment UI releases only a refused/cancelled request or a
  /// server-confirmed order. Accepted withdrawals clear the recipient and amount.
  Future<bool> finishInteraction() {
    if (!isCurrentAccount) return Future.value(false);
    return _finishingInteraction ??= Future<bool>.microtask(_finishInteraction)
        .whenComplete(() => _finishingInteraction = null);
  }

  Future<bool> _finishInteraction() async {
    if (!isCurrentAccount) return false;
    final confirmed = operation.receipt != null;
    final accepted = operation.receipt?.accepted ?? false;
    _keepInteractionInputs = true;
    try {
      final finished = await operation.finishWithdrawalInteraction();
      if (!finished || !isCurrentAccount) return false;
      if (confirmed) {
        if (accepted) _address = '';
        _amountText = '';
        _inputRevision++;
        _notify();
        if (isActive) await load();
      }
      return true;
    } finally {
      _keepInteractionInputs = false;
    }
  }

  Future<void> load() {
    if (!isActive) return Future.value();
    if (_flight != null) return _flight!;
    final finished = Completer<void>();
    _flight = finished.future;
    final epoch = _activation;
    _beginRead();
    unawaited(_load(epoch).whenComplete(() {
      _finishRead();
      finished.complete();
    }));
    return finished.future;
  }

  Future<void> _load(int epoch) async {
    try {
      await operation.load();
      if (!_readCurrent(epoch)) return;
      _restored = true;
      _syncDraft();
      final requestedCurrency = currency;
      final inputs = await _fetchInputs();
      if (!_readCurrent(epoch) || currency != requestedCurrency) return;
      _applyInputs(inputs.$1, inputs.$2);
    } catch (failure) {
      _readFailed(epoch, failure);
    }
  }

  Future<WalletChainWithdrawalSubmission?> prepareSubmission() async {
    if (!isActive || !operation.canSubmit || _preparing) return null;
    _preparing = true;
    final epoch = _activation;
    final revision = _inputRevision;
    final requestedCurrency = currency;
    try {
      // A settings route may have just resumed this form and started a read.
      // Join that read, then validate again against an independent fresh read.
      while (_flight != null) {
        await _flight;
        if (!_readCurrent(epoch) ||
            revision != _inputRevision ||
            currency != requestedCurrency) {
          return null;
        }
      }
      if (!canSubmit) return null;
      final finished = Completer<void>();
      _flight = finished.future;
      _beginRead();
      return await _prepare(epoch, revision, requestedCurrency)
          .whenComplete(() {
        _finishRead();
        finished.complete();
      });
    } finally {
      _preparing = false;
    }
  }

  Future<WalletChainWithdrawalSubmission?> _prepare(
      int epoch, int revision, FundCurrency requestedCurrency) async {
    try {
      final inputs = await _fetchInputs();
      if (!_readCurrent(epoch) ||
          revision != _inputRevision ||
          currency != requestedCurrency) {
        return null;
      }
      _applyInputs(inputs.$1, inputs.$2);
      if (!_validInputs || failed || !operation.canSubmit) return null;
      return WalletChainWithdrawalSubmission._(
        amount: amount!,
        address: address,
        balance: balance!,
        rule: rule!,
        owner: _owner,
        inputRevision: _inputRevision,
        dataRevision: _dataRevision,
      );
    } catch (failure) {
      _readFailed(epoch, failure);
      return null;
    }
  }

  bool matches(WalletChainWithdrawalSubmission submission) =>
      isCurrentAccount &&
      operation.canSubmit &&
      _validInputs &&
      submission._owner == _owner &&
      submission._inputRevision == _inputRevision &&
      submission._dataRevision == _dataRevision &&
      submission.amount == amount &&
      submission.address == address;

  Future<(List<FundBalance>, WalletDepositAddress)> _fetchInputs() async {
    final values = await Future.wait<Object>([
      _api.fetchBalances(),
      _api.fetchDepositAddress(),
    ]).timeout(const Duration(seconds: 6));
    return (values[0] as List<FundBalance>, values[1] as WalletDepositAddress);
  }

  bool _readCurrent(int epoch) => isActive && epoch == _activation;
  void _beginRead() {
    _reload = false;
    loading = true;
    failed = false;
    _error = null;
    _notify();
  }

  void _applyInputs(List<FundBalance> balances, WalletDepositAddress deposit) {
    if (deposit.network != 'TRON' || !deposit.currencies.contains(currency)) {
      throw const FormatException('该币种或网络不支持链上提现');
    }
    final matching =
        balances.where((value) => value.currency == currency).toList();
    if (matching.length != 1) throw const FormatException('提现余额数据不完整');
    _balance = matching.single;
    _rule = deposit.ruleFor(currency);
    _network = deposit.network;
    _ownAddress = deposit.isReady ? deposit.address.trim() : '';
    if (operation.draft != null) _selectedNetwork = true;
    failed = _rule?.isWithdrawalComplete != true;
    _error = failed ? '提现规则暂不可用，请重试' : null;
    _dataRevision++;
  }

  void _readFailed(int epoch, Object failure) {
    if (!_readCurrent(epoch)) return;
    _clearData();
    failed = true;
    _error = walletOperationError(failure);
  }

  void _clearData() {
    _rule = null;
    _balance = null;
    _network = null;
    _ownAddress = '';
    _dataRevision++;
  }

  void _finishRead() {
    _flight = null;
    loading = false;
    if (_dead) return;
    if (!isCurrentAccount) {
      _clearData();
      failed = true;
    }
    _notify();
    if (_reload && isActive) unawaited(load());
  }

  void _syncDraft() {
    final draft = operation.draft;
    if (draft != null) {
      if (_currency != draft.amount.currency ||
          _address != draft.toAddress ||
          amount != draft.amount) {
        _inputRevision++;
      }
      _currency = draft.amount.currency;
      _address = draft.toAddress;
      _amountText = draft.amount.decimal;
    } else if (_lastDraft != null && !_keepInteractionInputs) {
      _currency = initialCurrency;
      _address = '';
      _amountText = '';
      _selectedNetwork = false;
      _inputRevision++;
      _clearData();
      if (isActive) {
        if (_flight != null) {
          _reload = true;
        } else {
          unawaited(load());
        }
      }
    }
    _lastDraft = draft;
  }

  void _operationChanged() {
    if (_dead) return;
    if (isCurrentAccount) _syncDraft();
    _notify();
  }

  @override
  void dispose() {
    _dead = true;
    _activation++;
    operation.removeListener(_operationChanged);
    if (_ownsOperation) operation.dispose();
    super.dispose();
  }
}
