import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_controller.dart';
import 'package:openim_common/openim_common.dart';

import 'support/selection_test_messages.dart';

MessageSelectionController _selection(List<Message> messages,
        {Future<bool> Function()? forward}) =>
    MessageSelectionController(
      messages: () => messages,
      isClosed: () => false,
      onStart: () {},
      deleteMessages: (_) async => true,
      forwardMessages: (_, {required merged}) =>
          forward?.call() ?? Future.value(false),
    );

void main() {
  test('range uses timeline indices and restores baseline when it shrinks', () {
    final messages = List.generate(8, (i) => selectionMessage('m-$i'));
    final selection = _selection(messages);
    addTearDown(selection.dispose);
    selection.enter(messages.first);
    selection.toggle(messages.last);
    final baseline = Set.of(selection.selectedIDs);
    selection.updateDragRange('m-2', 'm-5', baseline: baseline, selected: true);
    expect(selection.selectedIDs, {'m-0', 'm-2', 'm-3', 'm-4', 'm-5', 'm-7'});
    selection.updateDragRange('m-2', 'm-3', baseline: baseline, selected: true);
    expect(selection.selectedIDs, {'m-0', 'm-2', 'm-3', 'm-7'});
    selection.updateDragRange('m-2', 'm-1', baseline: baseline, selected: true);
    expect(selection.selectedIDs, {'m-0', 'm-1', 'm-2', 'm-7'});
    expect(baseline, {'m-0', 'm-7'});
  });

  test('clearing range restores selected items outside the current endpoint',
      () {
    final messages = List.generate(8, (i) => selectionMessage('m-$i'));
    final selection = _selection(messages);
    addTearDown(selection.dispose);
    selection.enter(messages.first);
    for (final index in [2, 3, 4, 7]) {
      selection.toggle(messages[index]);
    }
    final baseline = Set.of(selection.selectedIDs);
    selection.updateDragRange('m-3', 'm-5',
        baseline: baseline, selected: false);
    expect(selection.selectedIDs, {'m-0', 'm-2', 'm-7'});
    selection.updateDragRange('m-3', 'm-2',
        baseline: baseline, selected: false);
    expect(selection.selectedIDs, {'m-0', 'm-4', 'm-7'});
    selection.updateDragRange('m-3', 'm-2',
        baseline: baseline, selected: false);
    expect(selection.selectedIDs, {'m-0', 'm-4', 'm-7'});
  });

  test('range order comes from loaded timeline rather than message IDs', () {
    final messages = ['z', 'a', 'm', 'c'].map(selectionMessage).toList();
    final selection = _selection(messages);
    addTearDown(selection.dispose);
    selection.enter(messages.last);
    final baseline = Set.of(selection.selectedIDs);
    selection.updateDragRange('z', 'm', baseline: baseline, selected: true);
    expect(selection.selectedMessages, messages);
  });

  test('notification and expired content inside a range remains unselected',
      () {
    final messages = [
      selectionMessage('start'),
      selectionMessage('notice', contentType: 1001),
      selectionMessage('expired', expired: true),
      selectionClaimNotice('claim'),
      selectionMessage('removed-from-group',
          contentType: MessageType.custom,
          customData: '{"customType":${CustomMessageType.removedFromGroup}}'),
      selectionMessage('group-disbanded',
          contentType: MessageType.custom,
          customData: '{"customType":${CustomMessageType.groupDisbanded}}'),
      selectionMessage('end'),
    ];
    final selection = _selection(messages);
    addTearDown(selection.dispose);
    selection.enter(messages.first);
    selection.updateDragRange('start', 'end',
        baseline: Set.of(selection.selectedIDs), selected: true);
    expect(selection.selectedIDs, {'start', 'end'});
  });

  test('missing endpoints and inactive drag updates leave selection unchanged',
      () {
    final messages = [selectionMessage('one'), selectionMessage('two')];
    final selection = _selection(messages);
    addTearDown(selection.dispose);
    selection.enter(messages.first);
    final baseline = Set.of(selection.selectedIDs);
    selection.updateDragRange('one', 'absent',
        baseline: baseline, selected: true);
    expect(selection.selectedIDs, {'one'});
    selection.cancel();
    selection.updateDragRange('one', 'two', baseline: baseline, selected: true);
    expect(selection.selectedIDs, isEmpty);
  });

  test('busy operation disables range edits until its response returns',
      () async {
    final messages = [selectionMessage('one'), selectionMessage('two')];
    final response = Completer<bool>();
    final selection = _selection(messages, forward: () => response.future);
    addTearDown(selection.dispose);
    selection.enter(messages.first);
    final pending = selection.forwardSelected(merged: false);
    expect(selection.canInteract, isFalse);
    selection.updateDragRange('one', 'two', baseline: {'one'}, selected: true);
    expect(selection.selectedIDs, {'one'});
    response.complete(false);
    await pending;
    expect(selection.canInteract, isTrue);
  });

  test('selected ID snapshot cannot be modified externally', () {
    final message = selectionMessage('one');
    final selection = _selection([message]);
    addTearDown(selection.dispose);
    selection.enter(message);
    expect(() => selection.selectedIDs.add('injected'), throwsUnsupportedError);
    expect(selection.selectedIDs, {'one'});
  });
}
