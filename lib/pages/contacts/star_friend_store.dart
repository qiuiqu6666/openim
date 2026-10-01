import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

class StarFriend {
  StarFriend.fromJson(Map<String, dynamic> json)
      : friendUserID = json['friendUserID'] as String,
        starred = json['starred'] as bool,
        version = (json['version'] as num).toInt(),
        updatedAt = (json['updatedAt'] as num).toInt();
  final String friendUserID;
  final bool starred;
  final int version;
  final int updatedAt;
  Map<String, dynamic> toJson() => {
        'friendUserID': friendUserID,
        'starred': starred,
        'version': version,
        'updatedAt': updatedAt
      };
}

class StarFriendConflict implements Exception {
  StarFriendConflict(this.current);
  final StarFriend current;
}

class StarFriendApi {
  StarFriendApi({Dio? client}) : client = client ?? dio;
  final Dio client;
  Options _options(String token) => Options(headers: {
        'token': token,
        'operationID': const Uuid().v4(),
        'Content-Type': 'application/json',
      });
  Map<String, dynamic> _data(Response response) {
    final body = Map<String, dynamic>.from(response.data as Map);
    if (body['errCode'] == 20016) {
      throw StarFriendConflict(
          StarFriend.fromJson(Map<String, dynamic>.from(body['data'] as Map)));
    }
    if (body['errCode'] != 0) throw StateError('starFriendRequestFailed');
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<StarFriend> set(
      String id, bool starred, int version, String token) async {
    return StarFriend.fromJson(_data(await client.put(
        '${Config.appAuthUrl}/chat/star-friends/${Uri.encodeComponent(id)}',
        data: {'starred': starred, 'version': version},
        options: _options(token))));
  }

  Future<Map<String, dynamic>> page(int cursor, String token) async =>
      _data(await client.get('${Config.appAuthUrl}/chat/star-friends',
          queryParameters: {'updatedAfter': cursor, 'limit': 500},
          options: _options(token)));
}

/// Owned by the logged-in contacts controller; snapshots are account scoped.
class StarFriendStore {
  StarFriendStore({StarFriendApi? api, void Function(String)? showMessage})
      : api = api ?? StarFriendApi(),
        showMessage = showMessage ?? IMViews.showToast;
  final StarFriendApi api;
  final void Function(String) showMessage;
  final records = <String, StarFriend>{}.obs;
  final pending = <String>{}.obs;
  String? _owner;
  int _syncAt = 0;
  bool _closed = false;
  Future<void>? _sync;
  bool isStarred(String id) => records[id]?.starred == true;
  bool _current(String owner) =>
      !_closed && DataSp.userID == owner && _owner == owner;
  String get _cacheKey => 'starFriends:${Config.appAuthUrl}:$_owner';

  void _loadAccount() {
    final owner = DataSp.userID;
    if (_owner == owner) return;
    _owner = owner;
    records.clear();
    pending.clear();
    _syncAt = 0;
    if (owner == null) return;
    try {
      final cache = SpUtil().getObject(_cacheKey);
      if (cache != null) {
        for (final item in cache['stars'] as List) {
          final record =
              StarFriend.fromJson(Map<String, dynamic>.from(item as Map));
          records[record.friendUserID] = record;
        }
        _syncAt = (cache['syncAt'] as num).toInt();
      }
    } catch (_) {
      records.clear();
      _syncAt = 0;
    }
  }

  void _save() {
    if (_owner != null && _current(_owner!)) {
      SpUtil().putObject(_cacheKey, {
        'syncAt': _syncAt,
        'stars': records.values.map((v) => v.toJson()).toList()
      });
    }
  }

  void apply(StarFriend record) {
    final previous = records[record.friendUserID];
    if (previous == null || record.version > previous.version) {
      records[record.friendUserID] = record;
    }
  }

  void handleNotification(String raw) {
    if (_closed) return;
    _loadAccount();
    try {
      final message = jsonDecode(raw) as Map;
      if (message['key'] != 'starFriendChanged' ||
          _owner == null ||
          message['sendUserID'] != _owner ||
          message['recvUserID'] != _owner) {
        return;
      }
      final data = message['data'];
      apply(StarFriend.fromJson(Map<String, dynamic>.from(
          (data is String ? jsonDecode(data) : data) as Map)));
      _save();
    } catch (_) {/* Ignore malformed or unrelated business notifications. */}
  }

  Future<void> refresh() {
    if (_closed) return Future.value();
    _loadAccount();
    final owner = _owner;
    return _sync ??= _refresh().whenComplete(() {
      _sync = null;
      if (!_closed && DataSp.userID != owner) unawaited(refresh());
    });
  }

  Future<void> _refresh() async {
    _loadAccount();
    final owner = _owner;
    final token = DataSp.chatToken;
    if (owner == null || token == null) return;
    var cursor = _syncAt;
    try {
      while (_current(owner)) {
        final page = await api.page(cursor, token);
        if (!_current(owner)) return;
        final items = (page['stars'] as List)
            .map(
                (v) => StarFriend.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList();
        for (final item in items) {
          apply(item);
        }
        if (items.length < 500) {
          _syncAt = (page['syncAt'] as num).toInt();
          _save();
          return;
        }
        final next = (page['syncAt'] as num).toInt();
        if (next <= cursor) {
          throw StateError('Star friend cursor did not advance');
        }
        cursor = next;
      }
    } catch (_) {
      /* Retain snapshot and watermark; retry on resume/reconnect. */
    }
  }

  Future<void> toggle(String id) async {
    _loadAccount();
    final owner = _owner;
    final token = DataSp.chatToken;
    if (_closed || owner == null || token == null || pending.contains(id)) {
      return;
    }
    if (id.isEmpty || id.length > 64 || id.contains(':') || id == owner) return;
    pending.add(id);
    try {
      final result =
          await api.set(id, !isStarred(id), records[id]?.version ?? 0, token);
      if (_current(owner)) {
        apply(result);
        _save();
      }
    } on StarFriendConflict catch (error) {
      if (_current(owner)) {
        // Adopt the authoritative conflict response, unless a newer push has
        // already arrived while this request was in flight.
        if ((records[id]?.version ?? -1) <= error.current.version) {
          records[id] = error.current;
        }
        _save();
        showMessage('starFriendConflict'.tr);
      }
    } catch (_) {
      if (_current(owner)) showMessage('starFriendRequestFailed'.tr);
    } finally {
      if (_current(owner)) pending.remove(id);
    }
  }

  void dispose() {
    _closed = true;
    records.clear();
    pending.clear();
  }
}
