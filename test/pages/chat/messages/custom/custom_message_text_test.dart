import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/custom/custom_message_text.dart';

void main() {
  const body = '# 开奖记录\n\n| 期数 | 结果 |\n| --- | --- |\n| 12 | **三公** |';
  test('original custom bodies keep newlines, Markdown and nested JSON strings',
      () {
    for (final payload in [
      body,
      jsonEncode(body),
      jsonEncode(jsonEncode(body)),
      jsonEncode({
        'customType': 2026,
        'data': {'text': body}
      }),
      jsonEncode({
        'customType': 2026,
        'data': jsonEncode({'markdown': body})
      }),
      jsonEncode({
        'content': {'body': body}
      }),
    ]) {
      expect(customMessageText(payload, '列表摘要'), body);
    }
  });

  test('unknown maps and arrays retain their fields instead of a summary', () {
    for (final payload in [
      {
        'customType': 99999,
        'result': [1, 2, 3],
        'label': '开奖结果'
      },
      [
        1,
        '二',
        {'result': true}
      ],
      42,
      false,
    ]) {
      expect(jsonDecode(customMessageText(jsonEncode(payload), '摘要')), payload);
    }
  });

  test('empty payload uses description and malformed data stays visible', () {
    expect(customMessageText(null, '兼容旧消息\n第二行'), '兼容旧消息\n第二行');
    expect(customMessageText(' ', '描述'), '描述');
    expect(customMessageText('{broken\n payload', '描述'), '{broken\n payload');
    expect(customMessageText(null, null), '');
  });
}
