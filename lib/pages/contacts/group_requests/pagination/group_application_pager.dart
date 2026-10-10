import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

typedef GroupApplicationPageRead = Future<List<GroupApplicationInfo>> Function(
    bool recipient, int offset, int count);

/// Merge the SDK's newest-first streams without discarding unread page tails.
/// Fork before reading so a failed/superseded request cannot advance live state.
class GroupApplicationPager {
  GroupApplicationPager({GroupApplicationPageRead? read})
      : _read = read ?? _sdkRead;

  static const pageSize = 20;
  final GroupApplicationPageRead _read;
  final _sources = [_ApplicationStream(), _ApplicationStream()];
  final _seen = <String>{};
  final _recipientIDs = <String>{};

  bool get hasMore => _sources.any((s) => s.buffer.isNotEmpty || !s.exhausted);

  GroupApplicationPager fork() {
    final copy = GroupApplicationPager(read: _read);
    for (var i = 0; i < _sources.length; i++) {
      copy._sources[i]
        ..offset = _sources[i].offset
        ..exhausted = _sources[i].exhausted
        ..buffer.addAll(_sources[i].buffer);
    }
    copy._seen.addAll(_seen);
    copy._recipientIDs.addAll(_recipientIDs);
    return copy;
  }

  static Future<List<GroupApplicationInfo>> _sdkRead(
      bool recipient, int offset, int count) {
    final manager = OpenIM.iMManager.groupManager;
    return recipient
        ? manager.getGroupApplicationListAsRecipient(
            req: GetGroupApplicationListAsRecipientReq(
                offset: offset, count: count))
        : manager.getGroupApplicationListAsApplicant(
            req: GetGroupApplicationListAsApplicantReq(
                offset: offset, count: count));
  }

  Future<List<GroupApplicationInfo>> nextPage() async {
    final result = <GroupApplicationInfo>[];
    while (result.length < pageSize) {
      await Future.wait([
        for (var i = 0; i < _sources.length; i++) _fill(i),
      ]);
      if (_sources.every((s) => s.buffer.isEmpty)) break;
      final left = _sources[0].buffer;
      final right = _sources[1].buffer;
      final selected = right.isEmpty ||
              (left.isNotEmpty &&
                  (left.first.reqTime ?? 0) >= (right.first.reqTime ?? 0))
          ? left
          : right;
      final item = selected.removeAt(0);
      if (_seen.add(IMUtils.buildGroupApplicationID(item))) result.add(item);
    }
    return result;
  }

  Iterable<GroupApplicationInfo> receivedIn(List<GroupApplicationInfo> items) =>
      items.where((item) =>
          _recipientIDs.contains(IMUtils.buildGroupApplicationID(item)));

  Future<void> _fill(int index) async {
    final source = _sources[index];
    if (source.exhausted || source.buffer.isNotEmpty) return;
    final page = await _read(index == 0, source.offset, pageSize);
    source.offset += page.length;
    source.exhausted = page.length < pageSize;
    source.buffer.addAll(page);
    source.buffer.sort((a, b) => (b.reqTime ?? 0).compareTo(a.reqTime ?? 0));
    if (index == 0) {
      _recipientIDs.addAll(page.map(IMUtils.buildGroupApplicationID));
    }
  }
}

class _ApplicationStream {
  int offset = 0;
  bool exhausted = false;
  final buffer = <GroupApplicationInfo>[];
}
