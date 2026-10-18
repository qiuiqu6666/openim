import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/compensation/entry/compensation_home_entry.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_poster.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_invitation.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_page.dart';
import 'package:openim/pages/fund/compensation/models/compensation_detail.dart';
import 'support.dart';

void main() {
  testWidgets('wallet poster opens detail only on tap and never claims',
      (t) async {
    final source = FakeSource();
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CompensationHomeEntry(
                active: true, poster: true, source: source))));
    await t.pumpAndSettle();
    expect(find.byType(CompensationPoster), findsOneWidget);
    expect(find.byType(CompensationInvitation), findsNothing);
    await t.tap(find.byKey(const ValueKey('compensation-wallet-banner')));
    await t.pumpAndSettle();
    expect(find.byType(CompensationPage), findsOneWidget);
    expect(source.claims, 0);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'unpublished campaign stays hidden and inactive wallet does not poll',
      (t) async {
    final source = FakeSource()..current = null;
    Widget app(bool active) => MaterialApp(
        home: Scaffold(
            body: CompensationHomeEntry(
                active: active, poster: true, source: source)));
    await t.pumpWidget(app(false));
    await t.pump(const Duration(minutes: 2));
    expect(source.reads, 0);
    await t.pumpWidget(app(true));
    await t.pumpAndSettle();
    expect(source.reads, 1);
    expect(find.byType(CompensationPoster), findsNothing);
    await t.pumpWidget(app(false));
    await t.pump(const Duration(minutes: 2));
    expect(source.reads, 1);
    await t.pumpWidget(const SizedBox());
  });
  for (final dark in [false, true]) {
    testWidgets('poster wraps at 320px with large text in dark=$dark',
        (t) async {
      await t.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(2)),
              child: w!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CompensationPoster(
                      detail: CompensationDetail.fromJson(
                          response(state: 'claimed', total: '500000.00')),
                      onTap: () {})))));
      await t.pumpAndSettle();
      expect(find.byType(Text), findsNothing);
      expect(find.byKey(const ValueKey('compensation-wallet-banner')),
          findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
