import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

import 'support/markdown_fixture.dart';

const _bodyStyle = TextStyle(fontSize: 16, height: 1.3);

Widget _body(String source,
        {List<MatchPattern> patterns = const [],
        Function(String?)? onSource,
        double width = 320}) =>
    Center(
      child: SizedBox(
        width: width,
        child: ChatMarkdownText(
          text: source,
          textStyle: _bodyStyle,
          patterns: patterns,
          onVisibleTrulyText: onSource,
        ),
      ),
    );

String _withoutBreaks(String value) => value.replaceAll('\u200B', '');

Iterable<(String, TextStyle)> _spans(InlineSpan root,
    [TextStyle inherited = const TextStyle()]) sync* {
  if (root is! TextSpan) return;
  final style = inherited.merge(root.style);
  if (root.text?.isNotEmpty ?? false) yield (root.text!, style);
  for (final child in root.children ?? const <InlineSpan>[]) {
    yield* _spans(child, style);
  }
}

List<TextStyle> _stylesFor(WidgetTester tester, String value) => [
      for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
        for (final (text, style) in _spans(rich.text))
          if (_withoutBreaks(text).contains(value)) style,
    ];

/// Tap rendered glyphs, including custom matches embedded in WidgetSpans.
Future<void> _tapText(WidgetTester tester, String label) async {
  for (final element in find.byType(RichText).evaluate()) {
    final rich = element.widget as RichText;
    final text = rich.text.toPlainText();
    final visible = _withoutBreaks(text);
    final index = visible.indexOf(label);
    if (index < 0) continue;
    var visibleOffset = 0;
    var start = 0;
    var end = text.length;
    for (var offset = 0; offset < text.length; offset++) {
      if (text[offset] == '\u200B') continue;
      if (visibleOffset == index) start = offset;
      if (visibleOffset == index + label.length - 1) {
        end = offset + 1;
        break;
      }
      visibleOffset++;
    }
    final paragraph = element.renderObject! as RenderParagraph;
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end));
    if (boxes.isEmpty) continue;
    await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
    await tester.pump();
    return;
  }
  fail('No rendered glyphs found for $label');
}

void main() {
  setUp(setupMarkdownFixture);

  test('Markdown detection recognizes supported inline and block syntax', () {
    for (final source in [
      '# 标题',
      '小标题\n---',
      '**粗体**',
      '*斜体*',
      '~~删除~~',
      '`代码`',
      '> 引用',
      '- 列表',
      '1. 顺序列表',
      '- [x] 完成',
      '```dart\nprint(1);\n```',
      '~~~\n代码\n~~~',
      '[链接](https://example.com)',
      '![图片](https://example.com/photo.png)',
      '<https://example.com>',
      '[文档][docs]\n\n[docs]: https://example.com',
      '    const value = 2;\n    print(value);',
      '\tconst value = 2;',
      r'\*文字\*',
      r'\# 标题',
      '| 名称 | 数量 |\n| --- | --- |\n| USDT | 2 |',
    ]) {
      expect(ChatMarkdownText.hasMarkdown(source), isTrue, reason: source);
    }
  });

  test('Plain chat messages do not get routed through Markdown', () {
    for (final source in [
      '',
      '你好\n第二行',
      'user_name',
      'support@example.com',
      'https://example.com/path',
      '13812345678',
      '@abcdefgh12',
      '2 * 3 = 6',
      '这是 ** 没有闭合的文字',
    ]) {
      expect(ChatMarkdownText.hasMarkdown(source), isFalse, reason: source);
    }
  });

  testWidgets('headings emphasis strikeout and explicit line breaks render',
      (tester) async {
    await mountMarkdown(tester, _body('# 标题\n\n**粗体** *斜体* ~~删除~~\n换行后的正文'));
    final visible = _withoutBreaks(renderedMarkdownText(tester));
    expect(visible, contains('标题'));
    expect(visible, contains('粗体'));
    expect(visible, contains('换行后的正文'));
    expect(visible, isNot(contains('**')));
    expect(_stylesFor(tester, '标题').any((s) => s.fontSize! > 16), isTrue);
    expect(_stylesFor(tester, '粗体').any((s) => s.fontWeight == FontWeight.w700),
        isTrue);
    expect(_stylesFor(tester, '斜体').any((s) => s.fontStyle == FontStyle.italic),
        isTrue);
    expect(
        _stylesFor(tester, '删除').any(
            (s) => s.decoration?.contains(TextDecoration.lineThrough) ?? false),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list task code and table content render without raw markers',
      (tester) async {
    await mountMarkdown(
      tester,
      _body('> 引用正文\n\n- 第一项\n- 第二项\n\n'
          '1. 步骤一\n2. 步骤二\n\n- [x] 已完成\n- [ ] 待完成\n\n'
          '```dart\nprint("hello");\n```\n\n'
          '| 币种 | 数量 |\n| --- | --- |\n| USDT | 2 |'),
    );
    final visible = _withoutBreaks(renderedMarkdownText(tester));
    for (final label in [
      '引用正文',
      '第一项',
      '第二项',
      '步骤一',
      '步骤二',
      '已完成',
      '待完成',
      'print("hello");',
      '币种',
      '数量',
      'USDT',
    ]) {
      expect(visible, contains(label), reason: label);
    }
    expect(visible, isNot(contains('[x]')));
    expect(visible, isNot(contains('```')));
    expect(visible, isNot(contains('| --- |')));
    expect(_stylesFor(tester, 'print(').any((s) => s.fontFamily == 'monospace'),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy callback retains exact source and meaningful newlines',
      (tester) async {
    const source = '# 标题\n\n**粗体**\n第二行\n\n```\n保留 * 星号\n```';
    final sources = <String?>[];
    await mountMarkdown(tester, _body(source, onSource: sources.add));
    expect(sources, isNotEmpty);
    expect(sources.every((value) => value == source), isTrue);
    await tester.pump();
    expect(sources.last, source);
  });

  testWidgets('escaped markers display literally and copying preserves source',
      (tester) async {
    const source = '\\*文字\\*\n\\# 标题';
    final sources = <String?>[];
    await mountMarkdown(
      tester,
      SizedBox(
        width: 320,
        child: ChatText(
          text: source,
          textStyle: _bodyStyle,
          enableMarkdown: true,
          onVisibleTrulyText: sources.add,
        ),
      ),
    );
    final visible = renderedMarkdownText(tester);
    expect(visible, contains('*文字*'));
    expect(visible, contains('# 标题'));
    expect(visible, isNot(contains('\\')));
    expect(
        _stylesFor(tester, '文字').every((style) =>
            style.fontWeight != FontWeight.w700 &&
            style.fontStyle != FontStyle.italic),
        isTrue);
    expect(sources, isNotEmpty);
    expect(sources.every((s) => s == source), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit and bare URLs preserve chat navigation callbacks',
      (tester) async {
    final taps = <(String, PatternType?)>[];
    await mountMarkdown(
      tester,
      _body(
          '## 链接\n\n[项目](https://example.com/docs)\n'
          'https://example.com/raw\n<https://example.com/auto>',
          patterns: [
            MatchPattern(
                type: PatternType.url,
                onTap: (url, type) => taps.add((url, type))),
          ]),
    );
    await _tapText(tester, '项目');
    await _tapText(tester, 'https://example.com/raw');
    await _tapText(tester, 'https://example.com/auto');
    expect(taps, [
      ('https://example.com/docs', PatternType.url),
      ('https://example.com/raw', PatternType.url),
      ('https://example.com/auto', PatternType.url),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mentions account IDs email and telephone preserve callbacks',
      (tester) async {
    final taps = <(String, PatternType?)>[];
    void tap(String value, PatternType? type) => taps.add((value, type));
    await mountMarkdown(
      tester,
      _body(
          '**联系** @好友 @abcdefgh12\n'
          'support@example.com\n[拨打](tel:13812345678)',
          patterns: [
            MatchPattern(type: PatternType.custom, pattern: '@好友', onTap: tap),
            MatchPattern(
                type: PatternType.custom, pattern: '@abcdefgh12', onTap: tap),
            MatchPattern(type: PatternType.email, onTap: tap),
            MatchPattern(type: PatternType.mobile, onTap: tap),
          ]),
    );
    await _tapText(tester, '@好友');
    await _tapText(tester, '@abcdefgh12');
    await _tapText(tester, 'support@example.com');
    await _tapText(tester, '拨打');
    expect(taps, [
      ('@好友', PatternType.custom),
      ('@abcdefgh12', PatternType.custom),
      ('mailto:support@example.com', PatternType.email),
      ('tel:13812345678', PatternType.mobile),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsafe Markdown links never invoke a chat callback',
      (tester) async {
    final taps = <String>[];
    await mountMarkdown(
      tester,
      _body(
          '[脚本](javascript:alert) [文件](file:///etc/passwd) '
          '[数据](data:text/html,test) [应用](intent:open)',
          patterns: [
            MatchPattern(
                type: PatternType.url, onTap: (url, _) => taps.add(url)),
          ]),
    );
    for (final label in ['脚本', '文件', '数据', '应用']) {
      await _tapText(tester, label);
    }
    expect(taps, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a standalone phone line remains tappable in Markdown messages',
      (tester) async {
    final taps = <String>[];
    await mountMarkdown(
      tester,
      _body('# 联系电话\n\n13812345678', patterns: [
        MatchPattern(type: PatternType.mobile, onTap: (v, _) => taps.add(v)),
      ]),
    );
    await _tapText(tester, '13812345678');
    expect(taps, ['tel:13812345678']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone matches work within prose while excluding account IDs',
      (tester) async {
    final taps = <String>[];
    await mountMarkdown(
      tester,
      _body(
          '联系 **13812345678** 或 13912345678\n'
          'ID a13812345678b 和 1138123456789 不应成为电话',
          patterns: [
            MatchPattern(
                type: PatternType.mobile, onTap: (v, _) => taps.add(v)),
          ]),
    );
    await _tapText(tester, '13812345678');
    await _tapText(tester, '13912345678');
    await _tapText(tester, 'a13812345678b');
    await _tapText(tester, '1138123456789');
    expect(taps, ['tel:13812345678', 'tel:13912345678']);
    expect(
        _stylesFor(tester, '13812345678')
            .any((s) => s.fontWeight == FontWeight.w700),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference links route to their definition URL', (tester) async {
    final taps = <String>[];
    await mountMarkdown(
      tester,
      _body('[文档][docs]\n\n[docs]: https://example.com/reference', patterns: [
        MatchPattern(type: PatternType.url, onTap: (v, _) => taps.add(v)),
      ]),
    );
    await _tapText(tester, '文档');
    expect(taps, ['https://example.com/reference']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a same-source rebuild uses the current navigation handler',
      (tester) async {
    final taps = <String>[];
    const source = '**地址** https://example.com/change';
    await mountMarkdown(
      tester,
      _body(source, patterns: [
        MatchPattern(
            type: PatternType.url, onTap: (_, __) => taps.add('first')),
      ]),
    );
    await _tapText(tester, 'https://example.com/change');
    await mountMarkdown(
      tester,
      _body(source, patterns: [
        MatchPattern(
            type: PatternType.url, onTap: (_, __) => taps.add('second')),
      ]),
    );
    await _tapText(tester, 'https://example.com/change');
    expect(taps, ['first', 'second']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom matches and standard links share explicit text scaling',
      (tester) async {
    await mountMarkdown(
      tester,
      SizedBox(
        width: 320,
        child: ChatMarkdownText(
          text: '**正文**\n@好友 [文档](https://example.com/docs)',
          textStyle: _bodyStyle,
          textScaler: TextScaler.linear(1.75),
          patterns: [
            MatchPattern(type: PatternType.custom, pattern: '@好友'),
            MatchPattern(type: PatternType.url),
          ],
        ),
      ),
      textScale: 2,
    );
    for (final label in ['正文', '@好友', '文档']) {
      final rich = tester.widgetList<RichText>(find.byType(RichText)).where(
          (widget) =>
              _withoutBreaks(widget.text.toPlainText()).contains(label));
      expect(rich, isNotEmpty, reason: label);
      expect(rich.every((widget) => widget.textScaler.scale(16) == 28), isTrue,
          reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('code spans and code blocks do not activate chat matches',
      (tester) async {
    final taps = <String>[];
    await mountMarkdown(
      tester,
      _body(
          '`https://example.com/inline`\n\n'
          '```\n@好友 support@example.com\nhttps://example.com/block\n```',
          patterns: [
            MatchPattern(type: PatternType.url, onTap: (v, _) => taps.add(v)),
            MatchPattern(type: PatternType.email, onTap: (v, _) => taps.add(v)),
            MatchPattern(
                type: PatternType.custom,
                pattern: '@好友',
                onTap: (v, _) => taps.add(v)),
          ]),
    );
    for (final label in [
      'https://example.com/inline',
      '@好友',
      'support@example.com',
      'https://example.com/block',
    ]) {
      await _tapText(tester, label);
    }
    expect(taps, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow bubbles wrap long code and allow wide table scrolling',
      (tester) async {
    final source = '## 币种信息\n\n```${'x' * 220}```\n\n'
        '| 币种 | 提现规则 | 网络 |\n| --- | --- | --- |\n'
        '| USDT | ${'规则' * 30} | TRON |';
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await mountMarkdown(tester, _body(source, width: 220),
          brightness: brightness, width: 320, textScale: 2);
      expect(tester.takeException(), isNull, reason: '$brightness');
      final bubble = tester.getRect(find.byType(ChatMarkdownText));
      expect(bubble.width, lessThanOrEqualTo(220));
      expect(renderedMarkdownText(tester), contains('USDT'));
      final horizontal = find.byWidgetPredicate((widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal);
      expect(horizontal, findsAtLeastNWidgets(1));
      await tester.ensureVisible(horizontal.last);
      await tester.pumpAndSettle();
      final scrolling = find.descendant(
          of: horizontal.last, matching: find.byType(Scrollable));
      final state = tester.state<ScrollableState>(scrolling.first);
      final previous = state.position.pixels;
      await tester.drag(horizontal.last, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(state.position.pixels, greaterThan(previous));
      expect(tester.takeException(), isNull);
    }
  });
}
