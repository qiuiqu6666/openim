import 'package:openim_common/openim_common.dart';

import '../../../../contacts/search/contact_search_source.dart';

/// Resolves public accounts through the existing authenticated contact search.
/// The caller retains the group/session permission boundary for every request.
class SangongAccountIdentityResolver {
  SangongAccountIdentityResolver({
    required bool Function() isCurrent,
    Object? Function()? scopeToken,
    ContactSearchSource? source,
  })  : _isCurrent = isCurrent,
        _scopeToken = scopeToken,
        _source = source ?? ContactSearchSource();

  final bool Function() _isCurrent;
  final Object? Function()? _scopeToken;
  final ContactSearchSource _source;
  int _generation = 0;
  bool _closed = false;

  bool _accepts(int generation, Object? scope) =>
      !_closed &&
      generation == _generation &&
      _isCurrent() &&
      scope == _scopeToken?.call();

  /// Existing saved IDs are preserved even when their shape resembles an
  /// account. New public account inputs never become an IM ID by inference.
  Future<String?> resolve(
    String input, {
    String? knownUserId,
    bool allowInternalUserId = true,
  }) async {
    final generation = ++_generation;
    final scope = _scopeToken?.call();
    if (!_accepts(generation, scope)) return null;
    final value = input.trim();
    if (value.isEmpty || RegExp(r'\s').hasMatch(value)) {
      throw StateError('请填写公开账号名或用户 ID');
    }
    if (allowInternalUserId &&
        !value.startsWith('@') &&
        value == knownUserId?.trim()) {
      return value;
    }
    final account = normalizePublicAccountSearch(value);
    if (account == null) {
      if (allowInternalUserId && !value.contains('@')) return value;
      throw StateError('公开账号名须为 10 位小写字母或数字');
    }
    try {
      final users = await _source.users('@$account', 1);
      if (!_accepts(generation, scope)) return null;
      final matches = <String>{
        for (final user in users ?? <UserFullInfo>[])
          if (normalizePublicAccountSearch(user.account ?? '') == account &&
              user.userID?.trim().isNotEmpty == true)
            user.userID!.trim(),
      };
      if (matches.isEmpty) throw StateError('未找到该公开账号对应的用户');
      if (matches.length != 1) throw StateError('账号信息不唯一，请刷新后重试');
      return matches.single;
    } catch (_) {
      if (!_accepts(generation, scope)) return null;
      rethrow;
    }
  }

  void cancel() => ++_generation;

  void close() {
    _closed = true;
    cancel();
  }
}
