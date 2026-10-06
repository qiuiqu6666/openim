import 'dart:async';
import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/chat_message_actions.dart';

Message _message(String? id) => Message(clientMsgID: id);

Message _fund() => Message.fromJson({
      'clientMsgID': 'fund',
      'contentType': MessageType.custom,
      'customElem': {
        'data': jsonEncode({
          'orderID': 'order',
          'biz': 'transfer',
          'currency': 'USDT',
          'amount': '1.000001',
          'status': 'open',
        })
      }
    });

class _Fixture {
  _Fixture() {
    actions = ChatMessageActions(
        conversationID: () => conversationID,
        isClosed: () => closed,
        removeMessage: removed.add,
        showToast: toasts.add,
        deleteFromLocalStorage: (
            {required conversationID, required clientMsgID}) async {
          calls.add((conversation: conversationID, message: clientMsgID));
          await onDelete?.call(clientMsgID);
        });
  }
  late final ChatMessageActions actions;
  String conversationID = 'current-chat';
  bool closed = false;
  final calls = <({String conversation, String message})>[];
  final removed = <String>[];
  final toasts = <String>[];
  Future<void> Function(String)? onDelete;
}

void main() {
  test('local batch deletion removes all successful messages in order',
      () async {
    final fixture = _Fixture();
    final selection = [_message('one'), _message('two')];
    expect(await fixture.actions.deleteMessages(selection), isTrue);
    expect(fixture.calls.map((call) => call.message), ['one', 'two']);
    expect(fixture.calls.map((call) => call.conversation),
        everyElement('current-chat'));
    expect(fixture.removed, ['one', 'two']);
    expect(fixture.toasts, isEmpty);
    expect(selection, hasLength(2));
  });

  test('partial SDK failures continue deleting others and show one summary',
      () async {
    final fixture = _Fixture();
    fixture.onDelete = (id) async {
      if (id != 'two') throw StateError('Unable to delete $id');
    };
    expect(
        await fixture.actions.deleteMessages(
            [_message('one'), _message('two'), _message('three')]),
        isFalse);
    expect(fixture.calls.map((call) => call.message), ['one', 'two', 'three']);
    expect(fixture.removed, ['two']);
    expect(fixture.toasts, ['chatSelectionDeleteFailed']);
  });

  test('financial cards are preserved while ordinary selected messages delete',
      () async {
    final fixture = _Fixture();
    expect(
        await fixture.actions
            .deleteMessages([_message('one'), _fund(), _message('two')]),
        isFalse);
    expect(fixture.calls.map((call) => call.message), ['one', 'two']);
    expect(fixture.removed, ['one', 'two']);
    expect(fixture.toasts, ['chatSelectionDeleteBlocked']);
  });

  test('a financial-only selection never calls SDK deletion', () async {
    final fixture = _Fixture();
    expect(await fixture.actions.deleteMessages([_fund()]), isFalse);
    expect(fixture.calls, isEmpty);
    expect(fixture.removed, isEmpty);
    expect(fixture.toasts, ['chatSelectionDeleteBlocked']);
  });

  test('missing IDs fail the batch but other valid IDs still delete once',
      () async {
    final fixture = _Fixture();
    expect(
        await fixture.actions.deleteMessages(
            [_message(null), _message(''), _message('one'), _message('one')]),
        isFalse);
    expect(fixture.calls.map((call) => call.message), ['one']);
    expect(fixture.removed, ['one']);
    expect(fixture.toasts, ['chatSelectionDeleteFailed']);
  });

  test('closed and empty selections do not touch SDK or visible messages',
      () async {
    final fixture = _Fixture();
    expect(await fixture.actions.deleteMessages([]), isFalse);
    fixture.closed = true;
    expect(await fixture.actions.deleteMessages([_message('one')]), isFalse);
    expect(fixture.calls, isEmpty);
    expect(fixture.removed, isEmpty);
    expect(fixture.toasts, isEmpty);
  });

  for (final switchConversation in [false, true]) {
    test(
        'late deletion cannot update a closed or changed chat ($switchConversation)',
        () async {
      final fixture = _Fixture();
      final deletion = Completer<void>();
      fixture.onDelete = (_) => deletion.future;
      final pending =
          fixture.actions.deleteMessages([_message('one'), _message('two')]);
      if (switchConversation) {
        fixture.conversationID = 'new-chat';
      } else {
        fixture.closed = true;
      }
      deletion.complete();
      expect(await pending, isFalse);
      expect(fixture.calls.map((call) => call.message), ['one']);
      expect(fixture.removed, isEmpty);
      expect(fixture.toasts, isEmpty);
    });
  }

  test(
      'failure after account invalidation stops the rest without a stale toast',
      () async {
    final fixture = _Fixture();
    final deletion = Completer<void>();
    fixture.onDelete = (_) => deletion.future;
    final pending =
        fixture.actions.deleteMessages([_message('one'), _message('two')]);
    fixture.closed = true;
    deletion.completeError(StateError('Late SDK failure'));
    expect(await pending, isFalse);
    expect(fixture.calls, hasLength(1));
    expect(fixture.removed, isEmpty);
    expect(fixture.toasts, isEmpty);
  });
}
