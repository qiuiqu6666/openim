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

  test('done releases a pending batch and never starts its remaining targets',
      () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    controller.toggleSelection('a');
    controller.toggleSelection('b');
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final calls = <String>[];
    final pending = controller.execute(
      conversations: [_conversation('a'), _conversation('b')],
      action: (conversation) {
        calls.add(conversation.conversationID);
        return gate.future;
      },
    );
    expect(controller.busy, isTrue);
    controller.toggleSelection('c');
    expect(controller.selectedIds, {'a', 'b'});
    await controller.execute(
      conversations: [_conversation('a')],
      action: (_) async => calls.add('unexpected-reentry'),
    );
    expect(calls, ['a']);

    controller.toggleEditing();
    expect(controller.editing, isFalse);
    expect(controller.busy, isFalse);
    expect(controller.selectedIds, isEmpty);
    await pending;
    expect(gate.isCompleted, isFalse,
        reason: 'Done must release the operation without waiting for the SDK.');
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['a']);
    expect(controller.busy, isFalse);
    expect(controller.editing, isFalse);
  });

  for (final lateFailure in [false, true]) {
    test('old completion cannot change the next busy edit ($lateFailure)',
        () async {
      final controller = ConversationEditController()..toggleEditing();
      addTearDown(controller.dispose);
      controller.toggleSelection('old-a');
      controller.toggleSelection('old-b');
      final oldGate = Completer<void>();
      final newGate = Completer<void>();
      addTearDown(() {
        for (final gate in [oldGate, newGate]) {
          if (!gate.isCompleted) gate.complete();
        }
      });
      final calls = <String>[];
      final previous = controller.execute(
        conversations: [_conversation('old-a'), _conversation('old-b')],
        action: (conversation) {
          calls.add(conversation.conversationID);
          return oldGate.future;
        },
      );
      controller.toggleEditing();
      expect(oldGate.isCompleted, isFalse);
      controller.toggleEditing();
      controller.toggleSelection('new');
      final current = controller.execute(
        conversations: [_conversation('new')],
        action: (conversation) {
          calls.add(conversation.conversationID);
          return newGate.future;
        },
      );
      expect(controller.editing, isTrue);
      expect(controller.busy, isTrue);
      expect(controller.selectedIds, {'new'});
      var notifications = 0;
      controller.addListener(() => notifications++);
      // Reenter before the cancelled operation gets to run its old finally.
      await previous;
      expect(controller.editing, isTrue);
      expect(controller.busy, isTrue);
      expect(controller.selectedIds, {'new'});
      expect(notifications, 0);
      if (lateFailure) {
        oldGate.completeError(StateError('Late cancelled SDK failure'));
      } else {
        oldGate.complete();
      }
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['old-a', 'new']);
      expect(controller.editing, isTrue);
      expect(controller.busy, isTrue);
      expect(controller.selectedIds, {'new'});
      expect(notifications, 0,
          reason: 'An abandoned operation must not publish into a new edit.');
      newGate.complete();
      await current;
      expect(controller.editing, isFalse);
      expect(controller.busy, isFalse);
      expect(controller.selectedIds, isEmpty);
    });
  }

  test('a resolved SDK error cannot escape after its edit is replaced',
      () async {
    final controller = ConversationEditController()..toggleEditing();
    addTearDown(controller.dispose);
    controller.toggleSelection('old-a');
    controller.toggleSelection('old-b');
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    addTearDown(() {
      for (final gate in [oldGate, newGate]) {
        if (!gate.isCompleted) gate.complete();
      }
    });
    final failure = StateError('Resolved SDK failure');
    final calls = <String>[];
    var errorDeliveries = 0;
    Future<void>? replacement;
    final previous = runZoned(
      () => controller.execute(
        conversations: [_conversation('old-a'), _conversation('old-b')],
        action: (conversation) {
          calls.add(conversation.conversationID);
          return oldGate.future;
        },
      ),
      zoneSpecification: ZoneSpecification(
        registerBinaryCallback: <R, T1, T2>(Zone self, ZoneDelegate parent,
            Zone zone, R Function(T1, T2) callback) {
          final registered = parent.registerBinaryCallback(zone, callback);
          return (T1 first, T2 second) {
            if (identical(first, failure) && ++errorDeliveries == 2) {
              // The first delivery lets Future.any choose the SDK error. The
              // second is execute's await continuation: replace the edit before
              // that continuation can report its old error or run its finally.
              controller.toggleEditing();
              controller.toggleEditing();
              controller.toggleSelection('new');
              replacement = controller.execute(
                conversations: [_conversation('new')],
                action: (conversation) {
                  calls.add(conversation.conversationID);
                  return newGate.future;
                },
              );
            }
            return registered(first, second);
          };
        },
      ),
    );
    final completion = expectLater(previous, completes);
    oldGate.completeError(failure);
    await completion;
    expect(errorDeliveries, 2,
        reason: 'Cancellation must occur after the error wins the SDK race.');
    expect(replacement, isNotNull);
    expect(calls, ['old-a', 'new']);
    expect(controller.editing, isTrue);
    expect(controller.busy, isTrue);
    expect(controller.selectedIds, {'new'});
    newGate.complete();
    await replacement;
    expect(controller.editing, isFalse);
    expect(controller.busy, isFalse);
    expect(controller.selectedIds, isEmpty);
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
    await pending;
    expect(gate.isCompleted, isFalse,
        reason: 'Disposal also releases a pending SDK wait immediately.');
    gate.complete();
    await Future<void>.delayed(Duration.zero);
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
