import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/navigation/chat_entry_trace.dart';

void main() {
  test('stages are monotonic, recorded once and fenced at route disposal', () {
    var us = 0;
    final trace = ChatEntryTrace(1, elapsedMicroseconds: () => us);
    void paint(
            {bool ready = true,
            bool visible = true,
            bool current = true,
            bool interactive = false,
            bool messages = true}) =>
        trace.painted(
            publishable: ready,
            hasVisibleMessages: messages,
            contentVisible: visible,
            canInteract: interactive,
            current: current);
    us = 1000;
    paint(ready: false);
    paint(visible: false);
    paint(current: false);
    expect(trace.milliseconds.keys, ['tap']);
    us = 4000;
    paint();
    expect(trace.milliseconds['first_correct_message_frame'], 4);
    expect(trace.listInteractive, isFalse);
    us = 7000;
    paint(interactive: true);
    expect(trace.milliseconds['first_correct_message_frame'], 4);
    expect(trace.milliseconds['list_interactive'], 7);
    expect(trace.complete, isFalse);
    trace.mark('transition_finished');
    expect(trace.complete, isTrue);
    trace.close();
    us = 9000;
    trace.mark('late_response');
    expect(trace.milliseconds.containsKey('late_response'), isFalse);
  });
  test('a confirmed empty window is not reported as a message frame', () {
    final trace = ChatEntryTrace(2);
    trace.painted(
        publishable: true,
        hasVisibleMessages: false,
        contentVisible: true,
        canInteract: true,
        current: true);
    expect(trace.milliseconds.containsKey('first_empty_frame'), isTrue);
    expect(
        trace.milliseconds.containsKey('first_correct_message_frame'), isFalse);
    trace.close();
  });
}
