import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final entry in <String, String>{
    'baidu.com': 'https://baidu.com',
    'www.baidu.com': 'https://www.baidu.com',
    'docs.example.technology/path?q=hello#part':
        'https://docs.example.technology/path?q=hello#part',
    'example.com:8080/path': 'https://example.com:8080/path',
    'https://example.com': 'https://example.com',
    'HTTP://example.com': 'HTTP://example.com',
  }.entries) {
    testWidgets('tap ${entry.key} opens ${entry.value}', (tester) async {
      String? opened;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MatchTextView(
        maximumWidth: 600,
        text: entry.key,
        patterns: [
          MatchPattern(
              type: PatternType.url, onTap: (value, _) => opened = value)
        ],
      ))));
      await tester.tap(find.byType(RichText).first);
      expect(opened, entry.value);
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(rich.text.toPlainText(), entry.key);
    });
  }

  test('URL boundaries preserve punctuation and avoid email/number matches',
      () {
    final expression = RegExp(regexUrl, unicode: true);
    expect(
        expression
            .allMatches('看 baidu.com，(example.com/path).')
            .map((m) => m[0]),
        ['baidu.com', 'example.com/path']);
    for (final text in [
      'me@baidu.com',
      'me@sub.baidu.com',
      '1.23',
      '192.168.1.1',
      '@baidu.com',
      'bad_domain.com'
    ]) {
      expect(expression.hasMatch(text), isFalse, reason: text);
    }
    expect(expression.firstMatch('https://192.168.1.1:8080/path')?[0],
        'https://192.168.1.1:8080/path');
  });

  testWidgets('email keeps its own click target next to a bare domain',
      (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MatchTextView(
      maximumWidth: 600,
      text: 'me@baidu.com baidu.com',
      patterns: [
        MatchPattern(
            type: PatternType.email, onTap: (value, _) => opened.add(value)),
        MatchPattern(
            type: PatternType.url, onTap: (value, _) => opened.add(value)),
      ],
    ))));
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    void tapLinks(InlineSpan child) {
      if (child is TextSpan && child.recognizer is TapGestureRecognizer) {
        (child.recognizer as TapGestureRecognizer).onTap!();
      }
      if (child is TextSpan) {
        for (final span in child.children ?? <InlineSpan>[]) {
          tapLinks(span);
        }
      }
    }

    tapLinks(rich.text);
    expect(opened, ['mailto:me@baidu.com', 'https://baidu.com']);
  });
}
