import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class _Fixture {
  final controller = ScrollController();
  final rows = <({String id, double height})>[];
  final reports = <({List<String> ids, double distance})>[];
  late StateSetter update;
  int builds = 0;
  double viewportHeight = 240;
  void addHistory(int count) => rows.addAll(List.generate(
      count, (i) => (id: 'old-${rows.length + i}', height: 48.0)));
  void prepend(int count, {bool varied = false}) => update(() {
        final batch = List.generate(
            count,
            (i) => (
                  id: 'new-${rows.length}-$i',
                  height: varied ? 25.0 + i % 5 * 37 : 48.0
                ));
        rows.insertAll(0, batch);
      });
  Widget get view => StatefulBuilder(builder: (_, setState) {
        update = setState;
        final ids = rows.map((e) => e.id).toList(growable: false);
        return SizedBox(
            height: viewportHeight,
            child: ChatListView(
              controller: controller,
              itemCount: rows.length,
              messageIDs: ids,
              loadOnInit: false,
              hasMore: false,
              findChildIndexCallback: (key) => key is ValueKey<String>
                  ? !ids.contains(key.value)
                      ? null
                      : ids.indexOf(key.value)
                  : null,
              onViewportChanged: (read, distance) =>
                  reports.add((ids: read, distance: distance)),
              itemBuilder: (_, index) {
                builds++;
                final row = rows[index];
                return SizedBox(
                    key: ValueKey(row.id),
                    height: row.height,
                    child: Align(
                        alignment: Alignment.topLeft, child: Text(row.id)));
              },
            ));
      });
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            home: Scaffold(
                body: Align(alignment: Alignment.topLeft, child: view)))));
    await tester.pump();
  }

  double y(WidgetTester tester, String id) =>
      tester.getTopLeft(find.byKey(ValueKey(id)).first).dy;
  List<String> visible(WidgetTester tester) => rows
      .where((row) {
        final finder = find.byKey(ValueKey(row.id));
        if (finder.evaluate().isEmpty) return false;
        final rect = tester.getRect(finder.first);
        return rect.bottom > 0 && rect.top < viewportHeight;
      })
      .map((e) => e.id)
      .toList();
}

void main() {
  tearDown(Get.reset);

  testWidgets(
      'short history is top aligned on its first frame and has no scroll',
      (tester) async {
    final f = _Fixture()..addHistory(2);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    expect(f.y(tester, 'old-1'), closeTo(10.h, 0.5));
    expect(f.y(tester, 'old-0'), closeTo(10.h + 48, 0.5));
    expect(f.controller.position.minScrollExtent, 0);
    expect(f.controller.position.maxScrollExtent, 0);
    expect(f.reports.last.ids.toSet(), {'old-0', 'old-1'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'short arrivals remain top aligned until the conversation overflows',
      (tester) async {
    final f = _Fixture()..addHistory(2);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    for (var i = 0; i < 2; i++) {
      f.prepend(1);
      await tester.pumpAndSettle();
      f.controller.jumpTo(f.controller.position.minScrollExtent);
      await tester.pumpAndSettle();
      expect(f.y(tester, 'old-1'), closeTo(10.h, 0.5));
      expect(f.controller.position.minScrollExtent, 0);
    }
    f.prepend(3);
    await tester.pumpAndSettle();
    f.controller.jumpTo(f.controller.position.minScrollExtent);
    await tester.pumpAndSettle();
    expect(f.reports.last.distance, closeTo(0, 0.5));
    expect(tester.getRect(find.byKey(ValueKey(f.rows.first.id)).first).bottom,
        closeTo(f.viewportHeight, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('different-height burst retains the same history anchor',
      (tester) async {
    final f = _Fixture()..addHistory(100);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.controller.jumpTo(600);
    await tester.pumpAndSettle();
    final anchor = f.visible(tester)[1];
    final before = f.y(tester, anchor);
    f.prepend(150, varied: true);
    await tester.pumpAndSettle();
    expect(f.y(tester, anchor), closeTo(before, 0.5));
    expect(f.controller.position.minScrollExtent, lessThan(0));
    expect(f.builds, lessThan(100),
        reason: 'The burst must not build all 150 arrivals');
    for (var i = 0; i < 4; i++) {
      f.prepend(3, varied: true);
      await tester.pumpAndSettle();
      expect(f.y(tester, anchor), closeTo(before, 0.5));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('older paging does not compensate like new-message insertion',
      (tester) async {
    final f = _Fixture()..addHistory(40);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.controller.jumpTo(500);
    await tester.pumpAndSettle();
    final anchor = f.visible(tester)[1];
    final before = f.y(tester, anchor);
    f.update(() => f.addHistory(40));
    await tester.pumpAndSettle();
    expect(f.y(tester, anchor), closeTo(before, 0.5));
    expect(f.controller.offset, closeTo(500, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame drag and arrivals preserve the actual user movement',
      (tester) async {
    final f = _Fixture()..addHistory(60);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.controller.jumpTo(500);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(200, 100));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump(); // Cross touch slop before the measured movement.
    final anchor = f.visible(tester)[1];
    final before = f.y(tester, anchor);
    final offset = f.controller.offset;
    await gesture.moveBy(const Offset(0, 50));
    final desiredOffset = f.controller.offset;
    expect(desiredOffset - offset, closeTo(50, 0.5));
    f.prepend(3, varied: true); // Before this drag's layout/measurement frame.
    await tester.pumpAndSettle();
    expect(f.controller.offset, closeTo(desiredOffset, 0.5));
    expect(f.y(tester, anchor), closeTo(before + 50, 0.5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'visible IDs progress at row boundaries and newest return uses min extent',
      (tester) async {
    final f = _Fixture()..addHistory(40);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.controller.jumpTo(400);
    await tester.pumpAndSettle();
    f.prepend(2);
    await tester.pumpAndSettle();
    final newIDs = f.rows.take(2).map((e) => e.id).toList();
    f.controller.jumpTo(f.controller.position.minScrollExtent + 48);
    await tester.pumpAndSettle();
    expect(f.reports.last.ids, contains(newIDs[1]));
    expect(f.reports.last.ids, isNot(contains(newIDs[0])));
    expect(f.reports.last.distance, closeTo(48, 0.5));
    f.controller.jumpTo(f.controller.position.minScrollExtent);
    await tester.pumpAndSettle();
    expect(f.reports.last.ids, containsAll(newIDs));
    expect(f.reports.last.distance, closeTo(0, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tall message counts only when its trailing edge has entered',
      (tester) async {
    final f = _Fixture()
      ..rows.addAll([(id: 'tall', height: 400), (id: 'old', height: 48)]);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.controller.jumpTo(60);
    await tester.pumpAndSettle();
    expect(f.reports.last.ids, isNot(contains('tall')));
    f.controller.jumpTo(f.controller.position.minScrollExtent);
    await tester.pumpAndSettle();
    expect(f.reports.last.ids, contains('tall'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('natural dragging to latest keeps the current coordinate window',
      (tester) async {
    final f = _Fixture()..addHistory(40);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.controller.jumpTo(400);
    await tester.pumpAndSettle();
    f.prepend(3, varied: true);
    await tester.pumpAndSettle();
    final minimum = f.controller.position.minScrollExtent;
    expect(minimum, lessThan(0));
    f.controller.jumpTo(minimum + 70);
    await tester.pumpAndSettle();
    // The first scroll may refine the variable-height segment's extent.
    f.controller.jumpTo(f.controller.position.minScrollExtent + 70);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(200, 170));
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(f.controller.position.minScrollExtent, lessThan(0),
        reason: 'An active drag must not reset the latest coordinate center');
    expect(f.reports.last.ids, contains(f.rows.first.id));
    expect(f.reports.last.distance, closeTo(0, 0.5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a visible anchor preserves a surviving neighbour',
      (tester) async {
    final f = _Fixture()..addHistory(60);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.controller.jumpTo(600);
    await tester.pumpAndSettle();
    final visible = f.visible(tester);
    final removed = visible.first;
    final neighbour = visible[1];
    final before = f.y(tester, neighbour);
    f.update(() => f.rows.removeWhere((e) => e.id == removed));
    await tester.pumpAndSettle();
    expect(f.y(tester, neighbour), closeTo(before, 0.5));
    expect(f.reports.last.ids, isNot(contains(removed)));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'async height change retains history and callback uses resized viewport',
      (tester) async {
    final f = _Fixture()..addHistory(60);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.controller.jumpTo(600);
    await tester.pumpAndSettle();
    final visible = f.visible(tester);
    final anchor = visible[1];
    final before = f.y(tester, anchor);
    f.update(() {
      final i = f.rows.indexWhere((e) => e.id == visible.first);
      f.rows[i] = (id: f.rows[i].id, height: 115);
    });
    await tester.pumpAndSettle();
    expect(f.y(tester, anchor), closeTo(before, 0.5));
    final count = f.reports.length;
    f.update(() => f.viewportHeight = 150);
    await tester.pumpAndSettle();
    expect(f.reports.length, greaterThan(count));
    expect(f.reports.last.distance, greaterThan(0));
    f.update(() => f.viewportHeight = 240);
    await tester.pumpAndSettle();
    expect(f.reports.last.distance, greaterThan(0));
    expect(f.y(tester, anchor), closeTo(before, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '1000 varied arrivals stay lazy and one newest jump reaches the real edge',
      (tester) async {
    final f = _Fixture()..addHistory(60);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.controller.jumpTo(500);
    await tester.pumpAndSettle();
    final anchor = f.visible(tester)[1];
    final before = f.y(tester, anchor);
    f.prepend(1000, varied: true);
    await tester.pumpAndSettle();
    expect(f.y(tester, anchor), closeTo(before, 0.5));
    expect(f.builds, lessThan(100));
    final newest = f.rows.first.id;
    f.controller.jumpTo(f.controller.position.minScrollExtent);
    await tester.pumpAndSettle();
    expect(f.reports.last.distance, closeTo(0, 0.5));
    expect(f.reports.last.ids, contains(newest));
    expect(tester.getRect(find.byKey(ValueKey(newest)).first).bottom,
        closeTo(f.viewportHeight, 0.5));
    expect(f.builds, lessThan(180),
        reason: 'Returning must not measure all 1000 rows');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '1000 varied arrivals at latest stay pinned and build only a window',
      (tester) async {
    final f = _Fixture()..addHistory(60);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    f.prepend(1000, varied: true);
    await tester.pumpAndSettle();
    expect(f.reports.last.distance, closeTo(0, 0.5));
    expect(f.reports.last.ids, contains(f.rows.first.id));
    expect(tester.getRect(find.byKey(ValueKey(f.rows.first.id)).first).bottom,
        closeTo(f.viewportHeight, 0.5));
    expect(f.builds, lessThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'controller ownership is optional and replaced external controller is detached',
      (tester) async {
    ScrollController? external;
    final next = ScrollController();
    addTearDown(next.dispose);
    late StateSetter rebuild;
    final reports = <double>[];
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            home: Scaffold(
                body: SizedBox(
                    height: 200,
                    child: StatefulBuilder(builder: (_, setState) {
                      rebuild = setState;
                      return ChatListView(
                          controller: external,
                          itemCount: 40,
                          messageIDs: List.generate(40, (i) => 'id-$i'),
                          loadOnInit: false,
                          onViewportChanged: (_, distance) =>
                              reports.add(distance),
                          itemBuilder: (_, i) => SizedBox(
                              key: ValueKey('id-$i'),
                              height: 48,
                              child: Text('$i')));
                    }))))));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ChatListView), const Offset(0, 250));
    await tester.pumpAndSettle();
    expect(reports.last, greaterThan(0));
    rebuild(() => external = next);
    await tester.pumpAndSettle();
    expect(next.hasClients, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(next.hasClients, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('covered and background routes do not confirm visibility',
      (tester) async {
    final f = _Fixture()..addHistory(30);
    addTearDown(f.controller.dispose);
    await f.pump(tester);
    final context = tester.element(find.byType(ChatListView));
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover'))));
    await tester.pumpAndSettle();
    final count = f.reports.length;
    f.prepend(2);
    await tester.pumpAndSettle();
    expect(f.reports.length, count);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    final restored = f.reports.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    f.prepend(2);
    await tester.pumpAndSettle();
    expect(f.reports.length, restored);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(f.reports.length, greaterThan(restored));
    expect(tester.takeException(), isNull);
  });
}
