import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../../services/common_group_count_service.dart';

class CommonGroupsStore extends ChangeNotifier {
  CommonGroupsStore(this.peerUserID,
      {CommonGroupCountService? service, String? Function()? currentUser})
      : _service = service ?? CommonGroupCountService(),
        _currentUser = currentUser ?? (() => DataSp.userID) {
    _owner = _currentUser();
  }
  final String peerUserID;
  final CommonGroupCountService _service;
  final String? Function() _currentUser;
  late final String? _owner;
  final items = <GroupInfo>[];
  final _ids = <String>{};
  bool busy = false;
  bool failed = false;
  bool refreshFailed = false;
  bool hasMore = true;
  String _cursor = '';
  bool _disposed = false;
  int _version = 0;
  CancelToken? _cancel;
  bool get _valid => !_disposed && _currentUser() == _owner;

  Future<void> refresh() => _load(refresh: true);
  Future<void> loadMore() => _load(refresh: false);

  Future<void> _load({required bool refresh}) async {
    if (!_valid || (!refresh && (busy || !hasMore))) return;
    final version = ++_version;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    busy = true;
    failed = false;
    refreshFailed = false;
    var replacing = refresh;
    var cursor = refresh ? '' : _cursor;
    final retainedCount = items.length;
    notifyListeners();
    try {
      CommonGroupListPage page;
      try {
        page = await _service.list(peerUserID,
            cursor: cursor, cancelToken: cancel);
      } on CommonGroupsException catch (error) {
        if (error.code != 1001 || cursor.isEmpty) rethrow;
        // Restart once when a signed or expired cursor is rejected.
        if (!_valid || version != _version) return;
        replacing = true;
        cursor = '';
        page = await _service.list(peerUserID, cancelToken: cancel);
      }
      if (!_valid || version != _version) return;
      final incoming = <GroupInfo>[];
      final incomingIDs = <String>{};
      final cursors = <String>{cursor};
      while (true) {
        incoming
            .addAll(page.items.where((item) => incomingIDs.add(item.groupID)));
        // Refill the previously visible prefix before publishing a refresh.
        // Keeping only page one would clamp a deeply scrolled viewport too.
        if (!replacing || !page.hasMore || incoming.length >= retainedCount) {
          break;
        }
        if (!cursors.add(page.nextCursor)) {
          throw const FormatException('Common group cursor did not advance');
        }
        page = await _service.list(peerUserID,
            cursor: page.nextCursor, cancelToken: cancel);
        if (!_valid || version != _version) return;
      }
      if (replacing) {
        items.clear();
        _ids.clear();
      }
      items.addAll(incoming.where((item) => _ids.add(item.groupID)));
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (_) {
      if (_valid && version == _version) {
        failed = true;
        refreshFailed = replacing;
      }
    } finally {
      if (_valid && version == _version) {
        busy = false;
        notifyListeners();
      } else if (!_disposed && _currentUser() != _owner) {
        items.clear();
        _ids.clear();
        busy = false;
        hasMore = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _version++;
    _cancel?.cancel();
    super.dispose();
  }
}
