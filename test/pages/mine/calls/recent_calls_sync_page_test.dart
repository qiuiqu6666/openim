import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/pages/mine/secondary/calls/data/call_record_sync_binding.dart';
import 'package:openim/pages/mine/secondary/calls/data/call_records_repository.dart';
import 'package:openim/pages/mine/secondary/calls/recent_calls_page.dart';
import 'package:openim_common/openim_common.dart';

import 'recent_call_test_support.dart';
import 'recent_calls_sync_fixture.dart';
import 'recent_calls_ui_host.dart';
import '../../../support/chat/chat_entry_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecentCallMemoryBox box;
  late CacheController cache;
  late RecentCallsUiApi api;
  late CallRecordsRepository repository;

  setUpAll(initializeRecentCallsUi);
  void initializeFixture() {
    box = RecentCallMemoryBox();
    cache = CacheController(
        accountIDProvider: () => 'account-a', boxOpener: () async => box);
    api = RecentCallsUiApi();
    repository = CallRecordsRepository(
      cache: cache,
      api: api,
      accountIDProvider: () => 'account-a',
      tokenProvider: () => 'chat-session',
      profileResolver: (rows) async => rows,
    );
  }

  tearDown(() async {
    repository.dispose();
    for (final request in api.requests) {
      if (!request.result.isCompleted) request.complete([], syncAt: 0);
    }
    cache.onDelete();
    Get.reset();
  });

  Finder key(String value) => find.byKey(ValueKey(value));
  Finder row(String callID) => key('recent-call-room:$callID');
  RecentCallsPage page({void Function(String, bool)? onStartCall}) =>
      RecentCallsPage(
          cacheController: cache,
          repository: repository,
          onStartCall: onStartCall);

  void pageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        initializeFixture();
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  pageTest('an empty device loads server call history using the chat session',
      (tester) async {
    await mountRecentCalls(tester, page());
    expect(api.requests, hasLength(1));
    expect(api.requests.single.syncAt, 0);
    expect(api.requests.single.token, 'chat-session');
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('暂无通话记录'), findsNothing);
    final connected = remoteCall(callID: 'other-device-call', name: '另一设备的来电');
    final missed = remoteCall(
        callID: 'other-device-missed',
        peer: 'peer-2',
        name: '另一设备的未接',
        status: 'missed',
        incoming: true);
    api.requests.single.complete([connected, missed]);
    await tester.pumpAndSettle();
    expect(row('other-device-call'), findsOneWidget);
    expect(find.text('另一设备的来电'), findsOneWidget);
    expect(find.text('拨出 · 已接通 · 01:13'), findsOneWidget);
    await tester.tap(key('recent-calls-tab-missed'));
    await tester.pumpAndSettle();
    expect(row('other-device-missed'), findsOneWidget);
    expect(row('other-device-call'), findsNothing);
    expect(api.requests, hasLength(1),
        reason: 'Filtering a synchronized cache does not refetch history.');
    expect(tester.takeException(), isNull);
  });

  pageTest('server failure has a retry action that restores remote records',
      (tester) async {
    await mountRecentCalls(tester, page());
    api.requests.single.result.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('通话记录读取失败'), findsOneWidget);
    expect(find.text('暂无通话记录'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(api.requests, hasLength(2));
    api.requests.last.complete([remoteCall(callID: 'retried-call')]);
    await tester.pumpAndSettle();
    expect(row('retried-call'), findsOneWidget);
    expect(find.text('通话记录读取失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  pageTest('a server callID update replaces missed state in the open page',
      (tester) async {
    Get.put<AppController>(EntryTestApp());
    final im = EntryTestIM();
    final binding = CallRecordSyncBinding(
      repository: repository,
      businessNotifications: im.customBusinessMessageSubject,
      observeLifecycle: false,
      debounce: const Duration(seconds: 2),
    );
    addTearDown(binding.dispose);
    addTearDown(im.close);
    final missed =
        remoteCall(callID: 'same-call', status: 'missed', incoming: true);
    await mountRecentCalls(tester, page());
    api.requests.single.complete([missed]);
    await tester.pumpAndSettle();
    await tester.tap(key('recent-calls-tab-missed'));
    await tester.pumpAndSettle();
    expect(row('same-call'), findsOneWidget);
    final completed = remoteCall(
        callID: 'same-call',
        incoming: true,
        duration: 81,
        updatedAt: missed.updatedAt + 10000);
    im.recvCustomBusinessMessage(callRecordNotice(completed));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(row('same-call'), findsNothing);
    expect(find.text('暂无未接记录'), findsOneWidget);
    await tester.tap(key('recent-calls-tab-all'));
    await tester.pumpAndSettle();
    expect(row('same-call'), findsOneWidget);
    expect(find.text('呼入 · 已接通 · 01:21'), findsOneWidget);
    expect(cache.callRecordList, hasLength(1));
    expect(api.requests, hasLength(1),
        reason: 'The full SDK business notification updates the page at once.');
    await tester.pump(const Duration(seconds: 2));
    expect(api.requests, hasLength(2));
    api.requests.last.complete([], syncAt: missed.updatedAt + 1);
    await tester.pumpAndSettle();
    expect(row('same-call'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  pageTest('local hide remains hidden through later updates and refresh',
      (tester) async {
    final hidden = remoteCall(callID: 'hide-only-here');
    final kept = remoteCall(callID: 'keep-here', peer: 'peer-2', name: '保留的记录');
    await mountRecentCalls(tester, page());
    api.requests.single.complete([hidden, kept]);
    await tester.pumpAndSettle();
    await tester.tap(key('recent-calls-edit'));
    await tester.pumpAndSettle();
    await tester.tap(key('recent-call-delete-room:hide-only-here'));
    await tester.pumpAndSettle();
    expect(find.textContaining('本设备'), findsWidgets,
        reason: 'The confirmation must explain the scope of hiding.');
    final confirm = find.widgetWithText(CupertinoDialogAction, '隐藏');
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(row('hide-only-here'), findsNothing);
    expect(row('keep-here'), findsOneWidget);
    final later = hidden.copy()..updatedAt = hidden.updatedAt + 1000;
    await repository.handleNotification(callRecordNotice(later));
    await tester.pumpAndSettle();
    expect(row('hide-only-here'), findsNothing);
    final refresh = repository.refresh();
    await tester.pump();
    api.requests.last.complete([later]);
    await refresh;
    await tester.pumpAndSettle();
    expect(row('hide-only-here'), findsNothing);
    expect(row('keep-here'), findsOneWidget);
    expect(api.reports, isEmpty,
        reason: 'Hiding does not report a different call state to the server.');
    expect(tester.takeException(), isNull);
  });

  pageTest(
      'resume and reopen preserve shared sync without a stale page observer',
      (tester) async {
    final first = remoteCall(callID: 'before-background');
    await mountRecentCalls(tester, page());
    api.requests.single.complete([first], syncAt: first.updatedAt);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.requests, hasLength(2));
    expect(api.requests.last.syncAt, first.updatedAt);
    final second = remoteCall(
        callID: 'while-background',
        peer: 'peer-2',
        name: '后台期间的通话',
        updatedAt: first.updatedAt + 1000);
    api.requests.last.complete([second], syncAt: second.updatedAt + 1);
    await tester.pumpAndSettle();
    expect(row('before-background'), findsOneWidget);
    expect(row('while-background'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.requests, hasLength(2),
        reason: 'The closed page must remove its foreground observer.');
    await repository.handleNotification(callRecordNotice(
        remoteCall(callID: 'after-page-close', peer: 'peer-3')));
    await mountRecentCalls(tester, page());
    expect(api.requests, hasLength(3));
    api.requests.last.complete([], syncAt: second.updatedAt + 2);
    await tester.pumpAndSettle();
    for (final callID in [
      'before-background',
      'while-background',
      'after-page-close',
    ]) {
      expect(row(callID), findsOneWidget);
    }
    expect(cache.callRecordList, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  pageTest('a synchronized group record is readable and cannot redial one user',
      (tester) async {
    final started = <(String, bool)>[];
    final group = remoteCall(callID: 'group-call', peer: '', name: '')
      ..roomType = 'group'
      ..groupID = 'server-group';
    await mountRecentCalls(
        tester, page(onStartCall: (peer, video) => started.add((peer, video))));
    api.requests.single.complete([group], syncAt: group.updatedAt);
    await tester.pumpAndSettle();
    expect(row('group-call'), findsOneWidget);
    expect(find.text('server-group'), findsOneWidget);
    await tester.tap(row('group-call'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(started, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    pageTest(
        'synchronized records and redial fit a narrow large-text page ($dark)',
        (tester) async {
      final started = <(String, bool)>[];
      await mountRecentCalls(tester,
          page(onStartCall: (peer, video) => started.add((peer, video))),
          dark: dark, size: const Size(320, 640), textScale: 2);
      api.requests.single.complete([
        remoteCall(
            callID: 'remote-redial', peer: 'remote-peer', name: '远端通话记录'),
      ]);
      await tester.pumpAndSettle();
      expect(row('remote-redial').hitTestable(), findsOneWidget);
      expect(
          tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          AppTokens.background(dark: dark));
      expect(tester.takeException(), isNull);
      await tester.tap(row('remote-redial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('视频通话'));
      await tester.pumpAndSettle();
      expect(started, [('remote-peer', true)]);
      expect(tester.takeException(), isNull);
    });
  }
}
