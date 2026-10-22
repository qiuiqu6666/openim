import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/media_browser/media_grid_pagination.dart';

void main() {
  testWidgets(
      'end message appears only at exhausted bottom and hides when scrolling up',
      (tester) async {
    var count = 1;
    ScrollController? scroll;
    await tester.pumpWidget(MaterialApp(
        home: MediaGridPagination(
            load: () async {
              count = 60;
              return false;
            },
            onLoaded: () {},
            builder: (controller) {
              scroll = controller;
              return ListView.builder(
                  controller: controller,
                  itemCount: count,
                  itemExtent: 60,
                  itemBuilder: (_, i) => Text('item $i'));
            })));
    await tester.pumpAndSettle();
    expect(find.text('No more items'), findsNothing);
    scroll!.jumpTo(scroll!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('No more items'), findsOneWidget);
    scroll!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('No more items'), findsNothing);
  });
  testWidgets('fills viewport then loads near bottom without parallel requests',
      (tester) async {
    var count = 2, calls = 0;
    Future<bool> load() async {
      calls++;
      count += 2;
      return calls < 20;
    }

    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            height: 600,
            child: MediaGridPagination(
                load: load,
                onLoaded: () {},
                builder: (controller) => GridView.builder(
                    controller: controller,
                    itemCount: count,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3),
                    itemBuilder: (_, i) => Text('$i'))))));
    await tester.pumpAndSettle();
    expect(calls, greaterThan(1));
    expect(calls, lessThan(20));
    final before = calls;
    await tester.drag(find.byType(GridView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(calls, greaterThan(before));
  });
  testWidgets('failure stops automatic retries and allows explicit retry',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: MediaGridPagination(
            load: () async {
              if (++calls == 1) throw StateError('offline');
              return false;
            },
            onLoaded: () {},
            builder: (controller) => ListView(controller: controller))));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('No more items'), findsNothing);
    await tester.tap(find.text('Loading failed. Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(TextButton), findsNothing);
  });
  testWidgets('closing during request does not notify disposed view',
      (tester) async {
    final pending = Completer<bool>();
    var notified = false;
    await tester.pumpWidget(MaterialApp(
        home: MediaGridPagination(
            load: () => pending.future,
            onLoaded: () => notified = true,
            builder: (controller) => ListView(controller: controller))));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(false);
    await tester.pump();
    expect(notified, false);
    expect(tester.takeException(), isNull);
  });
}
