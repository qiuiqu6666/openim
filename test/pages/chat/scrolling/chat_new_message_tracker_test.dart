import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/scrolling/chat_new_message_tracker.dart';

Message _message(String? id, {String sender = 'other', int? type}) => Message(
      clientMsgID: id,
      sendID: sender,
      contentType: type ?? MessageType.text,
    );

void main() {
  late ChatNewMessageTracker tracker;
  late bool ownerInactive;
  late String currentUserID;

  setUp(() {
    ownerInactive = false;
    currentUserID = 'me';
    tracker = ChatNewMessageTracker(
      currentUserID: () => currentUserID,
      isClosed: () => ownerInactive,
    );
  });

  tearDown(() => tracker.close());

  test('live arrivals decrease individually as their bubbles become visible',
      () {
    tracker.updateScrollOffset(300);
    for (final id in ['first', 'second', 'third']) {
      tracker.recordIncoming(_message(id));
    }
    expect(tracker.unseenCount.value, 3);

    tracker.markVisible('second');
    expect(tracker.unseenCount.value, 2);
    tracker.markVisible('second');
    tracker.markVisible('old-history');
    tracker.markVisible(null);
    expect(tracker.unseenCount.value, 2);

    tracker.markVisible('first');
    expect(tracker.unseenCount.value, 1);
    tracker.markVisible('third');
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isTrue);
  });

  test('duplicate deliveries do not recount seen messages after scrolling up',
      () {
    tracker.updateScrollOffset(100);
    tracker.recordIncoming(_message('new'));
    tracker.recordIncoming(_message('new'));
    expect(tracker.unseenCount.value, 1);

    tracker.markVisible('new');
    tracker.updateScrollOffset(200);
    tracker.recordIncoming(_message('new'));
    expect(tracker.unseenCount.value, 0);
    tracker.recordIncoming(_message('later'));
    expect(tracker.unseenCount.value, 1);
  });

  test('bottom arrivals stay uncounted when SDK replays them later', () {
    tracker.recordIncoming(_message('at-bottom'));
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isFalse);

    tracker.updateScrollOffset(100);
    tracker.recordIncoming(_message('at-bottom'));
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isTrue);
  });

  test('own messages, typing events and missing IDs never enter the count', () {
    tracker.updateScrollOffset(200);
    tracker.recordIncoming(_message('own', sender: 'me'));
    tracker.recordIncoming(_message('typing', type: MessageType.typing));
    tracker.recordIncoming(_message(null));
    tracker.recordIncoming(_message(''));
    expect(tracker.unseenCount.value, 0);

    tracker.recordIncoming(_message('actual'));
    expect(tracker.unseenCount.value, 1);
  });

  test('deleting an unseen arrival leaves return-to-bottom available', () {
    tracker.updateScrollOffset(100);
    tracker.recordIncoming(_message('deleted'));
    tracker.recordIncoming(_message('kept'));
    tracker.remove('deleted');
    tracker.remove('deleted');
    tracker.remove(null);
    tracker.remove('unknown');
    expect(tracker.unseenCount.value, 1);

    tracker.remove('kept');
    tracker.recordIncoming(_message('deleted'));
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isTrue);
  });

  test('returning to bottom clears pending arrivals without recounting them',
      () {
    tracker.updateScrollOffset(100);
    tracker.recordIncoming(_message('first'));
    tracker.recordIncoming(_message('second'));
    tracker.updateScrollOffset(1);
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isFalse);

    tracker.updateScrollOffset(1.01);
    tracker.recordIncoming(_message('first'));
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isTrue);
    tracker.recordIncoming(_message('third'));
    expect(tracker.unseenCount.value, 1);

    tracker.updateScrollOffset(-2);
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isFalse);
  });

  test('ordinary scroll changes alone do not mark pending messages visible',
      () {
    tracker.updateScrollOffset(400);
    tracker.recordIncoming(_message('new'));
    for (final pixels in [300.0, 100.0, 200.0, 2.0]) {
      tracker.updateScrollOffset(pixels);
      expect(tracker.unseenCount.value, 1);
      expect(tracker.awayFromLatest.value, isTrue);
    }
  });

  test('reset clears route state and lets a new live sequence start', () {
    tracker.updateScrollOffset(100);
    tracker.recordIncoming(_message('new'));
    tracker.reset();
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isFalse);

    tracker.updateScrollOffset(100);
    tracker.recordIncoming(_message('new'));
    expect(tracker.unseenCount.value, 1);
  });

  test('close clears resources and ignores every late event', () {
    tracker.updateScrollOffset(100);
    tracker.recordIncoming(_message('new'));
    tracker.close();
    tracker.updateScrollOffset(200);
    tracker.recordIncoming(_message('late'));
    tracker.markVisible('new');
    tracker.remove('new');
    tracker.reset();
    tracker.close();
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isFalse);
  });

  test('inactive account owner rejects late callbacks before close', () {
    tracker.updateScrollOffset(100);
    tracker.recordIncoming(_message('pending'));
    ownerInactive = true;
    currentUserID = 'another-account';

    tracker.recordIncoming(_message('late'));
    tracker.markVisible('pending');
    tracker.remove('pending');
    tracker.updateScrollOffset(0);
    expect(tracker.unseenCount.value, 1);
    expect(tracker.awayFromLatest.value, isTrue);

    tracker.close();
    expect(tracker.unseenCount.value, 0);
    expect(tracker.awayFromLatest.value, isFalse);
  });
}
