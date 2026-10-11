import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../services/fund_models.dart';
import '../models/live_tip_currency.dart';

/// One account-scoped balance snapshot for all tip currency choices.
class LiveTipBalance extends ChangeNotifier {
  LiveTipBalance({required this.load, required this.current});

  final Future<List<FundBalance>> Function() load;
  final bool Function() current;
  List<FundBalance> _balances = const [];
  bool loading = false, failed = false;
  bool _closed = false, _active = true;
  int _generation = 0;

  FundBalance? forCurrency(LiveTipCurrency? currency) {
    if (_closed || !_active || !current() || currency == null) return null;
    for (final balance in _balances) {
      if (balance.currency.code == currency.code &&
          balance.currency.decimals == currency.decimals) {
        return balance;
      }
    }
    return null;
  }

  void setActive(bool active) {
    if (_closed || active == _active) return;
    _active = active;
    ++_generation;
    _balances = const [];
    loading = false;
    failed = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_closed || !_active || !current() || loading) return;
    final generation = ++_generation;
    bool valid() =>
        !_closed && _active && current() && generation == _generation;
    loading = true;
    failed = false;
    _balances = const [];
    notifyListeners();
    try {
      final result = await load().timeout(const Duration(seconds: 10));
      if (valid()) _balances = List.unmodifiable(result);
    } catch (_) {
      if (valid()) failed = true;
    } finally {
      if (!_closed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    ++_generation;
    super.dispose();
  }
}
