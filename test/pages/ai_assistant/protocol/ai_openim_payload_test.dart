import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/protocol/ai_openim_payload.dart';

void main() {
  test('document selection enforces supported suffixes and byte limit', () {
    for (final name in ['notes.txt', 'REPORT.PDF', 'review.docx']) {
      expect(AiOpenimPayload.acceptsDocument(name, 1), isTrue);
      expect(
        AiOpenimPayload.acceptsDocument(name, AiOpenimPayload.maxDocumentBytes),
        isTrue,
      );
      expect(
        AiOpenimPayload.acceptsDocument(
            name, AiOpenimPayload.maxDocumentBytes + 1),
        isFalse,
      );
    }
    for (final name in [
      'report.doc',
      'sheet.xlsx',
      'report',
      '.pdf',
      'a.pdf.exe'
    ]) {
      expect(AiOpenimPayload.acceptsDocument(name, 5), isFalse);
    }
    expect(AiOpenimPayload.acceptsDocument('empty.txt', 0), isTrue);
    expect(AiOpenimPayload.acceptsDocument('invalid.txt', -1), isFalse);
  });

  test('image payload keeps an empty prompt and encodes multiline text', () {
    expect(jsonDecode(AiOpenimPayload.image('  ')), {'prompt': ''});
    expect(jsonDecode(AiOpenimPayload.image('  湖边\n"小屋"  ')),
        {'prompt': '湖边\n"小屋"'});
  });

  test('group card contains server field names without a separate chat API',
      () {
    expect(
      jsonDecode(AiOpenimPayload.groupCard(
          groupID: 'g_1', groupName: '设计组', faceURL: 'https://host/avatar')),
      {'groupID': 'g_1', 'groupName': '设计组', 'faceURL': 'https://host/avatar'},
    );
  });
}
