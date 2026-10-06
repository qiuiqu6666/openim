import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import '../../../services/fund_models.dart';

/// Durable default currency shared by all fund payments for one account/server.
/// This preference never replaces a submitted transaction's frozen currency.
class FundPaymentPreferences {
  FundPaymentPreferences({required this.accountID, required this.serverURL});

  final String accountID, serverURL;
  static final _locks = <String, Lock>{};

  String get _key {
    if (accountID.isEmpty) throw StateError('Please sign in again');
    return 'fund-payment-currency:${jsonEncode([serverURL, accountID])}';
  }

  Lock get _lock => _locks[_key] ??= Lock();

  Future<FundCurrency?> read() => _lock.synchronized(() async {
        final raw = (await SharedPreferences.getInstance()).get(_key);
        for (final currency in FundCurrency.values) {
          if (raw == currency.code) return currency;
        }
        return null;
      });

  Future<void> save(FundCurrency currency) => _lock.synchronized(() async {
        final preferences = await SharedPreferences.getInstance();
        if (!await preferences.setString(_key, currency.code)) {
          throw StateError('Cannot save default payment currency');
        }
      });
}
