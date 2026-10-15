import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/contacts/common_groups/common_groups_store.dart';
import 'package:openim/services/common_group_count_service.dart';

CommonGroupListPage _page(List<String> ids, [String next = '']) =>
    CommonGroupListPage(
        items: ids.map((id) => GroupInfo(groupID: id)).toList(),
        nextCursor: next,
        hasMore: next.isNotEmpty);

class _Service extends CommonGroupCountService {
  late Future<CommonGroupListPage> Function(String) fetch;
  @override
  Future<CommonGroupListPage> list(String peerUserID,
          {int limit = 30, String cursor = '', CancelToken? cancelToken}) =>
      fetch(cursor);
}

void main() {
  test('failed refresh retains content and retries from the first page',
      () async {
    final service = _Service()..fetch = (_) async => _page(['a'], 'next');
    final store =
        CommonGroupsStore('peer', service: service, currentUser: () => 'owner');
    addTearDown(store.dispose);
    await store.refresh();
    final pending = Completer<CommonGroupListPage>();
    service.fetch = (_) => pending.future;
    final refreshing = store.refresh();
    expect(store.items.single.groupID, 'a');
    pending.completeError(StateError('offline'));
    await refreshing;
    expect(store.items.single.groupID, 'a');
    expect(store.refreshFailed, isTrue);
    service.fetch = (cursor) async {
      expect(cursor, isEmpty);
      return _page(['b']);
    };
    await store.refresh();
    expect(store.items.single.groupID, 'b');
    expect(store.refreshFailed, isFalse);
  });

  test('refresh refills a loaded prefix atomically, including expired cursor',
      () async {
    final service = _Service()
      ..fetch = (cursor) async => cursor.isEmpty
          ? _page(['a', 'b'], 'next')
          : _page(['c', 'd'], 'tail');
    final store =
        CommonGroupsStore('peer', service: service, currentUser: () => 'owner');
    addTearDown(store.dispose);
    await store.refresh();
    await store.loadMore();
    final second = Completer<CommonGroupListPage>();
    service.fetch = (cursor) async {
      if (cursor == 'tail') throw const CommonGroupsException(1001);
      return cursor.isEmpty ? _page(['a', 'b'], 'fresh') : second.future;
    };
    final refreshing = store.loadMore();
    await Future<void>.delayed(Duration.zero);
    expect(store.items.map((item) => item.groupID), ['a', 'b', 'c', 'd']);
    second.complete(_page(['c', 'd']));
    await refreshing;
    expect(store.items.map((item) => item.groupID), ['a', 'b', 'c', 'd']);
    expect(store.failed, isFalse);
  });
}
