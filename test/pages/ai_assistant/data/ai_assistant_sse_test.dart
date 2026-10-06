import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/data/ai_assistant_sse.dart';

void main() {
  test('SSE parser handles arbitrary chunks, CRLF, comments and multiline data', () {
    final parser = AiAssistantSseParser();
    final results = <(String, String)>[];
    void capture(String event, String data) => results.add((event, data));
    parser.feed(': ping\r\n\r\neve', capture);
    parser.feed('nt: delta\r\ndata: {"text":\r\n', capture);
    parser.feed('data: "answer"}\r\n\r', capture);
    parser.feed('\n', capture);
    parser.finish();
    expect(results, [('delta', '{"text":\n"answer"}')]);
  });
  test('incomplete EOF is a failure and resets parser state', () {
    final parser = AiAssistantSseParser();
    parser.feed('event: delta\ndata: {"text":"unfinished"}', (_, __) {});
    expect(parser.finish, throwsFormatException);
    parser.finish();
  });
}
