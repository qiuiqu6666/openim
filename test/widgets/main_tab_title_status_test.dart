import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('failure label distinguishes sync failure and clears on recovery',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MainTabTitle(
                title: 'Chats',
                failed: true,
                failureLabel: 'Message sync failed'))));
    expect(find.text('Message sync failed'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MainTabTitle(title: 'Chats'))));
    expect(find.text('Chats'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });
}
