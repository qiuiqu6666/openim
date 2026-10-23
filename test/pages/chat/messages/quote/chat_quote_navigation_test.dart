import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/chat/messages/quote/chat_quote_navigation.dart';

void main() {
  Message message(String id) => Message()..clientMsgID = id;
  test('a newer quote supersedes an outstanding lookup and cancellation wins',
      () async {
    final reads = <String, Completer<Message?>>{};
    final focused = <String?>[];
    final feedback = <String>[];
    final navigation = ChatQuoteNavigation(
      findMessage: (id) => (reads[id] = Completer<Message?>()).future,
      focusMessage: (value) async {
        focused.add(value.clientMsgID);
        return true;
      },
      isAvailable: (_) => true,
      showFeedback: feedback.add,
    );
    final first = navigation.open(message('first'), isCurrent: () => true);
    final second = navigation.open(message('second'), isCurrent: () => true);
    reads['second']!.complete(message('second'));
    expect(await second, isTrue);
    reads['first']!.complete(message('first'));
    expect(await first, isFalse);
    expect(focused, ['second']);
    final cancelled =
        navigation.open(message('cancelled'), isCurrent: () => true);
    navigation.cancel();
    reads['cancelled']!.complete(message('cancelled'));
    expect(await cancelled, isFalse);
    expect(focused, ['second']);
    expect(feedback, isEmpty);
  });
  test('lookup failure releases the guard so the user can retry', () async {
    var fail = true;
    final feedback = <String>[];
    final navigation = ChatQuoteNavigation(
        findMessage: (id) async {
          if (fail) throw StateError('offline');
          return message(id);
        },
        focusMessage: (_) async => true,
        isAvailable: (_) => true,
        showFeedback: feedback.add);
    expect(await navigation.open(message('original'), isCurrent: () => true),
        isFalse);
    fail = false;
    expect(await navigation.open(message('original'), isCurrent: () => true),
        isTrue);
    expect(feedback, hasLength(1));
  });
  test('expired stored original never enters the history window', () async {
    final expired = Message.fromJson({
      'clientMsgID': 'original',
      'hasReadTime': DateTime.now()
          .subtract(const Duration(seconds: 10))
          .millisecondsSinceEpoch,
      'attachedInfoElem': {'isPrivateChat': true, 'burnDuration': 1},
    });
    var jumped = false;
    final feedback = <String>[];
    final navigation = ChatQuoteNavigation(
        findMessage: (_) async => expired,
        focusMessage: (_) async {
          jumped = true;
          return true;
        },
        isAvailable: (_) => true,
        showFeedback: feedback.add);
    expect(await navigation.open(message('original'), isCurrent: () => true),
        isFalse);
    expect(jumped, isFalse);
    expect(feedback.single, contains('失效'));
  });
  test('uses stored original rather than quote snapshot and focuses once',
      () async {
    final original = message('original');
    Message? focused;
    final feedback = <String>[];
    final navigation = ChatQuoteNavigation(
        findMessage: (id) async {
          expect(id, 'original');
          return original;
        },
        focusMessage: (value) async {
          focused = value;
          return true;
        },
        isAvailable: (_) => true,
        showFeedback: feedback.add);
    expect(await navigation.open(message('original'), isCurrent: () => true),
        isTrue);
    expect(focused, same(original));
    expect(feedback, isEmpty);
  });
  for (final found in [null, 'wrong', 'removed']) {
    test('missing, mismatched or removed original cannot be restored: $found',
        () async {
      var jumps = 0;
      final feedback = <String>[];
      final navigation = ChatQuoteNavigation(
          findMessage: (_) async => found == null ? null : message(found),
          focusMessage: (_) async {
            jumps++;
            return true;
          },
          isAvailable: (_) => found != 'removed',
          showFeedback: feedback.add);
      expect(
          await navigation.open(
              message(found == 'removed' ? 'removed' : 'original'),
              isCurrent: () => true),
          isFalse);
      expect(jumps, 0);
      expect(feedback, hasLength(1));
    });
  }
  test('duplicate taps and late completion after leaving do not navigate',
      () async {
    final pending = Completer<Message?>();
    var active = true, reads = 0, jumps = 0;
    final feedback = <String>[];
    final navigation = ChatQuoteNavigation(
        findMessage: (_) {
          reads++;
          return pending.future;
        },
        focusMessage: (_) async {
          jumps++;
          return true;
        },
        isAvailable: (_) => true,
        showFeedback: feedback.add);
    final first = navigation.open(message('original'), isCurrent: () => active);
    expect(await navigation.open(message('original'), isCurrent: () => active),
        isFalse);
    active = false;
    pending.complete(message('original'));
    expect(await first, isFalse);
    expect(reads, 1);
    expect(jumps, 0);
    expect(feedback, isEmpty);
  });
}
