import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/theme/app_scroll_behavior.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final count in [2, 80]) {
      testWidgets(
          '$platform list with $count rows stops at top and scrolls normally',
          (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: platform),
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
              body: ListView.builder(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            itemExtent: 60,
            itemCount: count,
            itemBuilder: (_, index) => Text('Row $index'),
          )),
        ));
        final list = find.byType(ListView);
        final drag = await tester.startGesture(tester.getCenter(list));
        await drag.moveBy(const Offset(0, 80));
        await drag.moveBy(const Offset(0, 100));
        await tester.pump();
        expect(controller.offset, 0);
        await drag.up();
        await tester.pumpAndSettle();
        if (count == 80) {
          await tester.drag(list, const Offset(0, -250));
          await tester.pumpAndSettle();
          expect(controller.offset, greaterThan(0));
        }
      });
    }
    testWidgets('$platform pull to refresh remains available', (tester) async {
      var refreshes = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
            body: RefreshIndicator(
          onRefresh: () async {
            refreshes++;
          },
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 100, child: Text('Content'))]),
        )),
      ));
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    });
  }
}
