import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../wallet_share_service.dart';

enum DepositSaveResult { saved, alreadySaved, failed }

/// Content-based receipt: no address is stored in preferences. Failed writes
/// remain retryable; concurrent views share one gallery operation.
class WalletDepositSaveOnce {
  static final instance = WalletDepositSaveOnce();
  final _pending = <String, Future<DepositSaveResult>>{};
  final _saved = <String>{};

  Future<DepositSaveResult> save({
    required String currency,
    required String network,
    required String address,
    required Future<WalletSaveImgResult> Function() write,
  }) {
    final key = 'wallet.deposit.qr.saved.v1.${sha256.convert(
      utf8.encode(jsonEncode([currency, network, address])),
    )}';
    return _pending.putIfAbsent(key, () => _save(key, write));
  }

  Future<DepositSaveResult> _save(
      String key, Future<WalletSaveImgResult> Function() write) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (_saved.contains(key) || preferences.getBool(key) == true) {
        return DepositSaveResult.alreadySaved;
      }
      if (await write() != WalletSaveImgResult.success) {
        return DepositSaveResult.failed;
      }
      // Keep the in-memory receipt even if persistence fails after gallery
      // success; reporting failure here would invite duplicate gallery writes.
      try {
        if (!await preferences.setBool(key, true)) _saved.add(key);
      } catch (_) {
        _saved.add(key);
      }
      return DepositSaveResult.saved;
    } catch (_) {
      return DepositSaveResult.failed;
    } finally {
      _pending.remove(key);
    }
  }
}
