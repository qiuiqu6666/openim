import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/home/navigation/animated_home_icon.dart';

void main() {
  for (final motion in HomeIconMotion.values) {
    testWidgets(
        '$motion animates once on selection and respects reduced motion',
        (tester) async {
      Widget host(bool selected, {bool reduced = false}) => MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Center(
                  child: AnimatedHomeIcon(
                      selected: selected,
                      motion: motion,
                      child: const SizedBox(width: 24, height: 24)))));
      List<double> scale() => tester
          .widgetList<Transform>(find.descendant(
              of: find.byType(AnimatedHomeIcon),
              matching: find.byType(Transform)))
          .last
          .transform
          .storage
          .toList();
      await tester.pumpWidget(host(false));
      final idle = scale();
      await tester.pumpWidget(host(true));
      await tester.pump(const Duration(milliseconds: 160));
      expect(scale(), isNot(idle));
      await tester.pumpAndSettle();
      expect(scale(), idle);
      await tester.pumpWidget(host(true));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(host(false));
      await tester.pumpWidget(host(true, reduced: true));
      expect(scale(), idle);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
