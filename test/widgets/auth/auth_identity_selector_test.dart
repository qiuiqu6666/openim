import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/widgets/auth/auth_identity_selector.dart';

void main() {
  testWidgets('both full tab halves respond at their outer and inner edges',
      (tester) async {
    var email = false;
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: SizedBox(
        width: 320,
        child: StatefulBuilder(
            builder: (context, setState) => AuthIdentitySelector(
                email: email,
                onChanged: (value) => setState(() {
                      if (email == value) return;
                      email = value;
                      changes++;
                    }))),
      ),
    ))));
    final phone = find.byKey(const ValueKey('auth-identity-phone'));
    final mail = find.byKey(const ValueKey('auth-identity-email'));
    expect(tester.getSize(phone).width, 160);
    expect(tester.getSize(mail).width, 160);
    for (final edge in [1.0, 159.0, 80.0, 1.0]) {
      for (final target in [mail, phone]) {
        final rect = tester.getRect(target);
        await tester.tapAt(Offset(rect.left + edge, rect.center.dy));
        await tester.pump();
        expect(email, target == mail);
      }
    }
    expect(changes, 8);
    await tester.tap(phone);
    await tester.pump();
    expect(changes, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid alternating taps are delivered before the next frame',
      (tester) async {
    final selections = <bool>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AuthIdentitySelector(
                email: false, onChanged: selections.add))));
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const ValueKey('auth-identity-email')));
      await tester.tap(find.byKey(const ValueKey('auth-identity-phone')));
    }
    expect(selections, List.generate(20, (index) => index.isEven));
  });
}
