// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
/// 解析 SSE `text/event-stream` 分块为 event + data。
class SangongSseParser {
  String _buffer = '';

  void feed(
    String chunk,
    void Function(String event, String data) onEvent,
  ) {
    if (chunk.isEmpty) {
      return;
    }
    _buffer += chunk;
    while (true) {
      final boundary = _findEventBoundary(_buffer);
      if (boundary < 0) {
        break;
      }
      final block = _buffer.substring(0, boundary);
      final separatorLength = _buffer.startsWith('\r\n\r\n', boundary) ? 4 : 2;
      _buffer = _buffer.substring(boundary + separatorLength);
      _parseBlock(block, onEvent);
    }
  }

  void reset() {
    _buffer = '';
  }

  static int _findEventBoundary(String source) {
    final lf = source.indexOf('\n\n');
    final crlf = source.indexOf('\r\n\r\n');
    if (lf < 0) {
      return crlf;
    }
    if (crlf < 0) {
      return lf;
    }
    return lf < crlf ? lf : crlf;
  }

  static void _parseBlock(
    String block,
    void Function(String event, String data) onEvent,
  ) {
    var eventName = 'message';
    final dataLines = <String>[];
    for (final rawLine in block.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty || line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) {
      return;
    }
    onEvent(eventName, dataLines.join('\n'));
  }
}
