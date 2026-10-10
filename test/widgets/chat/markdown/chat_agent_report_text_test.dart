import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/src/widgets/chat/markdown/chat_message_text_source.dart';
import 'package:openim_common/src/widgets/chat/markdown/chat_agent_report_text.dart';

const report = '''#0：🎲ｈｉ一级数量：1
=======================
#1昵称：叽里呱啦
流水:0
#1总计流水:0
剩余反水:0
已经反水:0
=======================
#0总计流水:304382
剩余反水:121
已经反水:7487
=======================''';

void main() {
  test('agent summary remains literal with original line breaks', () {
    for (final text in [report, report.replaceAll('\n', '\r\n')]) {
      expect(isChatAgentReportText(text), isTrue);
      final message = Message(
          contentType: MessageType.text, textElem: TextElem(content: text));
      expect(chatMessageAllowsMarkdown(message), isFalse);
      expect(chatMessageTextSource(message), text);
    }
  });
  test('ordinary headings and incomplete reports retain Markdown', () {
    for (final text in ['# 标题\n正文', '统计\n====\n流水:0', '#0：一级数量：1']) {
      expect(isChatAgentReportText(text), isFalse);
      expect(
          chatMessageAllowsMarkdown(Message(
              contentType: MessageType.text,
              textElem: TextElem(content: text))),
          isTrue);
    }
  });
}
