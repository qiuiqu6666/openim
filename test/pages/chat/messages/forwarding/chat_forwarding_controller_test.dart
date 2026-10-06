import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/services/chat_message_sender.dart';

import 'support/chat_forwarding_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForwardingFixture fixture;
  setUp(() => fixture = ForwardingFixture());
  tearDown(() => fixture.dispose());

  test(
      'individual batch selects recipients once and preserves chronological ties',
      () async {
    fixture.onPick = () async => {
          'checkedList': [UserInfo(userID: 'user'), GroupInfo(groupID: 'group')]
        };
    final selection = [
      forwardingSource('later', time: 20),
      forwardingSource('same-first', time: 10),
      forwardingSource('same-second', time: 10),
    ];
    expect(await fixture.forward(selection, merged: false), isTrue);
    expect(fixture.pickerDescriptions, hasLength(1));
    expect(fixture.originals, [
      'same-first',
      'same-second',
      'later',
      'same-first',
      'same-second',
      'later'
    ]);
    expect(selection.map((message) => message.clientMsgID),
        ['later', 'same-first', 'same-second']);
    expect(fixture.sends.take(3).map((send) => send.target.userID),
        everyElement('user'));
    expect(fixture.sends.skip(3).map((send) => send.target.groupID),
        everyElement('group'));
    expect(fixture.timeline.map((message) => message.clientMsgID),
        ['later', 'same-first', 'same-second']);
    expect(fixture.inputResets, 0);
    expect(fixture.toasts, isEmpty);
    expect(fixture.reviewRequests, 0);
  });

  test(
      'merged batch uses ordered history, title and three summaries per target',
      () async {
    fixture.onPick = () async => {
          'checkedList': [UserInfo(userID: 'user'), GroupInfo(groupID: 'group')]
        };
    final selection = [
      forwardingSource('four', time: 4),
      forwardingSource('one', time: 1),
      forwardingSource('two', time: 2),
      forwardingSource('three', time: 3),
    ];
    expect(await fixture.forward(selection, merged: true), isTrue);
    expect(fixture.pickerDescriptions, hasLength(1));
    expect(fixture.originals, isEmpty);
    expect(fixture.sends, hasLength(2));
    expect(fixture.merges, hasLength(2));
    for (final merge in fixture.merges) {
      expect(merge.ids, ['one', 'two', 'three', 'four']);
      expect(merge.title, startsWith('Current chat · '));
      expect(merge.summary, [
        'Original sender: Text one',
        'Original sender: Text two',
        'Original sender: Text three',
      ]);
    }
  });

  for (final merged in [false, true]) {
    test(
        'the ${merged ? 100 : 30} message limit rejects without opening contacts',
        () async {
      final limit = merged ? 100 : 30;
      final selection =
          List.generate(limit + 1, (index) => forwardingSource('$index'));
      expect(await fixture.forward(selection, merged: merged), isFalse);
      expect(fixture.pickerDescriptions, isEmpty);
      expect(fixture.sends, isEmpty);
      expect(fixture.toasts, hasLength(1));
      fixture.toasts.clear();
      expect(
          await fixture.forward(selection.take(limit).toList(), merged: merged),
          isTrue);
      expect(fixture.pickerDescriptions, hasLength(1));
      expect(fixture.sends, hasLength(merged ? 1 : limit));
    });
  }

  test('an ineligible selection is rejected as a whole rather than filtered',
      () async {
    for (final blocked in [
      forwardingSource('failed', status: MessageStatus.failed),
      forwardingSource('private', private: true),
      forwardingSource('unsupported', type: MessageType.custom),
      forwardingSource(''),
      forwardingSource('valid'),
    ]) {
      expect(
          await fixture
              .forward([forwardingSource('valid'), blocked], merged: false),
          isFalse);
    }
    expect(fixture.pickerDescriptions, isEmpty);
    expect(fixture.sends, isEmpty);
    expect(fixture.toasts, hasLength(5));
  });

  test('permissions are checked again after the contact picker returns',
      () async {
    final picker = Completer<dynamic>();
    fixture.onPick = () => picker.future;
    final message = forwardingSource('one');
    final pending = fixture.forward([message], merged: false);
    await flushForwarding();
    message.status = MessageStatus.failed;
    picker.complete({
      'checkedList': [UserInfo(userID: 'target')]
    });
    expect(await pending, isFalse);
    expect(fixture.originals, isEmpty);
    expect(fixture.sends, isEmpty);
    expect(fixture.toasts, hasLength(1));
  });

  test('cancellation and invalid recipients do not construct or send messages',
      () async {
    for (final result in [
      null,
      {'checkedList': <dynamic>[]},
      {'checkedList': 'broken'},
      {
        'checkedList': [UserInfo(userID: 'valid'), UserInfo()]
      },
    ]) {
      fixture.onPick = () async => result;
      expect(await fixture.forward([forwardingSource('one')], merged: false),
          isFalse);
    }
    expect(fixture.originals, isEmpty);
    expect(fixture.sends, isEmpty);
    expect(fixture.reviewRequests, 0);
  });

  test('SDK deletion while choosing recipients invalidates the whole selection',
      () async {
    final picker = Completer<dynamic>();
    fixture.onPick = () => picker.future;
    final pending = fixture.forward(
        [forwardingSource('one'), forwardingSource('two')],
        merged: true);
    await flushForwarding();
    fixture.timeline.removeWhere((message) => message.clientMsgID == 'two');
    picker.complete({
      'checkedList': [UserInfo(userID: 'target')]
    });
    expect(await pending, isFalse);
    expect(fixture.merges, isEmpty);
    expect(fixture.sends, isEmpty);
    expect(fixture.toasts, hasLength(1));
  });

  test(
      'replacement SDK objects are checked and used instead of stale snapshots',
      () async {
    final picker = Completer<dynamic>();
    fixture.onPick = () => picker.future;
    final pending = fixture.forward([forwardingSource('one')], merged: false);
    await flushForwarding();
    final latest = forwardingSource('one');
    latest.textElem!.content = 'Updated source';
    fixture.timeline.assignAll([latest]);
    Message? usedSource;
    fixture.onCreate = (message) async {
      usedSource = message;
      return forwardingSource('created', status: MessageStatus.sending);
    };
    picker.complete({
      'checkedList': [UserInfo(userID: 'target')]
    });
    expect(await pending, isTrue);
    expect(usedSource, same(latest));
    expect(usedSource!.textElem!.content, 'Updated source');
  });

  test('a newly private SDK replacement blocks an old eligible snapshot',
      () async {
    final picker = Completer<dynamic>();
    fixture.onPick = () => picker.future;
    final pending = fixture.forward([forwardingSource('one')], merged: false);
    await flushForwarding();
    fixture.timeline.assignAll([forwardingSource('one', private: true)]);
    picker.complete({
      'checkedList': [UserInfo(userID: 'target')]
    });
    expect(await pending, isFalse);
    expect(fixture.originals, isEmpty);
    expect(fixture.sends, isEmpty);
    expect(fixture.toasts, hasLength(1));
  });

  test('a delivery failure is false even though delivery catches the SDK error',
      () async {
    fixture.onSend = (_, __) async =>
        throw const MessageSendValidationException('transport rejected');
    expect(
        await fixture.forward(
            [forwardingSource('one'), forwardingSource('two')],
            merged: false),
        isFalse);
    expect(fixture.sends, hasLength(1));
    expect(fixture.originals, ['one']);
    expect(fixture.toasts, hasLength(1));
    expect(fixture.toasts.single, isNot('chatSelectionForwardUncertain'));
    expect(fixture.toasts.single, isNot('chatSelectionForwardPartial'));
    expect(fixture.reviewRequests, 0);
  });

  test(
      'the first unknown receipt stops remaining sends and requests review once',
      () async {
    fixture.onPick = () async => {
          'checkedList': [UserInfo(userID: 'first'), UserInfo(userID: 'second')]
        };
    fixture.onSend = (_, __) async => forwardingSource('unrelated-receipt');
    expect(
        await fixture.forward(
            [forwardingSource('one'), forwardingSource('two')],
            merged: false),
        isFalse);
    expect(fixture.sends, hasLength(1));
    expect(fixture.sends.single.target.userID, 'first');
    expect(fixture.originals, ['one']);
    expect(fixture.toasts, ['chatSelectionForwardUncertain']);
    expect(fixture.reviewRequests, 1);
  });

  test('an unconfirmed transport error also requests review without retrying',
      () async {
    fixture.onSend = (_, __) async => throw StateError('connection dropped');
    expect(await fixture.forward([forwardingSource('one')], merged: true),
        isFalse);
    expect(fixture.sends, hasLength(1));
    expect(fixture.toasts, ['chatSelectionForwardUncertain']);
    expect(fixture.reviewRequests, 1);
  });

  test('A accepted then B rejected stops C and exits the retained selection',
      () async {
    fixture.onSend = (message, _) async {
      if (fixture.sends.length == 2) {
        throw const MessageSendValidationException('second rejected');
      }
      return forwardingReceipt(message);
    };
    expect(
        await fixture.forward([
          forwardingSource('A'),
          forwardingSource('B'),
          forwardingSource('C'),
        ], merged: false),
        isFalse);
    expect(fixture.originals, ['A', 'B']);
    expect(fixture.sends, hasLength(2));
    expect(fixture.toasts, ['chatSelectionForwardPartial']);
    expect(fixture.reviewRequests, 1);
  });

  test(
      'first recipient accepted then second rejected stops remaining recipients',
      () async {
    fixture.onPick = () async => {
          'checkedList': [
            UserInfo(userID: 'first'),
            UserInfo(userID: 'second'),
            UserInfo(userID: 'third')
          ]
        };
    fixture.onSend = (message, target) async {
      if (target.userID == 'second') {
        throw const MessageSendValidationException('second rejected');
      }
      return forwardingReceipt(message);
    };
    expect(await fixture.forward([forwardingSource('one')], merged: true),
        isFalse);
    expect(fixture.merges, hasLength(2));
    expect(
        fixture.sends.map((send) => send.target.userID), ['first', 'second']);
    expect(fixture.toasts, ['chatSelectionForwardPartial']);
    expect(fixture.reviewRequests, 1);
  });

  test('construction failure after an accepted message reports only partial',
      () async {
    fixture.onCreate = (message) async {
      if (message.clientMsgID == 'two') throw StateError('create failed');
      return forwardingSource('created', status: MessageStatus.sending);
    };
    expect(
        await fixture.forward([
          forwardingSource('one'),
          forwardingSource('two'),
          forwardingSource('three'),
        ], merged: false),
        isFalse);
    expect(fixture.originals, ['one', 'two']);
    expect(fixture.sends, hasLength(1));
    expect(fixture.toasts, ['chatSelectionForwardPartial']);
    expect(fixture.reviewRequests, 1);
  });

  test('source invalidation after an accepted send reports only partial',
      () async {
    fixture.onSend = (message, _) async {
      fixture.timeline.removeWhere((source) => source.clientMsgID == 'two');
      return forwardingReceipt(message);
    };
    expect(
        await fixture.forward(
            [forwardingSource('one'), forwardingSource('two')],
            merged: false),
        isFalse);
    expect(fixture.originals, ['one']);
    expect(fixture.sends, hasLength(1));
    expect(fixture.toasts, ['chatSelectionForwardPartial']);
    expect(fixture.reviewRequests, 1);
  });

  test('single-message compatibility does not cancel a batch selection',
      () async {
    fixture.onPick = () async => {
          'checkedList': [UserInfo(userID: 'first'), UserInfo(userID: 'second')]
        };
    fixture.onSend = (message, target) async {
      if (target.userID == 'second') {
        throw const MessageSendValidationException('second rejected');
      }
      return forwardingReceipt(message);
    };
    await fixture.controller.forwardMessage(forwardingSource('one'));
    expect(fixture.sends, hasLength(2));
    expect(fixture.toasts, hasLength(1));
    expect(fixture.toasts.single, isNot('chatSelectionForwardPartial'));
    expect(fixture.reviewRequests, 0);
  });

  test('closing during construction stops before transport and leaves no toast',
      () async {
    final creation = Completer<Message>();
    fixture.onCreate = (_) => creation.future;
    final pending = fixture.forward([forwardingSource('one')], merged: false);
    await flushForwarding();
    fixture.closed = true;
    creation.complete(forwardingSource('created'));
    expect(await pending, isFalse);
    expect(fixture.sends, isEmpty);
    expect(fixture.toasts, isEmpty);
    expect(fixture.reviewRequests, 0);
  });

  test('an account change during transport stops the remaining batch',
      () async {
    final transport = Completer<Message>();
    fixture.onSend = (_, __) => transport.future;
    final pending = fixture.forward(
        [forwardingSource('one'), forwardingSource('two')],
        merged: false);
    await flushForwarding();
    fixture.account = 'another-account';
    transport.complete(forwardingReceipt(fixture.sends.single.message));
    expect(await pending, isFalse);
    expect(fixture.originals, ['one']);
    expect(fixture.sends, hasLength(1));
    expect(fixture.toasts, isEmpty);
    expect(fixture.reviewRequests, 0);
  });

  test(
      'source policy changes during construction cannot forward another subset',
      () async {
    final creation = Completer<Message>();
    fixture.onCreate = (_) => creation.future;
    final second = forwardingSource('two');
    final pending =
        fixture.forward([forwardingSource('one'), second], merged: false);
    await flushForwarding();
    second.status = MessageStatus.failed;
    creation.complete(forwardingSource('created'));
    expect(await pending, isFalse);
    expect(fixture.sends, isEmpty);
    expect(fixture.toasts, hasLength(1));
  });

  test('construction exceptions use the existing error toast and return false',
      () async {
    fixture.onMerge = () async => throw StateError('merge failed');
    expect(await fixture.forward([forwardingSource('one')], merged: true),
        isFalse);
    expect(fixture.toasts.single, contains('merge failed'));
    expect(fixture.sends, isEmpty);
  });

  test(
      'single message APIs remain compatible without a separate selection page',
      () async {
    await fixture.controller.forwardMessage(forwardingSource('one'));
    await fixture.controller.mergeForward(forwardingSource('two'));
    expect(fixture.pickerDescriptions, hasLength(2));
    expect(fixture.originals, ['one']);
    expect(fixture.merges.single.ids, ['two']);
    expect(fixture.sends, hasLength(2));
  });
}
