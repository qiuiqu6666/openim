import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Searches IM identity without widening the server-authorized team scope.
class SangongTeamUserSearch {
  SangongTeamUserSearch({
    Future<List<PublicUserInfo>> Function(List<String>)? profiles,
    Future<List<FriendInfo>> Function(String)? friends,
  })  : _profiles = profiles ??
            ((ids) =>
                OpenIM.iMManager.userManager.getUsersInfo(userIDList: ids)),
        _friends = friends ??
            ((query) => OpenIM.iMManager.friendshipManager.searchFriends(
                keywordList: [query],
                isSearchUserID: true,
                isSearchNickname: true,
                isSearchRemark: true));
  final Future<List<PublicUserInfo>> Function(List<String>) _profiles;
  final Future<List<FriendInfo>> Function(String) _friends;
  final _names = <String, String>{};
  int _generation = 0;
  bool _closed = false;
  final _cancelPending = <void Function()>{};

  Future<T?> _wait<T>(Future<T> work) {
    if (_closed) return Future.value();
    final result = Completer<T?>();
    late final Timer timer;
    late final void Function() cancel;
    void finish(T? value, [Object? error, StackTrace? stack]) {
      if (result.isCompleted) return;
      timer.cancel();
      _cancelPending.remove(cancel);
      if (error != null) {
        result.completeError(error, stack);
      } else {
        result.complete(value);
      }
    }

    cancel = () => finish(null);
    timer = Timer(const Duration(seconds: 8),
        () => finish(null, TimeoutException('OpenIM search timed out')));
    _cancelPending.add(cancel);
    work.then((value) => finish(value),
        onError: (Object error, StackTrace stack) =>
            finish(null, error, stack));
    return result.future;
  }

  Future<void> load(Set<String> ids, bool Function() isCurrent) async {
    final generation = ++_generation;
    _names.removeWhere((id, _) => !ids.contains(id));
    final pending = ids.toList();
    for (var offset = 0; offset < pending.length; offset += 50) {
      if (_closed || generation != _generation || !isCurrent()) return;
      final batch = pending.skip(offset).take(50).toList();
      final rows = await _wait(_profiles(batch));
      if (rows == null ||
          _closed ||
          generation != _generation ||
          !isCurrent()) {
        return;
      }
      for (final row in rows) {
        if (batch.contains(row.userID)) {
          _names[row.userID!] = row.nickname ?? '';
        }
      }
    }
  }

  bool matches(String userID, String query) {
    final key = query.trim().toLowerCase();
    return userID.toLowerCase().contains(key) ||
        (_names[userID]?.toLowerCase().contains(key) ?? false);
  }

  Future<Set<String>> searchFriends(String query, Set<String> teamIDs) async {
    if (_closed || query.trim().isEmpty) return {};
    final rows = await _wait(_friends(query.trim()));
    if (_closed || rows == null) return {};
    return {
      for (final row in rows)
        if (teamIDs.contains(row.userID)) row.userID!
    };
  }

  void close() {
    _closed = true;
    for (final cancel in _cancelPending.toList()) {
      cancel();
    }
    ++_generation;
    _names.clear();
  }
}
