import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/services/common_group_count_service.dart';
import 'package:openim/pages/contacts/common_groups/common_groups_store.dart';
import 'package:openim/pages/contacts/common_groups/common_groups_page.dart';

CommonGroupListPage page(List<String> ids,
        {String next = '', bool more = false}) =>
    CommonGroupListPage(
        items: ids
            .map((id) => GroupInfo(
                groupID: id,
                groupName: 'Group $id',
                faceURL: '',
                memberCount: 5))
            .toList(),
        nextCursor: next,
        hasMore: more);

class FakeService extends CommonGroupCountService {
  FakeService(this.fetch);
  final Future<CommonGroupListPage> Function(String) fetch;
  final cursors = <String>[];
  @override
  Future<CommonGroupListPage> list(String peerUserID,
      {int limit = 30, String cursor = '', CancelToken? cancelToken}) {
    cursors.add(cursor);
    return fetch(cursor);
  }
}

void main() {
  testWidgets(
      'pull refresh shows only the top spinner; initial load still shows feedback',
      (tester) async {
    addTearDown(Get.reset);
    final initial = Completer<CommonGroupListPage>();
    final refresh = Completer<CommonGroupListPage>();
    var calls = 0;
    final service =
        FakeService((_) => ++calls == 1 ? initial.future : refresh.future);
    final store =
        CommonGroupsStore('peer', service: service, currentUser: () => 'me');
    addTearDown(store.dispose);
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            home: CommonGroupsPage(peerUserID: 'peer', store: store))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    initial.complete(page(['a'], next: 'next', more: true));
    await tester.pumpAndSettle();
    final refreshing = tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    expect(service.cursors, ['', '']);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    refresh.complete(page(['b']));
    await tester.pumpAndSettle();
    await refreshing;
    expect(find.text('Group b'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  test(
      'pagination deduplicates; a failed next page retains rows and retries its cursor',
      () async {
    var fail = true;
    final service = FakeService((cursor) async {
      if (cursor.isEmpty) return page(['a'], next: 'next', more: true);
      if (fail) throw StateError('network');
      return page(['a', 'b']);
    });
    final store =
        CommonGroupsStore('peer', service: service, currentUser: () => 'me');
    addTearDown(store.dispose);
    await store.refresh();
    await store.loadMore();
    expect(store.failed, true);
    expect(store.items.map((g) => g.groupID), ['a']);
    fail = false;
    await store.loadMore();
    expect(store.items.map((g) => g.groupID), ['a', 'b']);
    expect(service.cursors, ['', 'next', 'next']);
    await store.loadMore();
    expect(service.cursors.length, 3);
  });
  test('1001 on cursor restarts once from first page', () async {
    var calls = 0;
    final service = FakeService((cursor) async {
      if (cursor.isNotEmpty) throw const CommonGroupsException(1001);
      return ++calls == 1
          ? page(['old'], next: 'expired', more: true)
          : page(['new']);
    });
    final store =
        CommonGroupsStore('peer', service: service, currentUser: () => 'me');
    addTearDown(store.dispose);
    await store.refresh();
    await store.loadMore();
    expect(service.cursors, ['', 'expired', '']);
    expect(store.items.single.groupID, 'new');
    expect(store.failed, false);
  });
  test('refresh supersedes an older request and dispose ignores completion',
      () async {
    final old = Completer<CommonGroupListPage>();
    var calls = 0;
    final store = CommonGroupsStore('peer',
        service: FakeService(
            (_) => ++calls == 1 ? old.future : Future.value(page(['new']))),
        currentUser: () => 'me');
    final pending = store.refresh();
    await store.refresh();
    old.complete(page(['old']));
    await pending;
    expect(store.items.single.groupID, 'new');
    store.dispose();
    final delayed = Completer<CommonGroupListPage>();
    final disposed = CommonGroupsStore('peer',
        service: FakeService((_) => delayed.future), currentUser: () => 'me');
    final loading = disposed.refresh();
    disposed.dispose();
    delayed.complete(page(['late']));
    await loading;
    expect(disposed.items, isEmpty);
  });
  test('account change discards pending response', () async {
    var owner = 'me';
    final delayed = Completer<CommonGroupListPage>();
    final store = CommonGroupsStore('peer',
        service: FakeService((_) => delayed.future), currentUser: () => owner);
    addTearDown(store.dispose);
    final pending = store.refresh();
    owner = 'other';
    delayed.complete(page(['old account group']));
    await pending;
    expect(store.items, isEmpty);
  });
  for (final dark in [false, true]) {
    testWidgets(
        'list opens group and supports empty/error states in $dark theme',
        (tester) async {
      tester.view.physicalSize = const Size(320, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(Get.reset);
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = false);
      var state = 'list';
      final store = CommonGroupsStore('peer',
          currentUser: () => 'me',
          service: FakeService((_) async {
            if (state == 'error') throw StateError('network');
            return page(state == 'empty' ? [] : ['a']);
          }));
      addTearDown(store.dispose);
      String? opened;
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
                theme: ThemeData(
                    brightness: dark ? Brightness.dark : Brightness.light),
                home: CommonGroupsPage(
                    peerUserID: 'peer',
                    store: store,
                    onOpenGroup: (group) async {
                      opened = group.groupID;
                    }),
              )));
      await tester.pumpAndSettle();
      expect(find.text('Group a'), findsOneWidget);
      await tester.tap(find.text('Group a'));
      await tester.pumpAndSettle();
      expect(opened, 'a');
      await tester.enterText(find.byType(TextField), 'missing group');
      await tester.pumpAndSettle();
      expect(find.text('Group a'), findsNothing);
      expect(find.text('profileCommonGroupsNoMatch'), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' A ');
      await tester.pumpAndSettle();
      expect(find.text('Group a'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Group a'), findsOneWidget);
      state = 'error';
      await store.refresh();
      await tester.pumpAndSettle();
      expect(find.text('profileCommonGroupsRetry'), findsOneWidget);
      state = 'empty';
      await tester.tap(find.text('profileCommonGroupsRetry'));
      await tester.pumpAndSettle();
      expect(find.text('profileCommonGroupsEmpty'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
