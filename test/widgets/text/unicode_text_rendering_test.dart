import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/quote/chat_quote_content.dart';

import '../../support/unicode/unicode_samples.dart';

Widget _host(Widget child) => ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(home: Scaffold(body: child)),
    );

String _visibleText(WidgetTester tester, Finder parent) => tester
    .widgetList<RichText>(
        find.descendant(of: parent, matching: find.byType(RichText)))
    .map((widget) => widget.text.toPlainText())
    .join();

void main() {
  for (final sample in unicodeSamples) {
    testWidgets('plain and matched text retain ${sample.name}', (tester) async {
      final source = '<literal> &entity; ${sample.text} ${sample.text}';
      await tester.pumpWidget(_host(Column(children: [
        TextView(data: source, wordEllipsis: false),
        MatchTextView(
          text: source,
          patterns: [
            MatchPattern(
                type: PatternType.custom, pattern: RegExp.escape(sample.text)),
          ],
        ),
      ])));
      expect(_visibleText(tester, find.byType(TextView)), source);
      expect(_visibleText(tester, find.byType(MatchTextView)), source);
      expect(tester.takeException(), isNull);
    });

    test('formatted ranges keep every cluster of ${sample.name}', () {
      for (final cluster in sample.text.characters) {
        final source = '前$cluster后';
        final offset = 1 + cluster.length ~/ 2;
        final entity = MessageEntity(type: 'bold', offset: offset, length: 1);
        final spans =
            ChatFormattedText.spans(source, [entity], const TextStyle());
        expect(spans.map((span) => span.toPlainText()).join(), source);
        var end = 0;
        final boundaries = graphemeBoundaries(source);
        for (final span in spans) {
          end += span.toPlainText().length;
          expect(boundaries, contains(end), reason: sample.name);
        }
        expect(entity.offset, offset);
        expect(entity.length, 1);
      }
    });

    test('quote summary retains ${sample.name}', () {
      final message = Message(
          contentType: MessageType.text,
          textElem: TextElem(content: sample.text));
      expect(chatQuoteSummary(message), sample.text);
    });
  }

  testWidgets('partial highlight styles the whole combining sequence',
      (tester) async {
    const source = '前e\u0301\u0327后';
    const hitStyle = TextStyle(fontWeight: FontWeight.bold);
    await tester.pumpWidget(_host(MatchTextView(
      text: source,
      matchTextStyle: hitStyle,
      patterns: [MatchPattern(type: PatternType.custom, pattern: 'e')],
    )));
    final text = tester.widget<RichText>(find.descendant(
        of: find.byType(MatchTextView), matching: find.byType(RichText)));
    final children = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.text != null) children.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        collect(child);
      }
    }

    collect(text.text);
    expect(children.map((span) => span.text).toList(),
        ['前', 'e\u0301\u0327', '后']);
    expect(children[1].style, hitStyle);
  });

  testWidgets('short matched contact values keep safe tap targets',
      (tester) async {
    String? target;
    await tester.pumpWidget(_host(MatchTextView(
      text: 'a@b.co',
      patterns: [
        MatchPattern(
            type: PatternType.email, onTap: (link, _) => target = link),
      ],
    )));
    final rendered = find.descendant(
        of: find.byType(MatchTextView), matching: find.byType(RichText));
    await tester.tapAt(tester.getTopLeft(rendered) + const Offset(8, 8));
    expect(target, 'mailto:a@b.co');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'middle ellipsis preserves complete suffix and avoids duplication',
      (tester) async {
    final cluster =
        unicodeSamples.firstWhere((sample) => sample.name == 'family').text;
    final source = '${'名称' * 40}$cluster';
    await tester.pumpWidget(_host(SizedBox(
      width: 150,
      child: TextWithMidEllipsis(source, endPartLength: 1),
    )));
    final texts = tester.widgetList<Text>(find.descendant(
        of: find.byType(TextWithMidEllipsis), matching: find.byType(Text)));
    expect(texts.map((text) => text.data).join(), source);
    expect(texts.last.data, cluster);
    expect(tester.takeException(), isNull);
  });

  test('display grouping is grapheme based without hidden Unicode insertion',
      () {
    final family =
        unicodeSamples.firstWhere((sample) => sample.name == 'family').text;
    expect('甲$family乙丙'.splitStringEveryNChars(n: 2), '甲$family 乙丙');
    expect(family.fixAutoLines(), family);
    expect(family.fixOverflowEllipsis, family);
  });

  testWidgets('search summary context starts on a whole cluster',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final family =
        unicodeSamples.firstWhere((sample) => sample.name == 'family').text;
    final ending = '后' * 70;
    await tester.pumpWidget(_host(Builder(
        builder: (_) => Text(IMUtils.calContent(
              content: 'abcdefghijklmn$family$ending',
              key: '后',
              style: const TextStyle(fontSize: 17),
              usedWidth: 300,
            )))));
    expect(find.text('...lmn$family$ending'), findsOneWidget);
  });

  testWidgets('Markdown custom matches preserve full source graphemes',
      (tester) async {
    for (final sample in unicodeSamples) {
      await tester.pumpWidget(_host(ChatMarkdownText(
        text: '**标题** ${sample.text}',
        textStyle: const TextStyle(fontSize: 17),
        patterns: [
          MatchPattern(
              type: PatternType.custom, pattern: RegExp.escape(sample.text))
        ],
      )));
      expect(_visibleText(tester, find.byType(ChatMarkdownText)),
          contains(sample.text));
      expect(_visibleText(tester, find.byType(ChatMarkdownText)),
          isNot(contains('\u200B')));
      expect(tester.takeException(), isNull);
    }
  });
}
