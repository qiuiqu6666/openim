import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_controller.dart';
import 'package:openim_common/openim_common.dart';

import 'support/selection_test_messages.dart';

class _SelectionFixture {
  _SelectionFixture(List<Message> initial) : messages = initial {
    controller = MessageSelectionController(
      messages: () => messages,
      isClosed: () => closed,
      onStart: () => starts++,
      deleteMessages: (messages) async {
        deletions.add(List.of(messages));
        return await onDelete?.call(messages) ?? true;
      },
      forwardMessages: (messages, {required merged}) async {
        forwards.add((messages: List.of(messages), merged: merged));
        return await onForward?.call(messages, merged: merged) ?? true;
      },
    );
  }

  List<Message> messages;
  bool closed = false, disposed = false;
  int starts = 0;
  late final MessageSelectionController controller;
  final deletions = <List<Message>>[];
  final forwards = <({List<Message> messages, bool merged})>[];
  Future<bool> Function(List<Message>)? onDelete;
  Future<bool> Function(List<Message>, {required bool merged})? onForward;

  void dispose() {
    if (disposed) return;
    disposed = true;
    controller.dispose();
  }
}

void main() {
  test('entry preselects a loaded message and cancel clears the mode', () {
    final first = selectionMessage('one');
    final second = selectionMessage('two');
    final fixture = _SelectionFixture([first, second]);
    addTearDown(fixture.dispose);
    final selection = fixture.controller;

    expect(selection.active, isFalse);
    selection.enter(first);
    expect(selection.active, isTrue);
    expect(selection.selectedMessages, [first]);
    expect(selection.isSelected(second), isFalse);
    expect(fixture.starts, 1);
    selection.toggle(second);
    expect(selection.selectedMessages, [first, second]);
    selection.cancel();
    expect(selection.active, isFalse);
    expect(selection.count, 0);
    expect(selection.allSelected, isFalse);
    selection.toggle(first);
    expect(selection.count, 0);
    selection.enter(second);
    expect(selection.selectedMessages, [second]);
    expect(fixture.starts, 2);
  });

  test('entry rejects unloaded IDs, empty IDs, typing and notifications', () {
    final invalid = [
      selectionMessage(''),
      selectionMessage('invalid-type', contentType: 0),
      selectionMessage('typing', contentType: MessageType.typing),
      selectionMessage('notice', contentType: 1001),
      selectionClaimNotice('claim-notice'),
      selectionMessage('expired', expired: true),
      selectionMessage('deleted-by-friend',
          contentType: MessageType.custom,
          customData: '{"customType":${CustomMessageType.deletedByFriend}}'),
      selectionMessage('blocked-by-friend',
          contentType: MessageType.custom,
          customData: '{"customType":${CustomMessageType.blockedByFriend}}'),
      selectionMessage('removed-from-group',
          contentType: MessageType.custom,
          customData: '{"customType":${CustomMessageType.removedFromGroup}}'),
      selectionMessage('group-disbanded',
          contentType: MessageType.custom,
          customData: '{"customType":${CustomMessageType.groupDisbanded}}'),
    ];
    final fixture = _SelectionFixture(invalid);
    addTearDown(fixture.dispose);
    for (final message in [...invalid, selectionMessage('unloaded')]) {
      fixture.controller.enter(message);
      expect(fixture.controller.active, isFalse);
      expect(fixture.controller.count, 0);
    }
    expect(fixture.starts, 0);
  });

  test('select all has no 100-message cap and only selects the loaded window',
      () {
    final loaded = List.generate(125, (i) => selectionMessage('loaded-$i'));
    final fixture = _SelectionFixture([
      ...loaded,
      loaded.first,
      selectionMessage('typing', contentType: MessageType.typing),
      selectionMessage('notice', contentType: 1001),
      selectionClaimNotice('claim-notice'),
    ]);
    addTearDown(fixture.dispose);
    final selection = fixture.controller..enter(loaded.first);
    selection.toggleAll();
    expect(selection.count, 125);
    expect(selection.selectedMessages, loaded);
    expect(selection.allSelected, isTrue);

    final arrived = selectionMessage('newly-loaded');
    fixture.messages.add(arrived);
    selection.sync();
    expect(selection.count, 125);
    expect(selection.isSelected(arrived), isFalse);
    expect(selection.allSelected, isFalse);
    selection.toggleAll();
    expect(selection.count, 126);
    expect(selection.allSelected, isTrue);
    selection.toggleAll();
    expect(selection.count, 0);
    expect(selection.active, isTrue);
    expect(selection.allSelected, isFalse);
  });

  test('selection follows live message order and prunes disappearance', () {
    final first = selectionMessage('one');
    final second = selectionMessage('two');
    final third = selectionMessage('three');
    final fixture = _SelectionFixture([first, second, third]);
    addTearDown(fixture.dispose);
    final selection = fixture.controller..enter(third);
    selection.toggle(first);
    expect(selection.selectedMessages, [first, third]);
    fixture.messages = [second, first];
    selection.sync();
    expect(selection.selectedMessages, [first]);
    expect(selection.isSelected(third), isFalse);
    fixture.messages = [second];
    selection.sync();
    expect(selection.count, 0);
    expect(selection.active, isTrue);
    selection.toggle(selectionMessage('absent'));
    expect(selection.count, 0);
  });

  test('live arrival notifies UI even when the selected IDs have not changed',
      () {
    final first = selectionMessage('one');
    final fixture = _SelectionFixture([first]);
    addTearDown(fixture.dispose);
    final selection = fixture.controller..enter(first);
    expect(selection.allSelected, isTrue);
    var notifications = 0;
    selection.addListener(() => notifications++);
    fixture.messages.add(selectionMessage('new'));
    selection.sync();
    expect(selection.allSelected, isFalse);
    expect(selection.count, 1);
    expect(notifications, 1);
  });

  test('non-forwardable selection can still be deleted', () async {
    final unsent = selectionMessage('failed', status: MessageStatus.failed);
    final privateMessage = selectionMessage('private', private: true);
    final fixture = _SelectionFixture([unsent, privateMessage]);
    addTearDown(fixture.dispose);
    fixture.onForward = (_, {required merged}) async => false;
    final selection = fixture.controller..enter(unsent);
    selection.toggle(privateMessage);

    await selection.forwardSelected(merged: false);
    expect(fixture.forwards.single.messages, [unsent, privateMessage]);
    expect(selection.active, isTrue);
    expect(selection.count, 2);
    var confirmedCount = 0;
    await selection.deleteSelected(confirm: (count) async {
      confirmedCount = count;
      return true;
    });
    expect(confirmedCount, 2);
    expect(fixture.deletions.single, [unsent, privateMessage]);
    expect(selection.active, isFalse);
    expect(selection.count, 0);
  });

  test('declined deletion retains selection and does not delete', () async {
    final message = selectionMessage('one');
    final fixture = _SelectionFixture([message]);
    addTearDown(fixture.dispose);
    final selection = fixture.controller..enter(message);
    await selection.deleteSelected(confirm: (_) async => false);
    expect(fixture.deletions, isEmpty);
    expect(selection.selectedMessages, [message]);
    expect(selection.active, isTrue);
    expect(selection.busy, isFalse);
  });

  test('confirmation only deletes messages still present after the delay',
      () async {
    final first = selectionMessage('one');
    final second = selectionMessage('two');
    final fixture = _SelectionFixture([first, second]);
    addTearDown(fixture.dispose);
    final selection = fixture.controller..enter(first);
    selection.toggle(second);
    final confirm = Completer<bool>();
    final pending = selection.deleteSelected(confirm: (_) => confirm.future);
    fixture.messages.remove(first);
    selection.sync();
    confirm.complete(true);
    await pending;
    expect(fixture.deletions.single, [second]);
    expect(selection.active, isFalse);
  });

  test('all messages disappearing while confirmation opens prevents deletion',
      () async {
    final message = selectionMessage('gone');
    final fixture = _SelectionFixture([message]);
    addTearDown(fixture.dispose);
    final selection = fixture.controller..enter(message);
    final confirm = Completer<bool>();
    final pending = selection.deleteSelected(confirm: (_) => confirm.future);
    fixture.messages.clear();
    selection.sync();
    confirm.complete(true);
    await pending;
    expect(fixture.deletions, isEmpty);
    expect(selection.count, 0);
    expect(selection.busy, isFalse);
  });

  test('busy forwarding blocks duplicate actions and selection edits',
      () async {
    final first = selectionMessage('one');
    final second = selectionMessage('two');
    final fixture = _SelectionFixture([first, second]);
    addTearDown(fixture.dispose);
    final response = Completer<bool>();
    fixture.onForward = (_, {required merged}) => response.future;
    final selection = fixture.controller..enter(first);
    final pending = selection.forwardSelected(merged: true);
    expect(selection.busy, isTrue);
    selection.toggle(second);
    selection.toggleAll();
    selection.enter(second);
    await selection.forwardSelected(merged: false);
    var confirmations = 0;
    await selection.deleteSelected(confirm: (_) async {
      confirmations++;
      return true;
    });
    expect(fixture.forwards, hasLength(1));
    expect(fixture.forwards.single.merged, isTrue);
    expect(fixture.deletions, isEmpty);
    expect(confirmations, 0);
    expect(selection.selectedMessages, [first]);
    response.complete(false);
    await pending;
    expect(selection.busy, isFalse);
    expect(selection.active, isTrue);
  });

  test('cancel during forwarding prevents late completion and reentry',
      () async {
    final first = selectionMessage('one');
    final second = selectionMessage('two');
    final fixture = _SelectionFixture([first, second]);
    addTearDown(fixture.dispose);
    final response = Completer<bool>();
    fixture.onForward = (_, {required merged}) => response.future;
    final selection = fixture.controller..enter(first);
    final pending = selection.forwardSelected(merged: false);
    selection.cancel();
    expect(selection.active, isFalse);
    expect(selection.count, 0);
    expect(selection.busy, isTrue);
    selection.enter(second);
    expect(selection.active, isFalse);
    response.complete(true);
    await pending;
    expect(selection.active, isFalse);
    expect(selection.busy, isFalse);
    selection.enter(second);
    expect(selection.selectedMessages, [second]);
  });

  test('cancel during confirmation prevents the deletion request', () async {
    final message = selectionMessage('one');
    final fixture = _SelectionFixture([message]);
    addTearDown(fixture.dispose);
    final confirm = Completer<bool>();
    final selection = fixture.controller..enter(message);
    final pending = selection.deleteSelected(confirm: (_) => confirm.future);
    selection.cancel();
    confirm.complete(true);
    await pending;
    expect(fixture.deletions, isEmpty);
    expect(selection.active, isFalse);
    expect(selection.busy, isFalse);
  });

  test('session invalidation clears mode and rejects delayed confirmation',
      () async {
    final message = selectionMessage('old-session');
    final fixture = _SelectionFixture([message]);
    addTearDown(fixture.dispose);
    final confirm = Completer<bool>();
    final selection = fixture.controller..enter(message);
    final pending = selection.deleteSelected(confirm: (_) => confirm.future);
    fixture.closed = true;
    selection.sync();
    expect(selection.active, isFalse);
    confirm.complete(true);
    await pending;
    expect(fixture.deletions, isEmpty);
    selection.enter(message);
    expect(selection.active, isFalse);
    expect(selection.count, 0);
  });

  test('disposing during forwarding tolerates the late completion', () async {
    final message = selectionMessage('old-page');
    final fixture = _SelectionFixture([message]);
    addTearDown(fixture.dispose);
    final response = Completer<bool>();
    fixture.onForward = (_, {required merged}) => response.future;
    final selection = fixture.controller..enter(message);
    final pending = selection.forwardSelected(merged: false);
    fixture.dispose();
    response.complete(true);
    await pending;
    expect(fixture.forwards, hasLength(1));
    expect(selection.count, 0);
    expect(selection.busy, isFalse);
  });

  test('failed operation releases busy and preserves retry selection',
      () async {
    final message = selectionMessage('retry');
    final fixture = _SelectionFixture([message]);
    addTearDown(fixture.dispose);
    fixture.onForward =
        (_, {required merged}) async => throw StateError('offline');
    final selection = fixture.controller..enter(message);
    await expectLater(
        selection.forwardSelected(merged: false), throwsStateError);
    expect(selection.busy, isFalse);
    expect(selection.active, isTrue);
    expect(selection.selectedMessages, [message]);
  });
}
