import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/wallet_fund_api.dart';
import '../order/wallet_order_events.dart';

/// Owns address allocation retries; one request and one timer at most. A
/// covered/background route stops scheduling and ignores in-flight results.
class WalletDepositController extends ChangeNotifier {
  WalletDepositController(
      {WalletFundApi? api,
      String Function()? accountProvider,
      this.pollInterval = const Duration(seconds: 4),
      this.enabled = true})
      : _api = api ?? WalletFundApi(),
        _accountProvider =
            accountProvider ?? (() => WalletOrderEvents.currentAccountKey) {
    _owner = _accountProvider();
  }

  final WalletFundApi _api;
  final String Function() _accountProvider;
  final Duration pollInterval;
  final bool enabled;
  late final String _owner;
  WalletDepositAddress? _address;
  WalletDepositAddress? get address => isCurrentAccount ? _address : null;
  bool get isCurrentAccount => _accountProvider() == _owner;
  bool loading = false;
  bool failed = false;
  String failureMessage = '';
  bool get canUseAddress =>
      enabled && isCurrentAccount && address?.isReady == true;
  bool _active = false;
  bool _busy = false;
  bool _resumeAfterBusy = false;
  bool _dead = false;
  Timer? _timer;

  void setActive(bool active) {
    if (_dead) return;
    if (_active == active && isCurrentAccount) return;
    _active = active;
    _timer?.cancel();
    _timer = null;
    if (!active || !enabled) return;
    if (!isCurrentAccount) {
      _address = null;
      loading = false;
      notifyListeners();
      return;
    }
    if (_busy) {
      _resumeAfterBusy = true;
    } else if (_address?.isReady != true) {
      unawaited(load());
    }
  }

  Future<void> load() async {
    if (_dead || !_active || !enabled || !isCurrentAccount || _busy) return;
    _timer?.cancel();
    _timer = null;
    _busy = true;
    loading = _address == null;
    failed = false;
    failureMessage = '';
    notifyListeners();
    try {
      final result =
          await _api.fetchDepositAddress().timeout(const Duration(seconds: 6));
      if (_dead || !_active || !isCurrentAccount) return;
      _address = result;
      failed = false;
    } catch (error) {
      if (_dead || !_active || !isCurrentAccount) return;
      failed = true;
      failureMessage = walletFundErrorMessage(error);
    } finally {
      _busy = false;
      loading = false;
      if (!_dead && _active && isCurrentAccount) {
        notifyListeners();
        if (_resumeAfterBusy) {
          _resumeAfterBusy = false;
          if (_address?.isReady != true) unawaited(load());
        } else if (!failed && _address?.status == 'pending') {
          _timer = Timer(pollInterval, () => unawaited(load()));
        }
      }
    }
  }

  @override
  void dispose() {
    _dead = true;
    _timer?.cancel();
    super.dispose();
  }
}
