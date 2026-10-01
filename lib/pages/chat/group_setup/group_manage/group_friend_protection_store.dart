import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

class GroupFriendProtectionStore {
  GroupFriendProtectionStore(this.groupID,
      {Dio? client, void Function(String)? notify})
      : client = client ?? dio,
        notify = notify ?? IMViews.showToast;
  final String groupID;
  final Dio client;
  final void Function(String) notify;
  final protect = false.obs;
  final canManage = false.obs;
  final ready = false.obs;
  final busy = false.obs;
  final failed = false.obs;
  final String? _owner = DataSp.userID;
  bool _closed = false;
  bool get _valid => !_closed && _owner != null && _owner == DataSp.userID;
  String get _url =>
      '${Config.appAuthUrl}/chat/groups/${Uri.encodeComponent(groupID)}/friend-protect';
  Options get _options => Options(headers: {
        'token': DataSp.chatToken,
        'operationID': const Uuid().v4(),
        'Content-Type': 'application/json',
      });

  Future<void> _read() async {
    final response = await client.get(_url, options: _options);
    if (!_valid) return;
    final body = response.data as Map;
    if (body['errCode'] != 0) throw StateError('request failed');
    final data = body['data'] as Map;
    final nextProtect = data['protect'] as bool;
    final nextCanManage = data['canManage'] as bool;
    protect.value = nextProtect;
    canManage.value = nextCanManage;
    ready.value = true;
    failed.value = false;
  }

  Future<void> refresh() async {
    if (!_valid || busy.value) return;
    busy.value = true;
    try {
      await _read();
    } catch (_) {
      if (_valid) {
        ready.value = false;
        failed.value = true;
      }
    } finally {
      if (_valid) busy.value = false;
    }
  }

  Future<void> setProtected(bool value) async {
    if (!_valid || busy.value || !ready.value || !canManage.value) return;
    busy.value = true;
    try {
      final response =
          await client.put(_url, options: _options, data: {'protect': value});
      if (!_valid) return;
      if ((response.data as Map)['errCode'] != 0) {
        throw StateError('save failed');
      }
    } catch (_) {
      if (_valid) notify(StrRes.saveFailed);
    }
    // Reconcile even after a timeout: the server may have accepted the write.
    try {
      if (_valid) await _read();
    } catch (_) {
      if (_valid) {
        ready.value = false;
        failed.value = true;
      }
    } finally {
      if (_valid) busy.value = false;
    }
  }

  void dispose() {
    _closed = true;
  }
}
