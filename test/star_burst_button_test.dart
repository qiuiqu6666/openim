import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/star_burst_button.dart';

void main() {
  testWidgets('tap bursts, vibrates once and blocks duplicate requests',
      (tester) async {
    var haptics = 0;
    var requests = 0;
    final pending = Completer<void>();
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StarBurstButton(
      starred: false,
      tooltip: 'Star',
      color: Colors.blue,
      onPressed: () {
        requests++;
        return pending.future;
      },
    ))));
    await tester.tap(find.byType(IconButton));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.auto_awesome), findsNWidgets(8));
    expect(haptics, 1);
    await tester.tap(find.byType(IconButton));
    expect(requests, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });
}
