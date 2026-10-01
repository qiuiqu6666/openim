import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

class PresenceVisibilityStore {
  PresenceVisibilityStore({Dio? client, void Function(String)? notify})
      : client = client ?? dio,
        notify = notify ?? IMViews.showToast;
  final Dio client;
  final void Function(String) notify;
  final showLastSeen = true.obs;
  final ready = false.obs;
  final busy = false.obs;
  final failed = false.obs;
  int version = -1;
  int updatedAt = 0;
  bool _closed = false;
  final String? owner = DataSp.userID;
  bool get _valid => !_closed && owner != null && owner == DataSp.userID;
  String get _url => '${Config.appAuthUrl}/chat/users/presence-visibility';
  Options get _options => Options(headers: {
        'token': DataSp.chatToken,
        'operationID': const Uuid().v4(),
        'Content-Type': 'application/json',
      });
  void _apply(Map data) {
    final next = (data['version'] as num).toInt();
    if (next < version) return;
    showLastSeen.value = data['showLastSeen'] as bool;
    version = next;
    updatedAt = (data['updatedAt'] as num).toInt();
    ready.value = true;
    failed.value = false;
  }

  Future<void> refresh() async {
    if (!_valid || busy.value) return;
    busy.value = true;
    try {
      final response = await client.get(_url, options: _options);
      if (!_valid) return;
      final body = response.data as Map;
      if (body['errCode'] != 0) throw StateError('request failed');
      _apply(body['data'] as Map);
    } catch (_) {
      if (_valid) failed.value = true;
    } finally {
      if (_valid) busy.value = false;
    }
  }

  Future<void> setVisible(bool value) async {
    if (!_valid || !ready.value || busy.value) return;
    busy.value = true;
    try {
      final response = await client.put(_url,
          options: _options, data: {'showLastSeen': value, 'version': version});
      if (!_valid) return;
      final body = response.data as Map;
      if (body['errCode'] == 0 || body['errCode'] == 20017) {
        _apply(body['data'] as Map);
        if (body['errCode'] == 20017) notify('presenceVisibilityConflict'.tr);
      } else {
        throw StateError('request failed');
      }
    } catch (_) {
      if (_valid) notify(StrRes.saveFailed);
    } finally {
      if (_valid) busy.value = false;
    }
  }

  void onNotification(String raw) {
    if (!_valid) return;
    try {
      final message = jsonDecode(raw) as Map;
      if (message['key'] != 'presenceVisibilityChanged' ||
          message['sendUserID'] != owner ||
          message['recvUserID'] != owner) return;
      final rawData = message['data'];
      final data = (rawData is String ? jsonDecode(rawData) : rawData) as Map;
      if ((data['version'] as num).toInt() > version) _apply(data);
    } catch (_) {/* Ignore unrelated or malformed notifications. */}
  }

  void dispose() {
    _closed = true;
  }
}
