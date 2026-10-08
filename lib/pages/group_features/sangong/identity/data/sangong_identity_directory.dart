import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../models/sangong_display_identity.dart';
export '../models/sangong_display_identity.dart';

typedef SangongIdentitySession = (String?, String?, String);

/// Public account comes from Chat profiles; avatar comes from the IM SDK.
/// Visible rows coalesce requests into batches and share a bounded login cache.
class SangongIdentityDirectory {
  SangongIdentityDirectory({
    Future<List<UserFullInfo>?> Function(List<String>)? profiles,
    Future<List<PublicUserInfo>> Function(List<String>)? imUsers,
    SangongIdentitySession Function()? session,
  })  : _profiles = profiles ??
            ((ids) => Apis.getUserFullInfo(
                userIDList: ids,
                showErrorToast: false,
                pageNumber: 1,
                showNumber: ids.length)),
        _imUsers = imUsers ??
            ((ids) =>
                OpenIM.iMManager.userManager.getUsersInfo(userIDList: ids)),
        _session = session ?? _defaultSession;
  static SangongIdentitySession _defaultSession() {
    final endpoint = Config.appAuthUrl;
    try {
      final user = DataSp.userID;
      if (user == null || user.isEmpty || user != OpenIM.iMManager.userID) {
        return (null, null, endpoint);
      }
      return (user, DataSp.chatToken, endpoint);
    } catch (_) {
      return (null, null, endpoint);
    }
  }

  static final shared = SangongIdentityDirectory();
  final Future<List<UserFullInfo>?> Function(List<String>) _profiles;
  final Future<List<PublicUserInfo>> Function(List<String>) _imUsers;
  final SangongIdentitySession Function() _session;
  final _cache = <String, (DateTime, SangongDisplayIdentity)>{};
  final _pending = <String, Completer<SangongDisplayIdentity?>>{};
  final _queued = <String>{};
  SangongIdentitySession? _owner;
  int _generation = 0;
  bool _scheduled = false;
  SangongIdentitySession get session {
    _sync();
    return _owner!;
  }

  bool get _authenticated =>
      _owner?.$1?.isNotEmpty == true && _owner?.$2?.isNotEmpty == true;
  void _sync() {
    final current = _session();
    if (current == _owner) return;
    _owner = current;
    _generation++;
    _cache.clear();
    _queued.clear();
    for (final request in _pending.values) {
      if (!request.isCompleted) request.complete(null);
    }
    _pending.clear();
  }

  SangongDisplayIdentity? peek(String id) {
    _sync();
    final cached = _cache[id];
    if (!_authenticated || cached == null) return null;
    if (DateTime.now().difference(cached.$1) > const Duration(minutes: 1)) {
      _cache.remove(id);
      return null;
    }
    return cached.$2;
  }

  Future<SangongDisplayIdentity?> resolve(String id) {
    _sync();
    if (!_authenticated || id.trim().isEmpty) return Future.value(null);
    final cached = peek(id);
    if (cached != null) return Future.value(cached);
    final pending = _pending[id];
    if (pending != null) return pending.future;
    final request = Completer<SangongDisplayIdentity?>();
    _pending[id] = request;
    _queued.add(id);
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_flush);
    }
    return request.future;
  }

  Future<List<UserFullInfo>> _loadProfiles(List<String> ids) async {
    try {
      return await _profiles(ids) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<List<PublicUserInfo>> _loadIMUsers(List<String> ids) async {
    try {
      return await _imUsers(ids);
    } catch (_) {
      return [];
    }
  }

  Future<void> _flush() async {
    _scheduled = false;
    _sync();
    final ids = _queued.toList();
    _queued.clear();
    final generation = _generation;
    for (var offset = 0; offset < ids.length; offset += 50) {
      final batch = ids.skip(offset).take(50).toList();
      final requests = {for (final id in batch) id: _pending[id]};
      final results =
          await Future.wait([_loadProfiles(batch), _loadIMUsers(batch)]);
      _sync();
      if (generation != _generation) return;
      final accounts = <String, UserFullInfo>{
        for (final user in results[0] as List<UserFullInfo>)
          if (batch.contains(user.userID)) user.userID!: user
      };
      final avatars = <String, PublicUserInfo>{
        for (final user in results[1] as List<PublicUserInfo>)
          if (batch.contains(user.userID)) user.userID!: user
      };
      for (final id in batch) {
        final user = SangongDisplayIdentity(
            userID: id,
            account: accounts[id]?.account?.trim() ?? '',
            nickname: avatars[id]?.nickname?.trim() ??
                accounts[id]?.nickname?.trim() ??
                '',
            faceURL: avatars[id]?.faceURL?.trim() ?? '');
        {
          _cache.remove(id);
          _cache[id] = (DateTime.now(), user);
          while (_cache.length > 512) {
            _cache.remove(_cache.keys.first);
          }
        }
        if (identical(requests[id], _pending[id])) {
          _pending.remove(id);
          requests[id]?.complete(user);
        }
      }
    }
  }
}
