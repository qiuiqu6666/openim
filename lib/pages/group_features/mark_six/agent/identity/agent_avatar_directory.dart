import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../../../models/group_feature_context.dart';

typedef AgentAvatarLoader = Future<List<PublicUserInfo>> Function(List<String>);

/// Optional avatar enrichment for this page's authorized account and group.
/// Visible rows share bounded SDK batches, without querying the entire downline.
class AgentAvatarDirectory {
  AgentAvatarDirectory(this.context, {AgentAvatarLoader? loadUsers})
      : _loadUsers = loadUsers ??
            ((ids) =>
                OpenIM.iMManager.userManager.getUsersInfo(userIDList: ids));

  final GroupFeatureContext context;
  final AgentAvatarLoader _loadUsers;
  final _cache = <String, (DateTime, String?)>{};
  final _pending = <String, Completer<String?>>{};
  final _queued = <String>{};
  void Function()? _cancelLookup;
  bool _closed = false, _running = false;

  bool get current =>
      !_closed &&
      context.sessionCurrent() &&
      context.capabilitiesCurrent() &&
      context.capabilities.markSix.canOpenAgent;

  (DateTime, String?)? _cached(String id) {
    final cached = _cache[id];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 1)) {
      return cached;
    }
    _cache.remove(id);
    return null;
  }

  String? peek(String userID) => current ? _cached(userID.trim())?.$2 : null;

  Future<String?> resolve(String userID) {
    final id = userID.trim();
    if (!current || id.isEmpty) return Future.value(null);
    final cached = _cached(id);
    if (cached != null) return Future.value(cached.$2);
    final existing = _pending[id];
    if (existing != null) return existing.future;
    final request = Completer<String?>();
    _pending[id] = request;
    _queued.add(id);
    if (!_running) {
      _running = true;
      scheduleMicrotask(_drain);
    }
    return request.future;
  }

  Future<void> _drain() async {
    try {
      while (current && _queued.isNotEmpty) {
        final ids = _queued.take(50).toList();
        _queued.removeAll(ids);
        final users = await _lookup(ids);
        if (!current) break;
        final urls = {
          for (final user in users)
            if (ids.contains(user.userID) &&
                user.faceURL?.trim().isNotEmpty == true)
              user.userID!: user.faceURL!.trim(),
        };
        for (final id in ids) {
          _cache.remove(id);
          _cache[id] = (DateTime.now(), urls[id]);
          while (_cache.length > 512) {
            _cache.remove(_cache.keys.first);
          }
          _pending.remove(id)?.complete(urls[id]);
        }
      }
    } finally {
      _running = false;
      if (!current) _clear();
    }
  }

  Future<List<PublicUserInfo>> _lookup(List<String> ids) async {
    final result = Completer<List<PublicUserInfo>>();
    final timer = Timer(const Duration(seconds: 8), () => result.complete([]));
    void finish(List<PublicUserInfo> users) {
      timer.cancel();
      if (!result.isCompleted) result.complete(users);
    }

    _cancelLookup = () => finish([]);
    // Optional photos must never block the business list or show a toast.
    Future.sync(() => _loadUsers(ids))
        .then(finish, onError: (Object _, StackTrace __) => finish([]));
    try {
      return await result.future;
    } finally {
      timer.cancel();
      _cancelLookup = null;
    }
  }

  void _clear() {
    _cancelLookup?.call();
    _cache.clear();
    _queued.clear();
    for (final request in _pending.values) {
      request.complete(null);
    }
    _pending.clear();
  }

  void dispose() {
    _closed = true;
    _clear();
  }
}
