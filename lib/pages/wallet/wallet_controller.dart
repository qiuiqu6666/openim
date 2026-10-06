import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/wallet_session_source.dart';
import 'order/wallet_order_events.dart';
import 'wallet_repository.dart';
import 'wallet_repository_provider.dart';
import 'data/wallet_trend_data.dart';

class WalletController extends ChangeNotifier {
  final WalletRepository _repo;

  WalletController(
      {WalletRepository? repo,
      Stream<String>? balanceChanges,
      String? accountKey})
      : _repo = repo ?? createWalletRepository() {
    final source = _repo;
    final owner = accountKey ??
        (source is WalletSessionSource
            ? (source as WalletSessionSource).ownerAccountKey
            : null);
    if (owner != null) {
      _balanceSubscription =
          (balanceChanges ?? WalletOrderEvents.balanceChanges).listen((key) {
        if (_dead || key != owner || !_sameAccount) return;
        if (!_active) {
          _dirty = true;
        } else {
          unawaited(load(force: true));
        }
      });
    }
  }

  StreamSubscription<String>? _balanceSubscription;
  bool get _sameAccount =>
      _repo is! WalletSessionSource ||
      (_repo as WalletSessionSource).isCurrentAccount;

  bool loading = false;
  bool loadFailed = false;
  bool showBal = true;
  Object? lastError;

  // Available balances and server CNY valuations come from the fund snapshot.
  String totalBal = '--';
  bool inspectingTrend = false;
  String? inspectedTrendCny;

  void inspectTrendBalance(String? amount) {
    if (_dead || !_active || !_sameAccount || !showBal) return;
    if (inspectingTrend && inspectedTrendCny == amount) return;
    inspectingTrend = true;
    inspectedTrendCny = amount;
    notifyListeners();
  }

  void endTrendInspection() {
    if (!inspectingTrend) return;
    inspectingTrend = false;
    inspectedTrendCny = null;
    if (!_dead) {
      if (_active) {
        notifyListeners();
      } else {
        _paintPending = true;
      }
    }
  }

  String totalBalUsd = '';
  String dailyAmountCny = '--';
  String dailyPercentage = '--';
  String trxAddr = '';
  List<CoinDto> coins = [];

  bool _dead = false;
  WalletTrendData? trend;
  bool trendLoading = false;
  bool trendFailed = false;
  bool _trendEnabled = false;
  bool _trendAgain = false;

  void setTrendEnabled(bool enabled) {
    _trendEnabled = enabled;
    if (!enabled) endTrendInspection();
    if (enabled) unawaited(loadTrend());
  }

  Future<void> loadTrend() async {
    if (_dead || !_active || !_sameAccount) return;
    if (trendLoading) {
      _trendAgain = true;
      return;
    }
    final source = _repo;
    if (source is! WalletTrendSource) return;
    trendLoading = true;
    trendFailed = false;
    notifyListeners();
    try {
      final data = await (source as WalletTrendSource)
          .getTrend()
          .timeout(const Duration(seconds: 6));
      if (_dead) return;
      if (!_sameAccount) {
        _clearAccountSnapshot();
        return;
      }
      trend = data;
      inspectingTrend = false;
      inspectedTrendCny = null;
    } catch (_) {
      if (!_dead) {
        if (!_sameAccount) {
          _clearAccountSnapshot();
        } else {
          trendFailed = true;
          inspectingTrend = false;
          inspectedTrendCny = null;
        }
      }
    } finally {
      trendLoading = false;
      if (!_dead) {
        if (_active) {
          notifyListeners();
        } else {
          _paintPending = true;
        }
        if (_trendAgain && _trendEnabled) {
          _trendAgain = false;
          unawaited(loadTrend());
        }
      }
    }
  }

  bool _active = true;
  bool _dirty = false;
  bool _paintPending = false;
  bool get hasDeferredRefresh => _dirty;

  /// Returns whether activation consumed a pending refresh (bypassing tab TTL).
  bool setActive(bool active) {
    if (_dead) return false;
    _active = active;
    if (!active) endTrendInspection();
    if (active && _paintPending) {
      _paintPending = false;
      notifyListeners();
    }
    if (!active || !_dirty) return false;
    _dirty = false;
    unawaited(load(force: true));
    return true;
  }

  bool _busy = false;
  bool _refreshAgain = false;
  bool _hasSnapshot = false;

  void _applySnapshot(WalletDto data) {
    totalBal = data.totalBal;
    dailyAmountCny = data.dailyAmountCny;
    dailyPercentage = data.dailyPercentage;
    totalBalUsd = data.totalBalUsd;
    trxAddr = data.trxAddr;
    coins = data.coins;
    _hasSnapshot = true;
  }

  Future<void> load({bool force = false}) async {
    if (_dead) return;
    if (!_sameAccount) {
      _clearAccountSnapshot();
      if (_active) notifyListeners();
      return;
    }
    if (!_active) {
      _dirty = true;
      return;
    }
    if (_busy) {
      _refreshAgain = _refreshAgain || force;
      return;
    }

    _busy = true;
    loading = !_hasSnapshot;
    loadFailed = false;
    lastError = null;
    if (_active) notifyListeners();

    try {
      final data = await _repo.getWallet().timeout(const Duration(seconds: 6));
      if (_dead) return;
      if (!_sameAccount) {
        _clearAccountSnapshot();
        return;
      }
      _applySnapshot(data);
      if (_trendEnabled) unawaited(loadTrend());
      if (!_active) _paintPending = true;
      loadFailed = false;
      lastError = null;
      loading = false;
      if (_active) notifyListeners();
    } catch (e, st) {
      if (_dead) return;
      if (!_sameAccount) {
        _clearAccountSnapshot();
        return;
      }
      loadFailed = !_hasSnapshot;
      lastError = e;
      if (!_hasSnapshot && coins.isEmpty) {
        // Preserve 99chat's two product rows without inventing account data.
        // Balance/fiat/rate/address all stay unknown until a real backend exists.
        coins = List<CoinDto>.from(walletUnavailableProductCoins);
      }
      if (kDebugMode) {
        debugPrint('load wallet error: $e\n$st');
      }
    } finally {
      _busy = false;
      loading = false;
      if (!_dead && _active) notifyListeners();
      if (_refreshAgain && !_dead) {
        _refreshAgain = false;
        unawaited(load(force: true));
      }
    }
  }

  void toggleBal() {
    inspectingTrend = false;
    inspectedTrendCny = null;
    showBal = !showBal;
    notifyListeners();
  }

  void _clearAccountSnapshot() {
    inspectingTrend = false;
    inspectedTrendCny = null;
    trend = null;
    trendFailed = false;
    _trendAgain = false;
    totalBal = '--';
    dailyAmountCny = '--';
    dailyPercentage = '--';
    totalBalUsd = '';
    trxAddr = '';
    coins = [];
    _hasSnapshot = false;
    _dirty = false;
    _refreshAgain = false;
    loadFailed = false;
    lastError = null;
  }

  @override
  void dispose() {
    _dead = true;
    _balanceSubscription?.cancel();
    super.dispose();
  }
}
