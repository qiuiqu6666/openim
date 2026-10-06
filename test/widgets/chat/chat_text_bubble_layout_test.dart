import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  Future<void> footerFixture(WidgetTester tester, String text,
      {double scale = 1, bool separate = false}) async {
    const bodyStyle = TextStyle(fontSize: 16, height: 1.30);
    const timeStyle = TextStyle(fontSize: 11, height: 1);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: 200,
              child: ChatTextBubbleLayout(
                text: text,
                textStyle: bodyStyle,
                timeText: '15:04',
                metadataTextStyle: timeStyle,
                forceSeparateFooter: separate,
                body: Text(text,
                    key: const ValueKey('footer-body'), style: bodyStyle),
                metadata: const Text('15:04',
                    key: ValueKey('footer-time'), style: timeStyle),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('short mixed text and scaled fonts keep a clear footer gap',
      (tester) async {
    for (final text in ['Hi', '2门20', '中文消息']) {
      for (final scale in [1.0, 2.0]) {
        await footerFixture(tester, text, scale: scale);
        final body = tester.getRect(find.byKey(const ValueKey('footer-body')));
        final time = tester.getRect(find.byKey(const ValueKey('footer-time')));
        expect(time.top - body.bottom, greaterThanOrEqualTo(8));
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets('a full final line reserves a new footer line without overlap',
      (tester) async {
    await footerFixture(tester, '123456789012');
    final body = tester.getRect(find.byKey(const ValueKey('footer-body')));
    final time = tester.getRect(find.byKey(const ValueKey('footer-time')));
    expect(time.top - body.bottom, closeTo(8, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich and forced footers remain separate at double text scale',
      (tester) async {
    for (final (text, forced) in [('🙂', false), ('Hi', true)]) {
      await footerFixture(tester, text, scale: 2, separate: forced);
      final body = tester.getRect(find.byKey(const ValueKey('footer-body')));
      final time = tester.getRect(find.byKey(const ValueKey('footer-time')));
      expect(time.top - body.bottom, closeTo(8, .01));
      expect(time.height, greaterThanOrEqualTo(22));
      expect(tester.takeException(), isNull);
    }
  });
}
