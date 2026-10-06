import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/wallet_fund_api.dart';
import 'wallet_swap_error.dart';

/// Quotes follow the input, while settlement remains owned by the coordinator.
/// A response for an older input or account never replaces the visible price.
class WalletSwapQuoteController extends ChangeNotifier {
  WalletSwapQuoteController({
    required this.api,
    required this.isActive,
    DateTime Function()? now,
    this.debounce = const Duration(milliseconds: 350),
  }) : now = now ?? DateTime.now;

  final WalletFundApi api;
  final bool Function() isActive;
  final DateTime Function() now;
  final Duration debounce;
  FundAmount? _amount;
  FundCurrency? _target;
  Timer? _debounceTimer, _expiryTimer;
  Future<WalletSwapQuote?>? _inFlight;
  int _revision = 0;
  bool _disposed = false, _foreground = true;
  bool loading = false;
  String? error;
  WalletSwapQuote? quote;

  WalletSwapQuote? get validQuote {
    final value = quote;
    return _active &&
            value != null &&
            !value.isExpired(now()) &&
            _amount != null &&
            value.matches(_amount!, _target!)
        ? value
        : null;
  }

  bool get _active => !_disposed && _foreground && isActive();
  bool get _canQuote =>
      _amount?.isPositive == true &&
      _amount!.units <= BigInt.parse('9223372036854775807') &&
      _target != null &&
      _target != _amount!.currency;

  void _notify() {
    if (!_disposed && isActive()) notifyListeners();
  }

  void update(FundAmount? amount, FundCurrency target) {
    if (_amount == amount && _target == target) return;
    _invalidate();
    _amount = amount;
    _target = target;
    _notify();
    if (_active && _canQuote) {
      _debounceTimer = Timer(debounce, refresh);
    }
  }

  void _invalidate() {
    _revision++;
    _debounceTimer?.cancel();
    _expiryTimer?.cancel();
    _inFlight = null;
    quote = null;
    error = null;
    loading = false;
  }

  void clear() {
    _invalidate();
    _amount = null;
    _target = null;
    _notify();
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _revision++;
    _debounceTimer?.cancel();
    _expiryTimer?.cancel();
    _inFlight = null;
    loading = false;
    if (value && quote != null) _watchExpiry();
    _notify();
  }

  Future<WalletSwapQuote?> ensureQuote() async => validQuote ?? await refresh();

  Future<WalletSwapQuote?> refresh() {
    _debounceTimer?.cancel();
    if (!_active || !_canQuote) return Future.value();
    if (_inFlight != null) return _inFlight!;
    final revision = _revision;
    loading = true;
    error = null;
    quote = null;
    _expiryTimer?.cancel();
    _notify();
    return _inFlight = _request(revision);
  }

  Future<WalletSwapQuote?> _request(int revision) async {
    final amount = _amount!;
    final target = _target!;
    try {
      final value =
          await api.fetchSwapQuote(amount: amount, toCurrency: target);
      if (!_active || revision != _revision) return null;
      if (!value.matches(amount, target)) {
        throw const FormatException('报价与输入不一致，请重新获取');
      }
      quote = value;
      if (value.isExpired(now())) error = '报价已过期，请重新获取';
      _watchExpiry();
      return validQuote;
    } catch (failure) {
      if (_active && revision == _revision) {
        error = walletSwapErrorMessage(failure);
      }
      return null;
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        _inFlight = null;
        _notify();
      }
    }
  }

  void _watchExpiry() {
    _expiryTimer?.cancel();
    final value = quote;
    if (!_active || value == null) return;
    final remaining = value.expiresAt.difference(now());
    if (remaining <= Duration.zero) {
      error = '报价已过期，请重新获取';
      return;
    }
    _expiryTimer = Timer(remaining, () {
      if (!_active) return;
      if (value.isExpired(now())) {
        error = '报价已过期，请重新获取';
        _notify();
      } else {
        _watchExpiry();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }
}
