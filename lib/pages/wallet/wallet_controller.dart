import 'dart:async';

import 'package:flutter/foundation.dart';

import 'wallet_repository.dart';

class WalletController extends ChangeNotifier {
  final WalletRepository _repo;

  WalletController({WalletRepository? repo})
      : _repo = repo ?? const UnavailableWalletRepository();

  bool loading = false;
  bool loadFailed = false;
  bool showBal = true;
  Object? lastError;

  // 99chat 使用 0.00 作为真实接口加载前的初值；当前 OpenIM Wallet 后端尚未
  // 接入，不能把未知余额伪装成真实 0，因此这里只保留相同字段语义并显示未知态。
  String totalBal = '--';
  String totalBalUsd = '';
  String trxAddr = '';
  List<CoinDto> coins = [];

  bool _dead = false;
  bool _active = true;
  bool _dirty = false;
  bool _paintPending = false;
  bool get hasDeferredRefresh => _dirty;

  /// Returns whether activation consumed a pending refresh (bypassing tab TTL).
  bool setActive(bool active) {
    if (_dead) return false;
    _active = active;
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
    totalBalUsd = data.totalBalUsd;
    trxAddr = data.trxAddr;
    coins = data.coins;
    _hasSnapshot = true;
  }

  Future<void> load({bool force = false}) async {
    if (_dead) return;
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
      _applySnapshot(data);
      if (!_active) _paintPending = true;
      loadFailed = false;
      lastError = null;
      loading = false;
      if (_active) notifyListeners();
    } catch (e, st) {
      if (_dead) return;
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
    showBal = !showBal;
    notifyListeners();
  }

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }
}
