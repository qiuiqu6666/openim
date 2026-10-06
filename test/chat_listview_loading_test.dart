import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

Future<void> pumpChatList(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: SizedBox(height: 300, child: child)),
    ),
  ));
}

void main() {
  tearDown(Get.reset);

  testWidgets('empty history shows progress before confirming no messages',
      (tester) async {
    final request = Completer<bool>();
    var calls = 0;
    await pumpChatList(
        tester,
        ChatListView(
          itemCount: 0,
          onScrollToBottomLoad: () {
            calls++;
            return request.future;
          },
          itemBuilder: (_, __) => const SizedBox.shrink(),
        ));
    expect(calls, 1);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('chatHistoryEmpty'.tr), findsNothing);
    request.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('chatHistoryEmpty'.tr), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prefetched history does not trigger a second initial page',
      (tester) async {
    var calls = 0;
    await pumpChatList(
        tester,
        ChatListView(
          itemCount: 1,
          loadOnInit: false,
          onScrollToBottomLoad: () async {
            calls++;
            return false;
          },
          itemBuilder: (_, index) => Text('message $index'),
        ));
    await tester.pumpAndSettle();
    expect(find.text('message 0'), findsOneWidget);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external initial state supports failure and retry in dark mode',
      (tester) async {
    var loading = true;
    String? error;
    var retries = 0;
    late StateSetter rebuild;
    await pumpChatList(tester, StatefulBuilder(builder: (_, setState) {
      rebuild = setState;
      return ChatListView(
        itemCount: 0,
        loadOnInit: false,
        initialLoading: loading,
        historyError: error,
        onRetry: () {
          retries++;
          rebuild(() {
            loading = true;
            error = null;
          });
        },
        itemBuilder: (_, __) => const SizedBox.shrink(),
      );
    }), brightness: Brightness.dark);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    rebuild(() {
      loading = false;
      error = 'SDK details must not be displayed';
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('chatHistoryLoadFailed'.tr), findsOneWidget);
    expect(find.textContaining('SDK details'), findsNothing);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(retries, 1);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial request failure is caught and can be retried',
      (tester) async {
    var calls = 0;
    await pumpChatList(
        tester,
        ChatListView(
          itemCount: 0,
          onScrollToBottomLoad: () async {
            calls++;
            if (calls == 1) throw StateError('database unavailable');
            return false;
          },
          itemBuilder: (_, __) => const SizedBox.shrink(),
        ));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(TextButton), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('chatHistoryEmpty'.tr), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated history edge events share one request and stop at end',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final more = Completer<bool>();
    var calls = 0;
    await pumpChatList(
        tester,
        ChatListView(
          controller: controller,
          itemCount: 30,
          onScrollToBottomLoad: () {
            calls++;
            return calls == 1 ? Future.value(true) : more.future;
          },
          itemBuilder: (_, index) =>
              SizedBox(height: 60, child: Text('message $index')),
        ));
    await tester.pumpAndSettle();
    expect(calls, 1);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    controller.jumpTo(controller.position.maxScrollExtent - 1);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(calls, 2);
    more.complete(false);
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent - 1);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pagination failure waits for explicit retry instead of refetching',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var calls = 0;
    await pumpChatList(
        tester,
        ChatListView(
          controller: controller,
          itemCount: 30,
          loadOnInit: false,
          onScrollToBottomLoad: () async {
            calls++;
            if (calls == 1) throw StateError('temporary SDK error');
            return false;
          },
          itemBuilder: (_, index) =>
              SizedBox(height: 60, child: Text('message $index')),
        ));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent - 1);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(TextButton), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyed reverse rows preserve state when a new message arrives',
      (tester) async {
    final ids = ['first', 'second', 'third'];
    final identities = <String, Object>{};
    late StateSetter rebuild;
    await pumpChatList(tester, StatefulBuilder(builder: (_, setState) {
      rebuild = setState;
      return ChatListView(
        itemCount: ids.length,
        loadOnInit: false,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = ids.indexOf(key.value);
          return index < 0 ? null : ids.length - 1 - index;
        },
        itemBuilder: (_, index) {
          final id = ids[ids.length - 1 - index];
          return _MessageProbe(
              key: ValueKey(id), id: id, identities: identities);
        },
      );
    }));
    final previous = Map<String, Object>.of(identities);
    expect(previous.length, 3);
    rebuild(() => ids.add('newest'));
    await tester.pumpAndSettle();
    for (final id in previous.keys) {
      expect(identities[id], same(previous[id]),
          reason: '$id should keep its media state');
    }
    expect(identities.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed refresh after the last page uses external retry and shows progress',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final retry = Completer<void>();
    var loading = false;
    String? error = 'latest-page refresh failed';
    var olderCalls = 0;
    var retries = 0;
    late StateSetter rebuild;
    await pumpChatList(tester, StatefulBuilder(builder: (_, setState) {
      rebuild = setState;
      return ChatListView(
        controller: controller,
        itemCount: 30,
        loadOnInit: false,
        hasMore: false,
        historyError: error,
        historyLoading: loading,
        onScrollToBottomLoad: () async {
          olderCalls++;
          return false;
        },
        onRetry: () {
          retries++;
          rebuild(() {
            error = null;
            loading = true;
          });
          retry.future.then((_) => rebuild(() => loading = false));
        },
        itemBuilder: (_, index) =>
            SizedBox(height: 60, child: Text('message $index')),
      );
    }));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(retries, 1);
    expect(olderCalls, 0);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    controller.jumpTo(controller.position.maxScrollExtent - 1);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(olderCalls, 0);
    retry.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'closing while initial history is pending ignores late completion',
      (tester) async {
    final request = Completer<bool>();
    await pumpChatList(
        tester,
        ChatListView(
          itemCount: 0,
          onScrollToBottomLoad: () => request.future,
          itemBuilder: (_, __) => const SizedBox.shrink(),
        ));
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    request.complete(false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _MessageProbe extends StatefulWidget {
  const _MessageProbe({super.key, required this.id, required this.identities});
  final String id;
  final Map<String, Object> identities;
  @override
  State<_MessageProbe> createState() => _MessageProbeState();
}

class _MessageProbeState extends State<_MessageProbe> {
  @override
  void initState() {
    super.initState();
    widget.identities[widget.id] = Object();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 50, child: Text(widget.id));
}
