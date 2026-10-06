import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/navigation/chat_message_focus_controller.dart';
import 'package:openim/pages/chat/navigation/chat_message_focus_tokens.dart';

Message _message(String id) => Message(clientMsgID: id);

void main() {
  testWidgets(
      'highlight starts after positioning and clears after its duration',
      (tester) async {
    final positioned = Completer<bool>();
    final controller = ChatMessageFocusController(
        canFocus: (_) => true, jump: (_) => positioned.future);
    addTearDown(controller.dispose);
    final focus = controller.focus(_message('target'));
    expect(controller.highlightedID.value, isNull);
    positioned.complete(true);
    expect(await focus, isTrue);
    expect(controller.highlightedID.value, 'target');
    await tester.pump(ChatMessageFocusTokens.highlightDuration);
    expect(controller.highlightedID.value, isNull);
  });

  testWidgets(
      'a newer focus owns the highlight when the older jump returns late',
      (tester) async {
    final first = Completer<bool>();
    final second = Completer<bool>();
    final controller = ChatMessageFocusController(
        canFocus: (_) => true,
        jump: (message) =>
            message.clientMsgID == 'first' ? first.future : second.future);
    addTearDown(controller.dispose);
    final olderFocus = controller.focus(_message('first'));
    final newerFocus = controller.focus(_message('second'));
    second.complete(true);
    expect(await newerFocus, isTrue);
    first.complete(true);
    expect(await olderFocus, isFalse);
    expect(controller.highlightedID.value, 'second');
    controller.dispose();
  });

  for (final interrupt in ['cancel', 'dispose', 'owner']) {
    testWidgets('$interrupt prevents late positioning from restoring highlight',
        (tester) async {
      final positioned = Completer<bool>();
      var current = true;
      final controller = ChatMessageFocusController(
          canFocus: (_) => current, jump: (_) => positioned.future);
      addTearDown(controller.dispose);
      final focus = controller.focus(_message('target'));
      if (interrupt == 'cancel') {
        controller.cancel();
      } else if (interrupt == 'dispose') {
        controller.dispose();
      } else {
        current = false;
      }
      positioned.complete(true);
      expect(await focus, isFalse);
      expect(controller.highlightedID.value, isNull);
    });
  }

  testWidgets(
      'a private message expiring during positioning stays unhighlighted',
      (tester) async {
    final positioned = Completer<bool>();
    final target = _message('private');
    final controller = ChatMessageFocusController(
        canFocus: (_) => true, jump: (_) => positioned.future);
    addTearDown(controller.dispose);
    final focus = controller.focus(target);
    target.attachedInfoElem = AttachedInfoElem(
        isPrivateChat: true,
        hasReadTime: DateTime(2020).millisecondsSinceEpoch,
        burnDuration: 1);
    positioned.complete(true);
    expect(await focus, isFalse);
    expect(controller.highlightedID.value, isNull);
  });

  testWidgets('a positioning failure leaves no target highlight',
      (tester) async {
    final controller = ChatMessageFocusController(
        canFocus: (_) => true, jump: (_) async => false);
    addTearDown(controller.dispose);
    expect(await controller.focus(_message('target')), isFalse);
    expect(controller.highlightedID.value, isNull);
  });
}
