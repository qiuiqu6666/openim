import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredAuthCredentials {
  const StoredAuthCredentials({
    this.account = '',
    this.areaCode = '+86',
    this.loginType = 0,
    this.password,
    this.rememberPassword = true,
  });

  final String account;
  final String areaCode;
  final int loginType;
  final String? password;
  final bool rememberPassword;
}

/// Serializes encrypted credential writes across login page lifetimes.
class AuthCredentialsStore {
  AuthCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static final instance = AuthCredentialsStore();
  static const credentialsKey = 'auth.remembered_credentials';
  static const rememberKey = 'auth.remember_password';

  final FlutterSecureStorage _storage;
  Future<void> _tail = Future.value();
  bool? _rememberOverride;
  int _preferenceRevision = 0;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Map<String, dynamic>? _decode(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<bool> _rememberEnabled() async =>
      _rememberOverride ?? (await _storage.read(key: rememberKey) != 'false');

  Future<StoredAuthCredentials> load() => _serialized(() async {
        final record = _decode(await _storage.read(key: credentialsKey));
        final remember = await _rememberEnabled();
        return StoredAuthCredentials(
          account: record?['account'] is String ? record!['account'] : '',
          areaCode: record?['areaCode'] is String ? record!['areaCode'] : '+86',
          loginType: record?['loginType'] is int ? record!['loginType'] : 0,
          password: remember && record?['password'] is String
              ? record!['password']
              : null,
          rememberPassword: remember,
        );
      });

  /// Updates the in-memory preference before waiting for any pending write.
  Future<void> setRememberPassword(bool remember) {
    _rememberOverride = remember;
    final revision = ++_preferenceRevision;
    return _serialized(() async {
      await _storage.write(key: rememberKey, value: remember.toString());
      if (!remember) {
        final record = _decode(await _storage.read(key: credentialsKey));
        if (record == null) {
          await _storage.delete(key: credentialsKey);
        } else if (record.remove('password') != null) {
          await _storage.write(key: credentialsKey, value: jsonEncode(record));
        }
      }
      if (revision == _preferenceRevision) _rememberOverride = null;
    });
  }

  Future<void> _restorePrevious(String? previous) async {
    final record = _decode(previous);
    if (record != null && !await _rememberEnabled()) {
      record.remove('password');
      previous = jsonEncode(record);
    }
    if (previous == null) {
      await _storage.delete(key: credentialsKey);
    } else {
      await _storage.write(key: credentialsKey, value: previous);
    }
  }

  /// Call only after the SDK has accepted the same login session.
  /// A superseded attempt restores the previous record before the next write.
  Future<bool> saveSuccessful({
    required String account,
    required String areaCode,
    required int loginType,
    required String? password,
    required bool rememberPassword,
    required bool Function() isCurrent,
  }) =>
      _serialized(() async {
        if (!isCurrent()) return false;
        final previous = await _storage.read(key: credentialsKey);
        if (!isCurrent()) return false;
        final remember = rememberPassword && await _rememberEnabled();
        if (!isCurrent()) return false;
        final saved = _decode(previous);
        final sameAccount = saved?['account'] == account &&
            saved?['areaCode'] == areaCode &&
            saved?['loginType'] == loginType;
        final remembered = password ??
            (sameAccount && saved?['password'] is String
                ? saved!['password'] as String
                : null);
        final record = <String, dynamic>{
          'account': account,
          'areaCode': areaCode,
          'loginType': loginType,
          if (remember && remembered != null) 'password': remembered,
        };
        await _storage.write(key: credentialsKey, value: jsonEncode(record));
        if (!isCurrent()) {
          await _restorePrevious(previous);
          return false;
        }
        if (!await _rememberEnabled() && record.remove('password') != null) {
          await _storage.write(key: credentialsKey, value: jsonEncode(record));
        }
        if (!isCurrent()) {
          await _restorePrevious(previous);
          return false;
        }
        return true;
      });

  /// A reset can update only the credentials for the matching remembered phone.
  Future<bool> updatePasswordIfRemembered({
    required String account,
    required String areaCode,
    required String password,
    required bool Function() isCurrent,
  }) =>
      _serialized(() async {
        if (!isCurrent() || !await _rememberEnabled()) return false;
        final previous = await _storage.read(key: credentialsKey);
        final record = _decode(previous);
        if (!isCurrent() ||
            record == null ||
            record['account'] != account.trim() ||
            record['areaCode'] != areaCode ||
            record['loginType'] != 0) {
          return false;
        }
        record['password'] = password;
        await _storage.write(key: credentialsKey, value: jsonEncode(record));
        if (!isCurrent()) {
          await _restorePrevious(previous);
          return false;
        }
        if (!await _rememberEnabled()) {
          record.remove('password');
          await _storage.write(key: credentialsKey, value: jsonEncode(record));
          return false;
        }
        if (!isCurrent()) {
          await _restorePrevious(previous);
          return false;
        }
        return true;
      });
}
