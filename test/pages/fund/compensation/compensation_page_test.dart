import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/compensation/models/compensation_detail.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_page.dart';
import 'package:openim/pages/fund/compensation/entry/compensation_home_entry.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_invitation.dart';
import 'support.dart';
import 'package:openim/pages/wallet/record/wallet_record_screen.dart';

void main() {
  for (final dark in [false, true]) {
    for (final state in ['unclaimed', 'claimed', 'ended', 'ineligible']) {
      testWidgets('$state light/dark=$dark supports narrow large text',
          (t) async {
        await t.binding.setSurfaceSize(const Size(320, 740));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final source = FakeSource()
          ..current = CompensationDetail.fromJson(
              response(state: state, ended: state == 'ended'));
        await t.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            builder: (c, child) => MediaQuery(
                data:
                    MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(2)),
                child: child!),
            home:
                CompensationPage(activityID: 'activity-one', source: source)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('切换预览状态'), findsNothing);
        expect(find.textContaining('演示'), findsNothing);
        final button = switch (state) {
          'unclaimed' => '领取补偿红包',
          'claimed' => '查看入账记录',
          'ended' => '返回首页',
          _ => '查看参与规则'
        };
        expect(find.text(button), findsOneWidget);
        if (state != 'claimed') {
          expect(find.textContaining('88.66'), findsNothing);
        }
        if (state == 'claimed') {
          await t.tap(find.text(button));
          await t.pumpAndSettle();
          expect(find.byType(WalletRecordScreen), findsOneWidget);
          expect(
              t
                  .widget<WalletRecordScreen>(find.byType(WalletRecordScreen))
                  .initialCoin,
              'BI99');
          expect(find.text('补偿入账记录'), findsNothing);
          expect(t.takeException(), isNull);
        }
        await t.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('missing published activity has no banner or invitation',
      (t) async {
    final source = FakeSource()..current = null;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CompensationHomeEntry(active: true, source: source))));
    await t.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(CompensationInvitation), findsNothing);
    expect(source.claims, 0);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('eligible invitation opens detail without claiming', (t) async {
    final source = FakeSource();
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CompensationHomeEntry(active: true, source: source))));
    await t.pumpAndSettle();
    expect(find.byType(CompensationInvitation), findsOneWidget);
    await t.tap(find.bySemanticsLabel('查看并领取'));
    await t.pumpAndSettle();
    expect(find.byType(CompensationPage), findsOneWidget);
    expect(source.claims, 0);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('poster illustration opens detail without claiming', (t) async {
    final source = FakeSource();
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CompensationHomeEntry(active: true, source: source))));
    await t.pumpAndSettle();
    expect(find.byType(CompensationInvitation), findsOneWidget);
    final poster = find.byKey(const ValueKey('compensation-invitation-poster'));
    final rect = t.getRect(poster);
    await t.tapAt(rect.topLeft + Offset(rect.width * .5, rect.height * .3));
    await t.pumpAndSettle();
    expect(find.byType(CompensationPage), findsOneWidget);
    expect(source.claims, 0);
    await t.pumpWidget(const SizedBox());
  });
  for (final validSession in [true, false]) {
    testWidgets(
        'dialog-covered home navigates only for valid session=$validSession',
        (t) async {
      final source = FakeSource();
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ValueListenableBuilder<bool>(
                  valueListenable: active,
                  builder: (_, value, __) =>
                      CompensationHomeEntry(active: value, source: source)))));
      await t.pumpAndSettle();
      expect(find.byType(CompensationInvitation), findsOneWidget);
      // HomeView disables live updates when the root dialog covers its route.
      active.value = false;
      await t.pump();
      source.valid = validSession;
      await t.tap(find.byKey(const ValueKey('compensation-invitation-poster')));
      await t.pumpAndSettle();
      expect(find.byType(CompensationInvitation), findsNothing);
      expect(find.byType(CompensationPage),
          validSession ? findsOneWidget : findsNothing);
      expect(source.claims, 0);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('network failure offers retry with no claim action', (t) async {
    final source = FakeSource()..failRead = true;
    await t.pumpWidget(MaterialApp(
        home: CompensationPage(activityID: 'activity-one', source: source)));
    await t.pumpAndSettle();
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('领取补偿红包'), findsNothing);
    source.failRead = false;
    await t.tap(find.text('重新加载'));
    await t.pumpAndSettle();
    expect(find.text('领取补偿红包'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
