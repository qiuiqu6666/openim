import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class _PagingFixture {
  final scroll = ScrollController();
  List<String> ids = List.generate(30, (index) => 'message-$index');
  bool withIDs = true;
  bool enabledNewer = true;
  bool? olderHasMore;
  bool? newerHasMore = true;
  Object? pagingWindow;
  bool historyLoading = false;
  bool initialLoading = false;
  String? historyError;
  int olderCalls = 0;
  int newerCalls = 0;
  Future<bool> Function()? readOlder;
  Future<bool> Function()? readNewer;
  late StateSetter update;

  Widget get view => StatefulBuilder(builder: (_, setState) {
        update = setState;
        return ChatListView(
          controller: scroll,
          itemCount: ids.length,
          messageIDs: withIDs ? ids : null,
          loadOnInit: false,
          hasMore: olderHasMore,
          newerHasMore: newerHasMore,
          pagingWindow: pagingWindow,
          enabledScrollTopLoad: enabledNewer,
          historyLoading: historyLoading,
          initialLoading: initialLoading,
          historyError: historyError,
          onScrollToBottomLoad: () {
            olderCalls++;
            return readOlder?.call() ?? Future.value(false);
          },
          onScrollToTopLoad: () {
            newerCalls++;
            return readNewer?.call() ?? Future.value(false);
          },
          findChildIndexCallback: (key) {
            final index = ids.indexOf((key as ValueKey<String>).value);
            return index < 0 ? null : index;
          },
          itemBuilder: (_, index) => SizedBox(
            key: ValueKey(ids[index]),
            height: 48,
            child: Text(ids[index]),
          ),
        );
      });

  Future<void> mount(WidgetTester tester,
      {Brightness brightness = Brightness.light}) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
    });
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(height: 300, child: view),
          ),
        ),
      ),
    ));
    if (historyLoading || initialLoading) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> reachNewer(WidgetTester tester) async {
    scroll.jumpTo(scroll.position.minScrollExtent + 100);
    await tester.pump();
    scroll.jumpTo(scroll.position.minScrollExtent);
    await tester.pump();
  }

  Future<void> reachOlder(WidgetTester tester) async {
    scroll.jumpTo(scroll.position.maxScrollExtent - 100);
    await tester.pump();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
  }
}

void main() {
  tearDown(Get.reset);

  testWidgets('reversing to newer while older loads keeps its own boundary',
      (tester) async {
    final older = Completer<bool>();
    final f = _PagingFixture()..readOlder = () => older.future;
    await f.mount(tester);
    await f.reachOlder(tester);
    expect(f.olderCalls, 1);

    await f.reachNewer(tester);
    expect(f.newerCalls, 0, reason: 'Both directions share one paging owner');
    older.complete(false);
    await tester.pumpAndSettle();

    await f.reachNewer(tester);
    expect(f.newerCalls, 1,
        reason: 'Reaching the oldest page does not exhaust newer messages');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reversing to older while newer loads does not overlap requests',
      (tester) async {
    final newer = Completer<bool>();
    final f = _PagingFixture()..readNewer = () => newer.future;
    await f.mount(tester);
    await f.reachNewer(tester);
    expect(f.newerCalls, 1);

    await f.reachOlder(tester);
    expect(f.olderCalls, 0);
    newer.complete(false);
    await tester.pumpAndSettle();

    await f.reachOlder(tester);
    expect(f.olderCalls, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old newer result cannot exhaust a replacement history window',
      (tester) async {
    final oldWindow = Completer<bool>();
    final f = _PagingFixture()..readNewer = () => oldWindow.future;
    await f.mount(tester);
    await f.reachNewer(tester);
    expect(f.newerCalls, 1);

    f.update(() {
      f.ids = List.generate(30, (index) => 'replacement-$index');
      f.newerHasMore = true;
      f.readNewer = () async => false;
    });
    await tester.pump();
    oldWindow.complete(false);
    await tester.pumpAndSettle();

    await f.reachNewer(tester);
    expect(f.newerCalls, 2,
        reason: 'The current SDK window controls its own newer boundary');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final newer in [false, true]) {
    for (final oldFails in [false, true]) {
      testWidgets(
          'a replacement window can page ${newer ? 'newer' : 'older'} before '
          'its old ${oldFails ? 'failure' : 'completion'} returns',
          (tester) async {
        final oldRequest = Completer<bool>();
        final currentRequest = Completer<bool>();
        final f = _PagingFixture()..pagingWindow = 'window-a';
        Future<bool> read() => f.pagingWindow == 'window-a'
            ? oldRequest.future
            : currentRequest.future;
        if (newer) {
          f.readNewer = read;
        } else {
          f.readOlder = read;
        }
        Future<void> reach() =>
            newer ? f.reachNewer(tester) : f.reachOlder(tester);
        int getCalls() => newer ? f.newerCalls : f.olderCalls;
        await f.mount(tester);
        await reach();
        expect(getCalls(), 1);

        f.update(() {
          f.pagingWindow = 'window-b';
          f.ids = List.generate(30, (index) => 'window-b-$index');
        });
        await tester.pump();
        await reach();
        expect(getCalls(), 2,
            reason: 'An old SDK future must not hold the new window busy');

        if (oldFails) {
          oldRequest.completeError(StateError('old window unavailable'));
        } else {
          oldRequest.complete(false);
        }
        await tester.pump();
        expect(find.byType(TextButton), findsNothing,
            reason: 'A stale failure belongs to the previous window');

        await reach();
        expect(getCalls(), 2,
            reason: 'A stale finally must not release the current request');
        if (newer) {
          await f.reachOlder(tester);
          expect(f.olderCalls, 0);
        } else {
          await f.reachNewer(tester);
          expect(f.newerCalls, 0);
        }
        f.update(() {
          f.olderHasMore = false;
          f.newerHasMore = false;
        });
        currentRequest.complete(false);
        await tester.pumpAndSettle();
        expect(getCalls(), 2);
        expect(find.byType(TextButton), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('adding rows to the same window preserves its paging owner',
      (tester) async {
    final request = Completer<bool>();
    final f = _PagingFixture()..pagingWindow = 'one-window';
    f.readOlder = () => request.future;
    await f.mount(tester);
    await f.reachOlder(tester);
    expect(f.olderCalls, 1);
    f.update(() => f.ids.add('another-edge-message'));
    await tester.pump();
    await f.reachOlder(tester);
    await f.reachNewer(tester);
    expect(f.olderCalls, 1);
    expect(f.newerCalls, 0);
    request.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final withIDs in [true, false]) {
      testWidgets(
          'short ${withIDs ? 'identity viewport' : 'legacy list'} pages in '
          'either drag direction and stops at both ends in ${brightness.name}',
          (tester) async {
        final older = Completer<bool>();
        final newer = Completer<bool>();
        final f = _PagingFixture()
          ..ids = ['short-0', 'short-1']
          ..withIDs = withIDs;
        f.readOlder = () => older.future;
        f.readNewer = () => newer.future;
        await f.mount(tester, brightness: brightness);
        expect(f.scroll.position.minScrollExtent,
            f.scroll.position.maxScrollExtent);
        expect(f.olderCalls, 0);
        expect(f.newerCalls, 0);

        await tester.drag(find.byType(Scrollable).first, const Offset(0, 100));
        await tester.pump();
        expect(f.olderCalls, 1);
        expect(f.newerCalls, 0);
        older.complete(false);
        await tester.pumpAndSettle();

        await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
        await tester.pump();
        expect(f.newerCalls, 1);
        f.update(() => f.newerHasMore = false);
        newer.complete(false);
        await tester.pumpAndSettle();

        await tester.drag(find.byType(Scrollable).first, const Offset(0, 100));
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(f.olderCalls, 1);
        expect(f.newerCalls, 1);
        expect(find.byType(TextButton), findsNothing,
            reason: 'Successful paging needs no load-more action');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a short-window drag waits while the route changes its window',
      (tester) async {
    final f = _PagingFixture()
      ..ids = ['short-0', 'short-1']
      ..historyLoading = true;
    await f.mount(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 100));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
    await tester.pump();
    expect(f.olderCalls, 0);
    expect(f.newerCalls, 0);
    f.update(() => f.historyLoading = false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('paging failures wait for retry instead of repeated edge drags',
      (tester) async {
    final f = _PagingFixture()
      ..ids = ['short-0', 'short-1']
      ..historyError = 'history unavailable';
    await f.mount(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 100));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(f.olderCalls, 0);
    expect(f.newerCalls, 0);
    expect(find.byType(TextButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
