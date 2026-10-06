import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

class GroupFriendProtectionStore {
  GroupFriendProtectionStore(
    this.groupID, {
    Dio? client,
    void Function(String)? notify,
    String? Function()? currentUserID,
    String? Function()? sdkUserID,
    String? Function()? currentToken,
    String Function()? baseURL,
  })  : client = client ?? dio,
        notify = notify ?? IMViews.showToast,
        _currentUserID = currentUserID ?? (() => DataSp.userID),
        _sdkUserID = sdkUserID ?? _readSdkUserID,
        _currentToken = currentToken ?? (() => DataSp.chatToken),
        _baseURL = baseURL ?? (() => Config.appAuthUrl) {
    _scope = _session;
  }
  final String groupID;
  final Dio client;
  final void Function(String) notify;
  final String? Function() _currentUserID;
  final String? Function() _sdkUserID;
  final String? Function() _currentToken;
  final String Function() _baseURL;
  late final (String?, String?, String?, String) _scope;
  (String?, String?, String?, String) get _session =>
      (_currentUserID(), _sdkUserID(), _currentToken(), _baseURL());

  final _protect = false.obs;
  final _canManage = false.obs;
  final _ready = false.obs;
  final _busy = false.obs;
  final _failed = false.obs;

  RxBool get protect {
    _guardCurrent();
    return _protect;
  }

  RxBool get canManage {
    _guardCurrent();
    return _canManage;
  }

  RxBool get ready {
    _guardCurrent();
    return _ready;
  }

  RxBool get busy {
    _guardCurrent();
    return _busy;
  }

  RxBool get failed {
    _guardCurrent();
    return _failed;
  }

  int _generation = 0;
  bool _writing = false;
  bool _invalidated = false;
  bool _closed = false;

  bool _guardCurrent() {
    if (!_closed &&
        !_invalidated &&
        _scope.$1?.trim().isNotEmpty == true &&
        _scope.$3?.isNotEmpty == true &&
        _scope == _session) {
      return true;
    }
    if (!_invalidated) {
      _invalidated = true;
      _generation++;
      _clearDisclosure();
      _busy.value = false;
      _failed.value = false;
    }
    return false;
  }

  bool _accepts(int generation) => _guardCurrent() && generation == _generation;

  void _clearDisclosure() {
    _ready.value = false;
    _protect.value = false;
    _canManage.value = false;
  }

  String get _url =>
      '${_scope.$4.replaceFirst(RegExp(r'/+$'), '')}/chat/groups/${Uri.encodeComponent(groupID)}/friend-protect';
  Options get _options => Options(headers: {
        'token': _scope.$3,
        'operationID': const Uuid().v4(),
        'Content-Type': 'application/json',
      });

  Future<void> _read(int generation) async {
    final response = await client.get(_url, options: _options);
    if (!_accepts(generation)) return;
    final body = response.data as Map;
    if (body['errCode'] != 0) throw StateError('request failed');
    final data = body['data'] as Map;
    final nextProtect = data['protect'] as bool;
    final nextCanManage = data['canManage'] as bool;
    _protect.value = nextProtect;
    if (!_accepts(generation)) return;
    _canManage.value = nextCanManage;
    if (!_accepts(generation)) return;
    _ready.value = true;
    if (!_accepts(generation)) return;
    _failed.value = false;
  }

  Future<void> refresh() async {
    if (!_guardCurrent() || _writing) return;
    // A new read replaces an older read; its response cannot restore stale state.
    final generation = ++_generation;
    _busy.value = true;
    try {
      await _read(generation);
    } catch (_) {
      if (_accepts(generation)) {
        _clearDisclosure();
        _failed.value = true;
      }
    } finally {
      if (_accepts(generation)) _busy.value = false;
    }
  }

  Future<void> setProtected(bool value) async {
    if (!_guardCurrent() ||
        _writing ||
        _busy.value ||
        !_ready.value ||
        !_canManage.value) {
      return;
    }
    final generation = ++_generation;
    _writing = true;
    _busy.value = true;
    try {
      final response =
          await client.put(_url, options: _options, data: {'protect': value});
      if (_accepts(generation) && (response.data as Map)['errCode'] != 0) {
        throw StateError('save failed');
      }
    } catch (_) {
      if (_accepts(generation)) notify(StrRes.saveFailed);
    }
    // Reconcile even after a timeout: the server may have accepted the write.
    try {
      if (_accepts(generation)) await _read(generation);
    } catch (_) {
      if (_accepts(generation)) {
        _clearDisclosure();
        _failed.value = true;
      }
    } finally {
      _writing = false;
      if (_accepts(generation)) _busy.value = false;
    }
  }

  void dispose() {
    _closed = true;
    _guardCurrent();
  }

  static String? _readSdkUserID() {
    try {
      return OpenIM.iMManager.userID;
    } catch (_) {
      return null;
    }
  }
}
