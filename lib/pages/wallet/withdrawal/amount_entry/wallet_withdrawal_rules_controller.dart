import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/wallet_fund_api.dart';
import '../../order/wallet_order_events.dart';

/// Reads current rules without polling address allocation or retaining config.
class WalletWithdrawalRulesController extends ChangeNotifier {
  WalletWithdrawalRulesController({
    required this.currency,
    WalletFundApi? api,
    String Function()? accountProvider,
  })  : _api = api ?? WalletFundApi(),
        _accountProvider =
            accountProvider ?? (() => WalletOrderEvents.currentAccountKey) {
    _owner = _accountProvider();
  }

  final FundCurrency currency;
  final WalletFundApi _api;
  final String Function() _accountProvider;
  late final String _owner;
  WalletCurrencyRule? _rule;
  WalletCurrencyRule? get rule => isCurrentAccount ? _rule : null;
  bool get isCurrentAccount => _owner == _accountProvider();
  bool get isActive => _active && isCurrentAccount && !_dead;
  bool loading = false;
  bool failed = false;
  bool _active = false;
  bool _dead = false;
  bool _reload = false;
  int _activation = 0;
  Future<void>? _flight;

  void setActive(bool active) {
    if (_dead || (_active == active && isCurrentAccount)) return;
    _active = active;
    _activation++;
    if (!isCurrentAccount) {
      _rule = null;
      notifyListeners();
      return;
    }
    if (!active) return;
    if (_flight != null) {
      _reload = true;
    } else {
      unawaited(load());
    }
  }

  Future<void> load() {
    if (!isActive) return Future.value();
    if (_flight != null) return _flight!;
    _reload = false;
    final epoch = _activation;
    loading = true;
    failed = false;
    notifyListeners();
    final flight = _read(epoch);
    _flight = flight;
    return flight;
  }

  Future<void> _read(int epoch) async {
    try {
      final address =
          await _api.fetchDepositAddress().timeout(const Duration(seconds: 6));
      if (!isActive || epoch != _activation) return;
      _rule = address.ruleFor(currency);
      failed = _rule?.isWithdrawalComplete != true;
    } catch (_) {
      if (!isActive || epoch != _activation) return;
      failed = true;
      _rule = null;
    } finally {
      _flight = null;
      loading = false;
      if (!_dead && isActive) {
        notifyListeners();
        if (_reload) {
          _reload = false;
          unawaited(load());
        }
      }
    }
  }

  @override
  void dispose() {
    _dead = true;
    _activation++;
    super.dispose();
  }
}
