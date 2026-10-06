import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger_floating_entry.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger_tokens.dart';
import 'package:openim/pages/group_features/sangong/services/agent_rebate_float_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _paneKey = ValueKey('ledger-pane');

Finder get _ink => find.descendant(
    of: find.byType(SangongProfileLedgerFloatingEntry),
    matching: find.byType(InkWell));

Future<void> _mount(
  WidgetTester tester, {
  required String preferenceKey,
  VoidCallback? onOpenLedger,
  bool dark = false,
  Size? paneSize,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  final pane = SizedBox(
    key: _paneKey,
    width: paneSize?.width,
    height: paneSize?.height,
    child: Stack(children: [
      const Positioned.fill(child: SizedBox.expand()),
      SangongProfileLedgerFloatingEntry(
          preferenceKey: preferenceKey, onOpenLedger: onOpenLedger),
    ]),
  );
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: Scaffold(
      body: Builder(builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(viewPadding: padding),
          child: paneSize == null
              ? pane
              : Align(alignment: Alignment.topRight, child: pane),
        );
      }),
    ),
  ));
  await tester.pumpAndSettle();
}

void _setScreen(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    testWidgets('ledger float matches 99chat circle and theme dark=$dark',
        (tester) async {
      _setScreen(tester, const Size(360, 760));
      var opens = 0;
      await _mount(tester,
          preferenceKey: 'visual-$dark',
          onOpenLedger: () => opens++,
          dark: dark,
          padding: const EdgeInsets.only(top: 24, bottom: 20));
      final rect = tester.getRect(_ink);
      expect(rect.size, const Size(58, 58));
      expect(rect.left, 290);
      expect(rect.top, 562);
      final circle = tester.widget<Material>(find.ancestor(
        of: _ink,
        matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.shape is CircleBorder),
      ));
      expect(circle.color, SangongProfileLedgerTokens.surface(dark: dark));
      expect(circle.elevation, 6);
      expect(circle.shadowColor, SangongProfileLedgerTokens.shadow(dark: dark));
      final label = tester.widget<Text>(find.text('流'));
      expect(label.style!.fontSize, 24);
      expect(label.style!.fontWeight, FontWeight.w600);
      expect(label.style!.color, SangongProfileLedgerTokens.accent);
      await tester.tap(_ink);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabled ledger stays visible and does not open',
      (tester) async {
    _setScreen(tester, const Size(360, 760));
    await _mount(tester, preferenceKey: 'disabled');
    expect(find.text('流'), findsOneWidget);
    expect(tester.widget<InkWell>(_ink).onTap, isNull);
    await tester.tap(_ink);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag clamps to safe bounds, snaps and saves ledger namespace',
      (tester) async {
    _setScreen(tester, const Size(360, 760));
    var opens = 0;
    await _mount(tester,
        preferenceKey: 'drag-account',
        onOpenLedger: () => opens++,
        padding: const EdgeInsets.fromLTRB(6, 24, 4, 20));
    final gesture = await tester.startGesture(tester.getCenter(_ink));
    await gesture.moveBy(const Offset(-180, -180));
    await tester.pump();
    final circle = tester.widget<Material>(find.ancestor(
      of: _ink,
      matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.shape is CircleBorder),
    ));
    expect(circle.elevation, 10);
    await gesture.moveBy(const Offset(-600, -900));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final rect = tester.getRect(_ink);
    expect(rect.topLeft, const Offset(14, 32));
    expect(opens, 0);
    expect(
        AgentRebateFloatPrefs.instance
            .readOffsetSync('sangong_profile_ledger:drag-account'),
        rect.topLeft);
    expect(
        AgentRebateFloatPrefs.instance.readOffsetSync('drag-account'), isNull);
  });

  testWidgets('rotation keeps the float inside the resized safe pane',
      (tester) async {
    _setScreen(tester, const Size(360, 760));
    await _mount(tester,
        preferenceKey: 'rotation-account', onOpenLedger: () {});
    await tester.drag(_ink, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(tester.getRect(_ink).bottom, 752);
    tester.view.physicalSize = const Size(760, 360);
    await tester.pumpAndSettle();
    final rect = tester.getRect(_ink);
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(752));
    expect(rect.top, greaterThanOrEqualTo(8));
    expect(rect.bottom, lessThanOrEqualTo(352));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide profile pane uses local bounds and preserves mobile prefs',
      (tester) async {
    _setScreen(tester, const Size(1200, 900));
    const account = 'pane-account';
    const storageKey = 'sangong_profile_ledger:$account';
    await AgentRebateFloatPrefs.instance
        .writeOffset(storageKey, const Offset(900, 500));
    await _mount(tester,
        preferenceKey: account,
        onOpenLedger: () {},
        paneSize: const Size(320, 620),
        padding: const EdgeInsets.only(right: 30, top: 40));
    final pane = tester.getRect(find.byKey(_paneKey));
    var circle = tester.getRect(_ink);
    expect(circle.left - pane.left, 250);
    expect(circle.top - pane.top, 442);
    await tester.drag(_ink, const Offset(-1000, 1000));
    await tester.pumpAndSettle();
    circle = tester.getRect(_ink);
    expect(circle.left - pane.left, 8);
    expect(circle.bottom - pane.top, 612);
    expect(AgentRebateFloatPrefs.instance.readOffsetSync(storageKey),
        const Offset(900, 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching viewing account restores only that account position',
      (tester) async {
    _setScreen(tester, const Size(360, 760));
    await AgentRebateFloatPrefs.instance
        .writeOffset('sangong_profile_ledger:owner-one', const Offset(8, 200));
    await AgentRebateFloatPrefs.instance.writeOffset(
        'sangong_profile_ledger:owner-two', const Offset(294, 450));
    await _mount(tester, preferenceKey: 'owner-one', onOpenLedger: () {});
    expect(tester.getRect(_ink).topLeft, const Offset(8, 200));
    await _mount(tester, preferenceKey: 'owner-two', onOpenLedger: () {});
    expect(tester.getRect(_ink).topLeft, const Offset(294, 450));
    expect(tester.takeException(), isNull);
  });
}
