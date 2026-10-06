import 'dart:convert';

import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

class FundPendingConflict implements Exception {
  const FundPendingConflict();
}

/// Keeps the same idempotency key after a timeout, page close, or app restart.
/// Payment passwords are never included in the saved request.
class FundPendingStore {
  FundPendingStore({String? accountKey}) : _accountKey = accountKey;
  final String? _accountKey;
  static final _locks = <String, Lock>{};

  String _key(String scope) {
    final account =
        _accountKey ?? '${Config.appAuthUrl}:${DataSp.userID ?? ''}';
    if (_accountKey == null && (DataSp.userID ?? '').isEmpty) {
      throw StateError('Please sign in again');
    }
    return 'fund-pending:$account:$scope';
  }

  Future<Map<String, dynamic>?> read(String scope) async {
    final value =
        (await SharedPreferences.getInstance()).getString(_key(scope));
    if (value == null) return null;
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> save(String scope, Map<String, dynamic> request) async {
    if (const ['payPassword', 'password', 'verifyCode', 'verifyChallengeID']
        .any(request.containsKey)) {
      throw ArgumentError('Payment credentials cannot be persisted');
    }
    final key = _key(scope);
    final encoded = jsonEncode(request);
    await (_locks[key] ??= Lock()).synchronized(() async {
      final preferences = await SharedPreferences.getInstance();
      final existing = preferences.getString(key);
      if (existing != null) {
        final previous = Map<String, dynamic>.from(jsonDecode(existing) as Map);
        final incoming = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
        // A second open page must not replace a still-pending payment. Display
        // names may change, but every field sent to the backend stays fixed.
        previous.remove('recipientName');
        incoming.remove('recipientName');
        if (!_sameRequest(previous, incoming)) {
          throw const FundPendingConflict();
        }
      }
      final stored = await preferences.setString(key, encoded);
      if (!stored) throw StateError('Cannot save payment request');
    });
  }

  Future<void> clear(String scope, {String? clientOrderID}) async {
    final key = _key(scope);
    await (_locks[key] ??= Lock()).synchronized(() async {
      final preferences = await SharedPreferences.getInstance();
      final existing = preferences.getString(key);
      if (existing == null) return;
      if (clientOrderID != null &&
          (jsonDecode(existing) as Map)['clientOrderID'] != clientOrderID) {
        throw const FundPendingConflict();
      }
      final removed = await preferences.remove(key);
      if (!removed) throw StateError('Cannot clear payment request');
    });
  }

  static bool _sameRequest(
      Map<String, dynamic> left, Map<String, dynamic> right) {
    if (left.length != right.length) return false;
    return left.entries.every((entry) => right[entry.key] == entry.value);
  }
}
