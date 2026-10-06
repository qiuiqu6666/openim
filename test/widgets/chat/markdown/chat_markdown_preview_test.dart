import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'support/markdown_fixture.dart';

const _demoText = '''# 消息支持 Markdown

**加粗**、*斜体*、~~删除线~~和 `行内代码`

> 引用内容保持清晰

- 项目一
- 项目二
- [x] 已完成
- [ ] 待处理

```dart
final message = "Hello Markdown";
```

| 项目 | 结果 |
| --- | --- |
| 文本 | 已支持 |
| 列表 | 已支持 |

[查看链接](https://example.com)
''';

void main() {
  setUp(setupMarkdownFixture);
  tearDown(Get.reset);
  for (final variant in [
    (
      name: 'light-375',
      brightness: Brightness.light,
      width: 375.0,
      scale: 1.0,
      rtl: false
    ),
    (
      name: 'dark-375',
      brightness: Brightness.dark,
      width: 375.0,
      scale: 1.0,
      rtl: false
    ),
    (
      name: 'light-320-2x',
      brightness: Brightness.light,
      width: 320.0,
      scale: 2.0,
      rtl: false
    ),
    (
      name: 'dark-320-rtl',
      brightness: Brightness.dark,
      width: 320.0,
      scale: 1.4,
      rtl: true
    ),
  ]) {
    testWidgets('Markdown bubble stays bounded ${variant.name}',
        (tester) async {
      const source = '**支持格式**\n\n- 第一项\n- 第二项\n\n> 引用说明';
      await mountMarkdown(
          tester,
          Column(children: [
            for (final outgoing in [false, true])
              ChatItemView(
                  message: markdownMessage(source,
                      id: '$outgoing', outgoing: outgoing),
                  onTapUserProfile: (_) {}),
          ]),
          brightness: variant.brightness,
          width: variant.width,
          textScale: variant.scale,
          direction: variant.rtl ? TextDirection.rtl : TextDirection.ltr);
      for (final element in find.byType(ChatBubble).evaluate()) {
        final rect =
            tester.getRect(find.byElementPredicate((e) => e == element));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(variant.width));
      }
      expect(renderedMarkdownText(tester), contains('第一项'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('export Markdown preview ${variant.name}', (tester) async {
      await tester.runAsync(loadMarkdownPreviewFonts);
      final text = variant.rtl
          ? '**مرحبا**\n\nهذه رسالة تدعم Markdown.\n\n- العنصر الأول\n- العنصر الثاني\n\n> نص مقتبس'
          : variant.scale > 1
              ? '**消息格式**\n\n- 第一项\n- 第二项\n\n> 引用说明\n\n`代码示例`'
              : _demoText;
      await mountMarkdown(
          tester,
          Column(children: [
            ChatItemView(
                message: markdownMessage(text), onTapUserProfile: (_) {}),
            ChatItemView(
                message: markdownMessage('**收到**\n\n支持 Markdown 气泡。',
                    id: 'reply', outgoing: true),
                onTapUserProfile: (_) {}),
          ]),
          brightness: variant.brightness,
          width: variant.width,
          textScale: variant.scale,
          direction: variant.rtl ? TextDirection.rtl : TextDirection.ltr);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => saveMarkdownPreview(tester, variant.name));
    }, skip: markdownPreviewDirectory.isEmpty);
  }
}
