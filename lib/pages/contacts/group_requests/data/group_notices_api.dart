import 'group_notice_migration.dart';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

typedef NoticeRequest = Future<dynamic> Function(
    String path, Map<String, dynamic> body);

class GroupNoticePage {
  GroupNoticePage.fromJson(Map<String, dynamic> data)
      : reset = data['reset'] == true,
        cursor = data['nextCursor'] as String? ?? '',
        snapshot = (data['snapshotTime'] as num?)?.toInt() ?? 0,
        revision = (data['revision'] as num?)?.toInt() ?? 0,
        raw = (data['items'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
  final bool reset;
  final String cursor;
  final int snapshot, revision;
  final List<Map<String, dynamic>> raw;
  List<GroupApplicationInfo> get items =>
      raw.map(GroupApplicationInfo.fromJson).toList();
}

/// Server visibility is authoritative. Never fall back to local-only deletion.
class GroupNoticesApi {
  GroupNoticesApi({NoticeRequest? request}) : _request = request;
  final NoticeRequest? _request;
  final _owner = OpenIM.iMManager.userID;
  final _token = DataSp.imToken;
  final _chatToken = DataSp.chatToken;
  final _base = Config.imApiUrl;
  final _cancel = CancelToken();
  bool get isCurrent =>
      !_cancel.isCancelled &&
      _owner == OpenIM.iMManager.userID &&
      _token == DataSp.imToken &&
      _chatToken == DataSp.chatToken &&
      _base == Config.imApiUrl;
  void close() => _cancel.cancel();
  Future<void>? _migration;
  Future<Map<String, dynamic>> _post(
      String action, Map<String, dynamic> body) async {
    try {
      await (_migration ??= migrateGroupNotices(_owner, _send));
    } catch (_) {
      _migration = null;
      rethrow;
    }
    return _send(action, body);
  }

  Future<Map<String, dynamic>> _send(
      String action, Map<String, dynamic> body) async {
    if (!isCurrent) throw StateError('Notice session changed');
    final path = '$_base/group/notices/$action';
    final data = _request != null
        ? await _request(path, body)
        : await HttpUtil.post(
            path,
            data: body,
            showErrorToast: false,
            cancelToken: _cancel,
            options: Options(
                headers: {'token': _token},
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15)),
          );
    if (!isCurrent) throw StateError('Notice session changed');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<GroupNoticePage> list({String cursor = ''}) async =>
      GroupNoticePage.fromJson(
          await _post('list', {'cursor': cursor, 'limit': 20}));
  Future<Map<String, dynamic>> state({bool unread = true}) =>
      _post('state', {'includeUnread': unread});
  Future<void> clear(int snapshot) async {
    await _post('clear', {'through': snapshot});
  }

  Future<void> read(int snapshot) async {
    await _post('read', {'through': snapshot});
  }

  Future<void> delete(GroupApplicationInfo info) async {
    final time = info.reqTime ?? 0;
    await _post('delete', {
      'groupID': info.groupID,
      'userID': info.userID,
      'reqTime': time < 100000000000 ? time * 1000 : time
    });
  }

  Future<Map<String, dynamic>?> detail(GroupApplicationInfo info) async {
    final time = info.reqTime ?? 0;
    final result = await _post('detail', {
      'groupID': info.groupID,
      'userID': info.userID,
      'reqTime': time < 100000000000 ? time * 1000 : time,
    });
    final item = result['item'];
    return item is Map ? Map<String, dynamic>.from(item) : null;
  }
}
