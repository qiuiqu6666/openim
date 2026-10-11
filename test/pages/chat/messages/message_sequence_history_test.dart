import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/identity/message_sequence_history.dart';

void main() {
  test('100000 contiguous messages retain one exact interval', () {
    final history = MessageSequenceHistory();
    for (var i = 1; i <= 100000; i++) {
      expect(history.add('$i', i), isTrue);
    }
    expect(history.rangeCount, 1);
    expect(history.unsequencedCount, 0);
    expect(history.add('old', 1), isFalse);
    expect(history.contains('next', 100001), isFalse);
  });
  test('out of order holes remain unseen until individually observed', () {
    final history = MessageSequenceHistory();
    history.add('one', 1);
    history.add('three', 3);
    expect(history.contains('two', 2), isFalse);
    expect(history.add('two', 2), isTrue);
    expect(history.rangeCount, 1);
    expect(history.add('two', 2), isFalse);
    expect(history.add('no-seq', null), isTrue);
    expect(history.add('no-seq', 0), isFalse);
    expect(history.add('no-seq', 5), isFalse);
    expect(history.contains('four', 4), isFalse);
    history.clear();
    expect(history.rangeCount, 0);
    expect(history.add('no-seq', null), isTrue);
  });
}
