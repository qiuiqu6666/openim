import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/editing/conversation_edit_controller.dart';

ConversationInfo _conversation(String id) =>
    ConversationInfo(conversationID: id);

void main() {
  test('selection belongs to editing mode and cannot be modified externally',
      () {
    final controller = ConversationEditController();
    addTearDown(controller.dispose);

    controller.toggleSelection('a');
    expect(controller.selectedIds, isEmpty);
    controller.toggleEditing();
    controller.toggleSelection('');
    controller.toggleSelection('a');
    expect(controller.selectedIds, {'a'});
    expect(() => controller.selectedIds.add('b'), throwsUnsupportedError);
    controller.toggleSelection('a');
    expect(controller.selectedIds, isEmpty);
    controller.toggleSelection('b');
    controller.toggleEditing();
    expect(controller.editing, isFalse);
    expect(controller.selectedIds, isEmpty);
  });

  test('selected actions are filtered to a stable visible scope', () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    controller.toggleSelection('a');
    controller.toggleSelection('b');
    controller.toggleSelection('outside');
    final visible = [
      _conversation('a'),
      _conversation('b'),
      _conversation('a')
    ];
    final actedOn = <String>[];

    await controller.execute(
      conversations: visible,
      action: (conversation) async {
        actedOn.add(conversation.conversationID);
        visible
          ..clear()
          ..add(_conversation('outside'));
      },
    );

    expect(actedOn, ['a', 'b']);
    expect(controller.busy, isFalse);
    expect(controller.editing, isFalse);
    expect(controller.selectedIds, isEmpty);
  });

  test('unselected archive or delete cannot act on the whole scope', () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    var calls = 0;
    await controller.execute(
      conversations: [_conversation('a')],
      action: (_) async => calls++,
    );
    expect(calls, 0);
    expect(controller.editing, isTrue);
    expect(controller.busy, isFalse);
  });

  test('read all uses the supplied scope only when nothing is selected',
      () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    final actedOn = <String>[];
    await controller.execute(
      conversations: [_conversation('a'), _conversation('b')],
      allWhenEmpty: true,
      action: (conversation) async => actedOn.add(conversation.conversationID),
    );
    expect(actedOn, ['a', 'b']);
    expect(controller.editing, isFalse);

    controller.toggleEditing();
    controller.toggleSelection('b');
    actedOn.clear();
    await controller.execute(
      conversations: [_conversation('a'), _conversation('b')],
      allWhenEmpty: true,
      action: (conversation) async => actedOn.add(conversation.conversationID),
    );
    expect(actedOn, ['b']);
  });

  test('missing selected rows exit editing without acting on unrelated rows',
      () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    controller.toggleSelection('removed');
    final actedOn = <String>[];
    await controller.execute(
      conversations: [_conversation('unrelated')],
      action: (conversation) async => actedOn.add(conversation.conversationID),
    );
    expect(actedOn, isEmpty);
    expect(controller.editing, isFalse);
    expect(controller.selectedIds, isEmpty);
  });

  test('read all uses the new folder when only hidden rows were selected',
      () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    controller.toggleSelection('old-folder-chat');
    final actedOn = <String>[];
    await controller.execute(
      conversations: [
        _conversation('new-folder-a'),
        _conversation('new-folder-b')
      ],
      allWhenEmpty: true,
      action: (info) async => actedOn.add(info.conversationID),
    );
    expect(actedOn, ['new-folder-a', 'new-folder-b']);
    expect(controller.editing, isFalse);
  });

  test('mark read ignores hidden selections while honoring visible selection',
      () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    controller.toggleSelection('old-folder-chat');
    controller.toggleSelection('visible-selected');
    final actedOn = <String>[];
    await controller.execute(
      conversations: [
        _conversation('visible-selected'),
        _conversation('visible-other')
      ],
      allWhenEmpty: true,
      action: (info) async => actedOn.add(info.conversationID),
    );
    expect(actedOn, ['visible-selected']);
  });

  test('the first failure stops execution and retains the selection', () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    controller.toggleSelection('a');
    controller.toggleSelection('b');
    final actedOn = <String>[];
    await expectLater(
      controller.execute(
        conversations: [_conversation('a'), _conversation('b')],
        action: (conversation) async {
          actedOn.add(conversation.conversationID);
          throw StateError('SDK action failed');
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(actedOn, ['a']);
    expect(controller.busy, isFalse);
    expect(controller.editing, isTrue);
    expect(controller.selectedIds, {'a', 'b'});
  });

  test('pending actions disable reentry and selection changes', () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    controller.toggleSelection('a');
    final gate = Completer<void>();
    var calls = 0;
    final pending = controller.execute(
      conversations: [_conversation('a')],
      action: (_) {
        calls++;
        return gate.future;
      },
    );
    expect(controller.busy, isTrue);
    controller.toggleEditing();
    controller.toggleSelection('b');
    await controller.execute(
      conversations: [_conversation('a')],
      action: (_) async => calls++,
    );
    expect(calls, 1);
    expect(controller.editing, isTrue);
    expect(controller.selectedIds, {'a'});
    gate.complete();
    await pending;
    expect(controller.busy, isFalse);
    expect(controller.editing, isFalse);
  });

  test('disposal stops queued actions and never notifies after disposal',
      () async {
    final controller = ConversationEditController()..toggleEditing();
    final gate = Completer<void>();
    final actedOn = <String>[];
    var notifications = 0;
    controller.addListener(() => notifications++);
    final pending = controller.execute(
      conversations: [_conversation('a'), _conversation('b')],
      allWhenEmpty: true,
      action: (conversation) {
        actedOn.add(conversation.conversationID);
        return gate.future;
      },
    );
    expect(notifications, 1);
    controller.dispose();
    gate.complete();
    await pending;
    expect(actedOn, ['a']);
    expect(notifications, 1);
    controller.toggleEditing();
    controller.toggleSelection('c');
    await controller.execute(
      conversations: [_conversation('c')],
      allWhenEmpty: true,
      action: (conversation) async => actedOn.add(conversation.conversationID),
    );
    expect(actedOn, ['a']);
    expect(controller.editing, isFalse);
    expect(controller.busy, isFalse);
    expect(controller.selectedIds, isEmpty);
  });
}
