import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/presentation/loading/moments_header_loading.dart';

Widget host(bool loading, {bool reduced = false}) => MaterialApp(
    home: MediaQuery(
        data: MediaQueryData(
            disableAnimations: reduced,
            padding: const EdgeInsets.only(top: 32)),
        child: Align(
            alignment: Alignment.topLeft,
            child: MomentsHeaderLoading(loading: loading))));
final visual = find.byKey(const ValueKey('moments_header_loading'));
double y(WidgetTester tester) => tester
    .widget<Transform>(
        find.byKey(const ValueKey('moments_header_loading_motion')))
    .transform
    .storage[13];

void main() {
  testWidgets('enters from above, spins, exits before removal with stable slot',
      (tester) async {
    await tester.pumpWidget(host(true));
    final slot = tester.getRect(find.byType(MomentsHeaderLoading));
    expect(y(tester), lessThan(-80));
    final turns = tester
        .widget<RotationTransition>(find.byType(RotationTransition))
        .turns;
    await tester.pump(const Duration(milliseconds: 180));
    expect(y(tester), lessThan(0));
    expect(turns.value, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(y(tester), 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(turns.value, greaterThan(0));
    await tester.pumpWidget(host(false));
    expect(visual, findsOneWidget);
    expect(y(tester), 0);
    await tester.pump(const Duration(milliseconds: 399));
    expect(y(tester), 0);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 130));
    expect(y(tester), lessThan(0));
    expect(visual, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(visual, findsNothing);
    expect(tester.getRect(find.byType(MomentsHeaderLoading)), slot);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'fast completion finishes entry and minimum spin; renewed loading remains visible',
      (tester) async {
    await tester.pumpWidget(host(true));
    await tester.pump(const Duration(milliseconds: 90));
    final entering = y(tester);
    await tester.pumpWidget(host(false));
    expect(y(tester), entering);
    await tester.pump(const Duration(milliseconds: 20));
    final leaving = y(tester);
    expect(leaving, greaterThan(entering));
    await tester.pumpWidget(host(true));
    expect(y(tester), leaving);
    await tester.pump(const Duration(milliseconds: 400));
    expect(y(tester), 0);
    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 599));
    expect(y(tester), 0);
    expect(visual, findsOneWidget);
    await tester.pumpWidget(host(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(y(tester), 0);
    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(y(tester), lessThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows static icon and removes without movement',
      (tester) async {
    await tester.pumpWidget(host(true, reduced: true));
    expect(y(tester), 0);
    final turns = tester
        .widget<RotationTransition>(find.byType(RotationTransition))
        .turns;
    await tester.pump(const Duration(milliseconds: 300));
    expect(turns.value, 0);
    await tester.pumpWidget(host(false, reduced: true));
    expect(visual, findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
