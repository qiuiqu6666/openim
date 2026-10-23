import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/widgets/auth/auth_minimal_layout.dart';
import 'package:openim/widgets/auth/auth_form_scaffold.dart';
import 'package:openim/widgets/auth/auth_reference_layout.dart';

void main() {
  for (final hero in [false, true]) {
    for (final height in [844.0, 568.0]) {
      testWidgets('authentication viewport avoids keyboard: hero=$hero $height',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(390, height);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        addTearDown(tester.view.reset);
        const child = Column(children: [
          TextField(),
          SizedBox(height: 250),
          TextField(key: ValueKey('last-field')),
        ]);
        await tester.pumpWidget(MaterialApp(
          home: hero
              ? const AuthEntryScaffold(
                  greeting: 'Hello',
                  accent: 'Welcome',
                  tabs: ['Login', 'Register'],
                  activeTab: 1,
                  footer: Text('Version'),
                  child: child)
              : const AuthFormScaffold(
                  title: 'Verify', subtitle: 'Enter your code', child: child),
        ));
        final heading = find.text(hero ? 'Hello' : 'Verify');
        final headingY = tester.getTopLeft(heading).dy;
        tester.view.padding = const FakeViewPadding(top: 24);
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(heading).dy, headingY);
        final scroll = find.byType(SingleChildScrollView);
        expect(
            tester.getBottomRight(scroll).dy, lessThanOrEqualTo(height - 260));
        await tester.ensureVisible(find.byKey(const ValueKey('last-field')));
        await tester.pumpAndSettle();
        await tester.showKeyboard(find.byKey(const ValueKey('last-field')));
        await tester.pumpAndSettle();
        expect(
            tester.getBottomRight(find.byKey(const ValueKey('last-field'))).dy,
            lessThanOrEqualTo(height - 260));
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final height in [844.0, 568.0]) {
    testWidgets('keyboard preserves form spacing at height $height',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(390, height);
      addTearDown(tester.view.reset);
      const tabs = ValueKey('tabs');
      const field = ValueKey('field');
      await tester.pumpWidget(const MaterialApp(
        home: AuthMinimalLayout(
          header: SizedBox(height: 48),
          footer: Text('Footer'),
          child: Column(children: [
            SizedBox(key: tabs, height: 48, child: Text('Login methods')),
            TextField(key: field),
            SizedBox(height: 160),
          ]),
        ),
      ));
      final tabsTop = tester.getTopLeft(find.byKey(tabs)).dy;
      final fieldTop = tester.getTopLeft(find.byKey(field)).dy;
      for (final inset in [100.0, 200.0, 300.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(tabs)).dy, tabsTop);
        expect(tester.getTopLeft(find.byKey(field)).dy, fieldTop);
        expect(tester.takeException(), isNull);
      }
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(field));
      await tester.showKeyboard(find.byKey(field));
      await tester.ensureVisible(find.byKey(field));
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(find.byKey(field)).dy,
          lessThanOrEqualTo(height - 300));
      expect(tester.takeException(), isNull);
    });
  }
}
