import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/editing/batch_read/conversation_batch_read_api.dart';
import 'package:openim/pages/conversation/editing/batch_read/conversation_batch_read_projection.dart';

ConversationInfo row(int seq, int unread) => ConversationInfo(
    conversationID: 'sg_a',
    unreadCount: unread,
    latestMsgSendTime: seq,
    latestMsg: Message(clientMsgID: 'm$seq', seq: seq));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => OpenIM.iMManager.userID = 'self');
  test('ack clears only captured preview; a new arrival stays unread', () {
    final old = row(5, 3);
    final projection = ConversationBatchReadProjection([old]);
    final newer = row(6, 4);
    expect(
        projection.confirm([const BatchReadTarget('sg_a', 5)], [newer], (_) {}),
        false);
    expect(newer.unreadCount, 4);
    expect(
        projection.confirm([const BatchReadTarget('sg_a', 5)], [old], (_) {}),
        true);
    expect(old.unreadCount, 0);
  });
  test('increased unread, unknown seq and insufficient watermark never clear',
      () {
    for (final seq in [0, 5]) {
      final initial = row(seq, 3);
      final projection = ConversationBatchReadProjection([initial]);
      final increased = row(seq, 4);
      expect(
          projection
              .confirm([const BatchReadTarget('sg_a', 5)], [increased], (_) {}),
          false);
      expect(
          projection
              .confirm([const BatchReadTarget('sg_a', 4)], [initial], (_) {}),
          false);
    }
  });
  test('account switch invalidates all captured acknowledgements', () {
    final initial = row(5, 3);
    final projection = ConversationBatchReadProjection([initial]);
    OpenIM.iMManager.userID = 'other';
    expect(
        projection.confirm([const BatchReadTarget('sg_a', 5)], [initial],
            (_) => fail('stale session')),
        false);
    expect(initial.unreadCount, 3);
  });
}
